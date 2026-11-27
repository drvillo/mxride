import Toybox.Lang;
import Toybox.Math;

// Wrist-side G-force math. All public floats are in g (1 g = 9.81 m/s^2).
//
// Sensor callback feeds every sample through push(). Once per second the
// outer code calls advanceSecond() then clearSecond() after reading the
// per-second peaks for the FIT record and the view.
//
// The gravity vector is kept in watch-frame coordinates. With the gyro on
// it is rotated by the measured angular velocity each sample and nudged
// toward the measured accel direction with time constant tau ≈ 2 s; without
// the gyro the nudge alone with tau ≈ 3 s does the work. Both are frozen
// while |a| is more than ~0.3 g away from 1 g, so cornering and air do not
// wash the estimate.
//
// Values that cannot be trusted (no fix, no gyro, warmup still running)
// fail safe: they report 0.0 and do not feed session maxima. imuOkPct is
// the share of samples where gravity was considered safe to nudge.
//
// scripts/gforce.py mirrors this math on synthetic traces.
class Gforce {
    private var _rate as Number;
    private var _gyroOn as Boolean;
    private var _dt as Float;
    private var _tau as Float;
    // Unit gravity in watch frame.
    private var _gx as Float = 0.0;
    private var _gy as Float = 0.0;
    private var _gz as Float = 1.0;
    // GPS, per sample.
    private var _hasFix as Boolean = false;
    private var _speedMps as Float = 0.0;
    private var _gpsDvDtG as Float = 0.0;
    // Smoothed |a|^2, in g^2.
    private var _window as Number;
    private var _box as Array<Float>;
    private var _boxI as Number = 0;
    private var _boxN as Number = 0;
    private var _boxSum as Float = 0.0;
    // Per-second peaks. _peakPos = max(load - 1), _peakNeg = min(load - 1).
    // _latPeak/_lonPeak carry the signed value of the second's largest
    // excursion on their axis.
    private var _peakPos as Float = 0.0;
    private var _peakNeg as Float = 0.0;
    private var _latPeak as Float = 0.0;
    private var _lonPeak as Float = 0.0;
    private var _combinedPeak as Float = 0.0;
    // 3 s peak-hold ticks on each ring half.
    private var _holdPos as Float = 0.0;
    private var _holdPosMs as Number = 0;
    private var _holdNeg as Float = 0.0;
    private var _holdNegMs as Number = 0;
    // Landing: a jump accept arms a 500 ms window in which max |a| is kept.
    private var _landPeak as Float = 0.0;
    private var _landLastPeak as Float = 0.0;
    private var _landWindowSamples as Number;
    private var _landLeft as Number = 0;
    private var _landLive as Boolean = false;
    private var _landShowMs as Number = 0;
    // Per-event landing value, written once when a landing window closes
    // and cleared by clearSecond(). RideSession.sample() uses this instead
    // of the session-cumulative _landPeak so lap 2's max_land_g cannot
    // inherit the previous lap's peak when lap 2 has no new landings.
    private var _landEvent as Float = 0.0;
    // Convergence counter: samples where gravity was safe to nudge.
    private var _imuOkSamples as Number = 0;
    private var _imuTotalSamples as Number = 0;
    // Warmup: 2 s of sample accumulation before trusting gravity-derived
    // values. On a cold start the gravity vector is (0,0,1); real wrist
    // orientation needs a couple of seconds of nudging before readings mean
    // anything.
    private var _warmupLeft as Number;

    function initialize(rate as Number, gyroOn as Boolean) {
        _rate = rate > 0 ? rate : 25;
        _gyroOn = gyroOn;
        _dt = (1.0f / _rate.toFloat()).toFloat();
        _tau = gyroOn ? 2.0f : 3.0f;
        _window = _rate >= 50 ? 5 : 3;
        _box = [0.0f, 0.0f, 0.0f, 0.0f, 0.0f] as Array<Float>;
        _landWindowSamples = (500 * _rate) / 1000;
        if (_landWindowSamples < 1) {
            _landWindowSamples = 1;
        }
        _warmupLeft = _rate * 2;
    }

    function rate() as Number {
        return _rate;
    }

    function setSpeed(hasFix as Boolean, speedMps as Float) as Void {
        _hasFix = hasFix;
        _speedMps = speedMps;
    }

    // RideSession calls this once per second from sample(). It gives this
    // class the GPS-derived longitudinal acceleration in g, held steady
    // between updates.
    function noteGpsSecond(prevSpeedMps as Float, curSpeedMps as Float) as Void {
        _gpsDvDtG = ((curSpeedMps - prevSpeedMps) / 9.81f).toFloat();
    }

    // Arm a landing window. Called from the jump detector on accept.
    function armLanding() as Void {
        _landLeft = _landWindowSamples;
        _landLive = true;
        _landLastPeak = 0.0;
    }

    function landingLive() as Boolean {
        return _landLive;
    }

