import Toybox.Lang;

// Same gates as scripts/jump_detector.py. Milli-g and deg/s, sum of squares, no sqrt.
// 0 ground, 1 air, 2 landing. A short or mismatched batch calls abort().
class JumpDetector {
    private var _rate as Number;
    private var _gyroOn as Boolean;
    private var _window as Number;
    private var _need as Number;
    private var _box as Array<Number>;
    private var _boxI as Number = 0;
    private var _boxN as Number = 0;
    private var _boxSum as Number = 0;
    private var _state as Number = 0;
    private var _quiet as Number = 0;
    private var _soft as Number = 0;
    private var _airSamples as Number = 0;
    private var _since as Number;
    private var _debounce as Number;
    private var _landSamples as Number = 0;
    private var _landNeed as Number;
    private var _landFlag as Boolean = false;
    private var _gyroPulse as Boolean = false;
    private var _minSs as Number = 2000000000;
    private var _hasFix as Boolean = false;
    private var _kmh as Number = 0;
    private var _count as Number = 0;
    private var _totalMs as Number = 0;
    private var _longestMs as Number = 0;
    private var _lastMs as Number = 0;
    private var _lastScore as Number = 0;
    private var _lapCount as Number = 0;
    private var _lapAirMs as Number = 0;
    private var _lapLongestMs as Number = 0;
    private var _recent as Array<Number>;
    private var _recentN as Number = 0;
    private var _recordMs as Number = 0;

    function initialize(rate as Number, gyroOn as Boolean) {
        _rate = rate > 0 ? rate : 1;
        _gyroOn = gyroOn;
        _window = rate >= 50 ? 5 : 3;
        _need = _window;
        _box = [0, 0, 0, 0, 0] as Array<Number>;
        _debounce = (300 * _rate) / 1000;
        if (_debounce < 1) {
            _debounce = 1;
        }
        _since = _debounce;
        _landNeed = (200 * _rate) / 1000;
        if (_landNeed < 1) {
            _landNeed = 1;
        }
        _recent = [] as Array<Number>;
        for (var i = 0; i < 32; i++) {
            _recent.add(0);
        }
    }

    function rate() as Number {
        return _rate;
    }

    function gyroOn() as Boolean {
        return _gyroOn;
    }

    function setSpeed(hasFix as Boolean, kmh as Number) as Void {
        _hasFix = hasFix;
        _kmh = kmh;
    }

    function abort() as Void {
        _state = 0;
        _quiet = 0;
        _soft = 0;
        _since = 0;
        _boxN = 0;
        _boxSum = 0;
        _boxI = 0;
    }

    function push(ax as Number, ay as Number, az as Number, gx as Number, gy as Number, gz as Number) as Boolean {
        ax = clamp(ax, 8000);
        ay = clamp(ay, 8000);
        az = clamp(az, 8000);
        var ss = ax * ax + ay * ay + az * az;
        var sm = smooth(ss);
        var gss = 0;
        if (_gyroOn) {
            gx = clamp(gx, 2000);
            gy = clamp(gy, 2000);
            gz = clamp(gz, 2000);
            gss = gx * gx + gy * gy + gz * gz;
        }
        var axis = ax;
        if (ay > axis) {
            axis = ay;
        }
        if (az > axis) {
            axis = az;
        }
        if (-ax > axis) {
            axis = -ax;
        }
        if (-ay > axis) {
            axis = -ay;
        }
        if (-az > axis) {
            axis = -az;
        }
        if (_state == 0) {
            if (_since < _debounce) {
                _since += 1;
                _quiet = 0;
                _soft = 0;
            } else if (sm < 202500) {
                _quiet += 1;
                _soft = 0;
            } else if (_gyroOn && sm < 490000 && gss >= 6400) {
                _soft += 1;
                _quiet = 0;
            } else {
                _quiet = 0;
                _soft = 0;
            }
            if (_quiet >= _need || _soft >= _need) {
                _state = 1;
                _airSamples = _need;
                _gyroPulse = _soft >= _need;
                _minSs = sm;
                _landFlag = axis >= 2000;
                _quiet = 0;
                _soft = 0;
            }
            return false;
        }
        if (_state == 1) {
            if (gss >= 6400) {
                _gyroPulse = true;
            }
            if (sm < _minSs) {
                _minSs = sm;
            }
            if (axis >= 2000) {
                _landFlag = true;
            }
            if (sm > 640000) {
                _state = 2;
                _landSamples = 0;
            } else {
                _airSamples += 1;
            }
            return false;
        }
        if (axis >= 2000) {
            _landFlag = true;
        }
        _landSamples += 1;
        if (_landSamples < _landNeed) {
            return false;
        }
        var accepted = finish();
        _state = 0;
        _since = 0;
        _quiet = 0;
        _soft = 0;
        return accepted;
    }