    // Force an open landing window closed and publish its peak into the
    // display value and the per-event value, so the next sample() can
    // attribute the landing to the current lap. Called from
    // RideSession.lap() so that a jump accepted in lap N (and therefore
    // counted in lap N) also contributes its landing G to lap N even when
    // the user presses lap before the 500 ms window elapses. No-op when
    // no window is open.
    function closeLanding() as Void {
        if (!_landLive) {
            return;
        }
        _landLive = false;
        _landLeft = 0;
        if (_landLastPeak > _landPeak) {
            _landPeak = _landLastPeak;
        }
        if (_landLastPeak > _landEvent) {
            _landEvent = _landLastPeak;
        }
        _landShowMs = 3000;
        _landLastPeak = 0.0;
    }

    function push(ax_mg as Number, ay_mg as Number, az_mg as Number, gx_dps as Number, gy_dps as Number, gz_dps as Number) as Void {
        _imuTotalSamples += 1;
        var ax = ax_mg.toFloat() / 1000.0;
        var ay = ay_mg.toFloat() / 1000.0;
        var az = az_mg.toFloat() / 1000.0;
        var mag2 = ax * ax + ay * ay + az * az;
        if (mag2 < 0.000001) {
            mag2 = 0.000001;
        }
        var mag = Math.sqrt(mag2).toFloat();
        var sm = smooth(mag2);
        var smMag = Math.sqrt(sm).toFloat();
        if (_gyroOn) {
            var kdeg = 0.0174532925f;
            var wx = gx_dps.toFloat() * kdeg * _dt;
            var wy = gy_dps.toFloat() * kdeg * _dt;
            var wz = gz_dps.toFloat() * kdeg * _dt;
            _gx = (_gx - (wy * _gz - wz * _gy)).toFloat();
            _gy = (_gy - (wz * _gx - wx * _gz)).toFloat();
            _gz = (_gz - (wx * _gy - wy * _gx)).toFloat();
        }
        var nearRest = mag > 0.7f && mag < 1.3f;
        if (nearRest) {
            var alpha = (_dt / _tau).toFloat();
            if (alpha > 1.0f) {
                alpha = 1.0f;
            }
            _gx = ((1.0f - alpha) * _gx + alpha * (ax / mag)).toFloat();
            _gy = ((1.0f - alpha) * _gy + alpha * (ay / mag)).toFloat();
            _gz = ((1.0f - alpha) * _gz + alpha * (az / mag)).toFloat();
            if (_warmupLeft > 0) {
                _warmupLeft -= 1;
            }
            _imuOkSamples += 1;
        }
        var g2 = _gx * _gx + _gy * _gy + _gz * _gz;
        if (g2 < 0.000001f) {
            _gx = 0.0f;
            _gy = 0.0f;
            _gz = 1.0f;
            g2 = 1.0f;
        }
        var gnorm = Math.sqrt(g2).toFloat();
        _gx = (_gx / gnorm).toFloat();
        _gy = (_gy / gnorm).toFloat();
        _gz = (_gz / gnorm).toFloat();
        var dot = (ax * _gx + ay * _gy + az * _gz).toFloat();
        var ring = (dot - 1.0f).toFloat();
        var ringSm = (smMag - 1.0f).toFloat();
        // Smoothed catches engine vibration & whoops; raw catches a brief
        // freefall. Keep the larger of the two on each half.
        var posCandidate = ring > ringSm ? ring : ringSm;
        var negCandidate = ring < ringSm ? ring : ringSm;
        if (posCandidate > _peakPos) {
            _peakPos = posCandidate;
        }
        if (negCandidate < _peakNeg) {
            _peakNeg = negCandidate;
        }
        if (_landLive) {
            if (mag > _landLastPeak) {
                _landLastPeak = mag;
            }
            _landLeft -= 1;
            if (_landLeft <= 0) {
                _landLive = false;
                if (_landLastPeak > _landPeak) {
                    _landPeak = _landLastPeak;
                }
                if (_landLastPeak > _landEvent) {
                    _landEvent = _landLastPeak;
                }
                _landShowMs = 3000;
            }
        }
        // Horizontal G, projected dynamic accel minus its vertical part.
        var linx = (ax - dot * _gx).toFloat();
        var liny = (ay - dot * _gy).toFloat();
        var linz = (az - dot * _gz).toFloat();
        var horiz2 = linx * linx + liny * liny + linz * linz;
        var horiz = horiz2 > 0.000001f ? Math.sqrt(horiz2).toFloat() : 0.0f;
        // Lateral (cornering) is yaw_rate × speed, when both are available.
        var lat = 0.0f;
        if (_warmupLeft <= 0 && _gyroOn && _hasFix && _speedMps >= 2.8f) {
            var kdps = 0.0174532925f;
            var yaw = (gx_dps.toFloat() * kdps * _gx + gy_dps.toFloat() * kdps * _gy + gz_dps.toFloat() * kdps * _gz).toFloat();
            lat = (_speedMps * yaw / 9.81f).toFloat();
        }
        var lon = _warmupLeft <= 0 ? _gpsDvDtG : 0.0f;
        var absLat = lat >= 0.0f ? lat : -lat;
        var absLon = lon >= 0.0f ? lon : -lon;
        var absLatPeak = _latPeak >= 0.0f ? _latPeak : -_latPeak;
        var absLonPeak = _lonPeak >= 0.0f ? _lonPeak : -_lonPeak;
        if (absLat > absLatPeak) {
            _latPeak = lat;
        }
        if (absLon > absLonPeak) {
            _lonPeak = lon;
        }
        if (horiz > _combinedPeak) {
            _combinedPeak = horiz;
        }
    }