    function count() as Number {
        return _count;
    }

    function totalMs() as Number {
        return _totalMs;
    }

    function longestMs() as Number {
        return _longestMs;
    }

    function lastMs() as Number {
        return _lastMs;
    }

    function lastScore() as Number {
        return _lastScore;
    }

    function lapCount() as Number {
        return _lapCount;
    }

    function lapAirMs() as Number {
        return _lapAirMs;
    }

    function lapLongestMs() as Number {
        return _lapLongestMs;
    }

    function resetLap() as Void {
        _lapCount = 0;
        _lapAirMs = 0;
        _lapLongestMs = 0;
    }

    function recent() as Array<Number> {
        return _recent;
    }

    function takeRecord() as Number {
        var ms = _recordMs;
        _recordMs = 0;
        return ms;
    }

    // Live air time (ms) while the detector thinks we are in phase 1. The
    // view uses this for the "AIR 0.6" label. Returns 0 when on the ground
    // or during the short landing-spike window; the view falls back to the
    // normal G line in that case.
    function airLiveMs() as Number {
        if (_state != 1) {
            return 0;
        }
        return (_airSamples * 1000) / _rate;
    }

    private function finish() as Boolean {
        var ms = (_airSamples * 1000) / _rate;
        var floor = _gyroPulse ? 250 : 300;
        var ok = ms >= floor || (_landFlag && ms >= 200 && ms < 400);
        if (_hasFix && _kmh < 8) {
            ok = false;
        }
        if (!ok) {
            return false;
        }
        var score = 0;
        if (_minSs < 202500) {
            score += 2;
        }
        if (_gyroPulse) {
            score += 2;
        }
        if (_landFlag) {
            score += 1;
        }
        if (!_hasFix || _kmh >= 8) {
            score += 1;
        }
        if (ms >= 500) {
            score += 2;
        }
        _count += 1;
        _totalMs += ms;
        if (ms > _longestMs) {
            _longestMs = ms;
        }
        _lastMs = ms;
        _lastScore = score;
        _lapCount += 1;
        _lapAirMs += ms;
        if (ms > _lapLongestMs) {
            _lapLongestMs = ms;
        }
        remember(ms);
        _recordMs = ms;
        return true;
    }

    private function remember(ms as Number) as Void {
        if (_recentN < 32) {
            _recent[_recentN] = ms;
            _recentN += 1;
            return;
        }
        for (var i = 0; i < 31; i++) {
            _recent[i] = _recent[i + 1];
        }
        _recent[31] = ms;
    }

    private function smooth(ss as Number) as Number {
        if (_boxN < _window) {
            _box[_boxN] = ss;
            _boxN += 1;
            _boxSum += ss;
            return _boxSum / _boxN;
        }
        var old = _box[_boxI];
        _box[_boxI] = ss;
        _boxI = (_boxI + 1) % _window;
        _boxSum += ss - old;
        return _boxSum / _window;
    }

    private function clamp(value as Number, limit as Number) as Number {
        if (value > limit) {
            return limit;
        }
        if (value < -limit) {
            return -limit;
        }
        return value;
    }
}