    // RideSession calls this once per second after sampling. It locks in
    // the per-second peak-hold ticks and decays the landing-label timer.
    function advanceSecond() as Void {
        if (_peakPos > _holdPos) {
            _holdPos = _peakPos;
            _holdPosMs = 3000;
        } else if (_holdPosMs > 0) {
            _holdPosMs -= 1000;
            if (_holdPosMs <= 0) {
                _holdPos = _peakPos;
                _holdPosMs = 0;
            }
        }
        if (_peakNeg < _holdNeg) {
            _holdNeg = _peakNeg;
            _holdNegMs = 3000;
        } else if (_holdNegMs > 0) {
            _holdNegMs -= 1000;
            if (_holdNegMs <= 0) {
                _holdNeg = _peakNeg;
                _holdNegMs = 0;
            }
        }
        if (_landShowMs > 0) {
            _landShowMs -= 1000;
            if (_landShowMs < 0) {
                _landShowMs = 0;
            }
        }
    }

    function clearSecond() as Void {
        _peakPos = 0.0;
        _peakNeg = 0.0;
        _latPeak = 0.0;
        _lonPeak = 0.0;
        _combinedPeak = 0.0;
        _landEvent = 0.0;
    }

    function clearLanding() as Void {
        _landPeak = 0.0;
        _landLastPeak = 0.0;
        _landEvent = 0.0;
        _landLive = false;
        _landLeft = 0;
        _landShowMs = 0;
    }

    function ringValue() as Float {
        if (-_peakNeg > _peakPos) {
            return _peakNeg;
        }
        return _peakPos;
    }

    function peakPos() as Float {
        return _peakPos;
    }

    function peakNeg() as Float {
        return _peakNeg;
    }

    function holdPos() as Float {
        return _holdPos;
    }

    function holdNeg() as Float {
        return _holdNeg;
    }

    function latG() as Float {
        return _latPeak;
    }

    function lonG() as Float {
        return _lonPeak;
    }

    function latAbs() as Float {
        return _latPeak >= 0.0f ? _latPeak : (-_latPeak).toFloat();
    }

    function lonAbs() as Float {
        return _lonPeak >= 0.0f ? _lonPeak : (-_lonPeak).toFloat();
    }

    function combinedPeak() as Float {
        return _combinedPeak;
    }

    function landPeak() as Float {
        return _landPeak;
    }

    // Per-event landing value. Non-zero only in the second a landing
    // window closed, otherwise 0. Cleared by clearSecond(). Session and
    // lap maxima feed from this instead of landPeak() so that an idle
    // lap cannot inherit the previous lap's cumulative peak.
    function landEvent() as Float {
        return _landEvent;
    }

    function landShowMs() as Number {
        return _landShowMs;
    }

    function imuOkPct() as Number {
        if (_imuTotalSamples <= 0) {
            return 0;
        }
        var pct = (_imuOkSamples * 100) / _imuTotalSamples;
        if (pct < 0) {
            return 0;
        }
        if (pct > 100) {
            return 100;
        }
        return pct;
    }

    function gravityReady() as Boolean {
        return _warmupLeft <= 0;
    }

    function reset() as Void {
        _gx = 0.0;
        _gy = 0.0;
        _gz = 1.0;
        _peakPos = 0.0;
        _peakNeg = 0.0;
        _holdPos = 0.0;
        _holdNeg = 0.0;
        _holdPosMs = 0;
        _holdNegMs = 0;
        _latPeak = 0.0;
        _lonPeak = 0.0;
        _combinedPeak = 0.0;
        _landPeak = 0.0;
        _landLastPeak = 0.0;
        _landEvent = 0.0;
        _landLive = false;
        _landLeft = 0;
        _landShowMs = 0;
        _imuOkSamples = 0;
        _imuTotalSamples = 0;
        _boxN = 0;
        _boxI = 0;
        _boxSum = 0.0;
        _warmupLeft = _rate * 2;
        _gpsDvDtG = 0.0;
    }

    private function smooth(v as Float) as Float {
        if (_boxN < _window) {
            _box[_boxN] = v;
            _boxN += 1;
            _boxSum = (_boxSum + v).toFloat();
            return (_boxSum / _boxN.toFloat()).toFloat();
        }
        var old = _box[_boxI];
        _box[_boxI] = v;
        _boxI = (_boxI + 1) % _window;
        _boxSum = (_boxSum + v - old).toFloat();
        return (_boxSum / _window.toFloat()).toFloat();
    }
}
