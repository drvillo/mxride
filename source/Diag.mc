import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

// Phase 0 sensor diagnostics.
//
// Collects enough metadata on every ride to answer, from the saved FIT alone:
//   - configured vs actually-delivered accel/gyro/GPS sample rates
//   - per-axis min/max in mg / dps (saturation near +/-8 g, +/-2000 dps)
//   - sign-wrap events (axis flips between consecutive samples near the cap)
//   - a histogram of total |a| (sanity-check float/landing thresholds)
//   - a histogram of total |gyro|
//   - how many sensor batches, GPS updates, and record seconds were seen
//
// All of this is additive: existing jump + speed fields keep writing exactly
// the same bytes as 1.0.5. Field ids 10..15 (record) and 20..43 (session) are
// new and can be deleted without touching the ones already shipped.
//
// To fully disable the diagnostic code paths at compile time, flip
// DIAG_ENABLED to false; the RideSession never instantiates a DiagCollector
// and the class is left for the optimizer to strip. To delete it, remove this
// file, the "import" in RideSession.mc, the _diag field, and the handful of
// _diag != null call sites.

const DIAG_ENABLED as Boolean = true;

const DIAG_HIST_BINS as Number = 16;
const DIAG_GYRO_HIST_BINS as Number = 8;
const DIAG_HIST_BIN_MG as Number = 500;      // 0..0.5g, 0.5..1g, ... 7.5..8g+
const DIAG_GYRO_BIN_DPS as Number = 250;     // 0..250, ... 1750..2000+
const DIAG_CLIP_ACCEL_MG as Number = 7500;   // sample near the +/-8 g cap
const DIAG_CLIP_GYRO_DPS as Number = 1800;   // sample near the +/-2000 dps cap
const DIAG_WRAP_MG as Number = 6000;         // sign flip only counted when both samples are this large
const DIAG_FLAG_ACCEL_CLIP as Number = 1;
const DIAG_FLAG_ACCEL_WRAP as Number = 2;
const DIAG_FLAG_GYRO_CLIP as Number = 4;
const DIAG_FLAG_SHORT_BATCH as Number = 8;
const DIAG_FLAG_NO_BATCH as Number = 16;

class DiagCollector {
    private var _accelCfg as Number = 0;
    private var _gyroCfg as Number = 0;

    private var _recordSec as Number = 0;
    private var _accelSamplesTotal as Number = 0;
    private var _gyroSamplesTotal as Number = 0;
    private var _batchesTotal as Number = 0;
    private var _gpsTotal as Number = 0;
    private var _accelClipTotal as Number = 0;
    private var _accelWrapTotal as Number = 0;
    private var _gyroClipTotal as Number = 0;

    private var _axLo as Number = 32767;
    private var _axHi as Number = -32768;
    private var _ayLo as Number = 32767;
    private var _ayHi as Number = -32768;
    private var _azLo as Number = 32767;
    private var _azHi as Number = -32768;
    private var _gxLo as Number = 32767;
    private var _gxHi as Number = -32768;
    private var _gyLo as Number = 32767;
    private var _gyHi as Number = -32768;
    private var _gzLo as Number = 32767;
    private var _gzHi as Number = -32768;

    private var _aHist as Array<Number>;
    private var _gHist as Array<Number>;

    private var _recSamples as Number = 0;
    private var _recGyroSamples as Number = 0;
    private var _recBatches as Number = 0;
    private var _recGps as Number = 0;
    private var _recAPeakMg as Number = 0;
    private var _recAMinMg as Number = 65535;
    private var _recGPeakDps as Number = 0;
    private var _recFlags as Number = 0;
    private var _recHasAccel as Boolean = false;

    private var _prevAx as Number = 0;
    private var _prevAy as Number = 0;
    private var _prevAz as Number = 0;
    private var _hasPrev as Boolean = false;

    private var _fRecSamples as FitContributor.Field or Null;
    private var _fRecGps as FitContributor.Field or Null;
    private var _fRecAPeak as FitContributor.Field or Null;
    private var _fRecAMin as FitContributor.Field or Null;
    private var _fRecGPeak as FitContributor.Field or Null;
    private var _fRecFlags as FitContributor.Field or Null;

    private var _fAccelCfg as FitContributor.Field or Null;
    private var _fGyroCfg as FitContributor.Field or Null;
    private var _fAccelRate as FitContributor.Field or Null;
    private var _fGyroRate as FitContributor.Field or Null;
    private var _fGpsRate as FitContributor.Field or Null;
    private var _fBatchesTotal as FitContributor.Field or Null;
    private var _fRecordSec as FitContributor.Field or Null;
    private var _fAxLo as FitContributor.Field or Null;
    private var _fAxHi as FitContributor.Field or Null;
    private var _fAyLo as FitContributor.Field or Null;
    private var _fAyHi as FitContributor.Field or Null;
    private var _fAzLo as FitContributor.Field or Null;
    private var _fAzHi as FitContributor.Field or Null;
    private var _fGxLo as FitContributor.Field or Null;
    private var _fGxHi as FitContributor.Field or Null;
    private var _fGyLo as FitContributor.Field or Null;
    private var _fGyHi as FitContributor.Field or Null;
    private var _fGzLo as FitContributor.Field or Null;
    private var _fGzHi as FitContributor.Field or Null;
    private var _fAccelClip as FitContributor.Field or Null;
    private var _fAccelWrap as FitContributor.Field or Null;
    private var _fGyroClip as FitContributor.Field or Null;
    private var _fAHist as FitContributor.Field or Null;
    private var _fGHist as FitContributor.Field or Null;

    function initialize() {
        _aHist = new Array<Number>[DIAG_HIST_BINS];
        _gHist = new Array<Number>[DIAG_GYRO_HIST_BINS];
        for (var i = 0; i < DIAG_HIST_BINS; i += 1) {
            _aHist[i] = 0;
        }
        for (var j = 0; j < DIAG_GYRO_HIST_BINS; j += 1) {
            _gHist[j] = 0;
        }
    }

    function beginSession(session as ActivityRecording.Session, accelCfg as Number, gyroCfg as Number) as Void {
        _accelCfg = accelCfg;
        _gyroCfg = gyroCfg;

        _fRecSamples   = tryField(session, "diag_samples",       10, FitContributor.DATA_TYPE_UINT16, FitContributor.MESG_TYPE_RECORD,  "count", 0);
        _fRecGps       = tryField(session, "diag_gps",            11, FitContributor.DATA_TYPE_UINT8,  FitContributor.MESG_TYPE_RECORD,  "count", 0);
        _fRecAPeak     = tryField(session, "diag_a_peak",         12, FitContributor.DATA_TYPE_UINT16, FitContributor.MESG_TYPE_RECORD,  "mg",    0);
        _fRecAMin      = tryField(session, "diag_a_min",          13, FitContributor.DATA_TYPE_UINT16, FitContributor.MESG_TYPE_RECORD,  "mg",    0);
        _fRecGPeak     = tryField(session, "diag_g_peak",         14, FitContributor.DATA_TYPE_UINT16, FitContributor.MESG_TYPE_RECORD,  "dps",   0);
        _fRecFlags     = tryField(session, "diag_flags",          15, FitContributor.DATA_TYPE_UINT8,  FitContributor.MESG_TYPE_RECORD,  "mask",  0);

        _fAccelCfg     = tryField(session, "diag_accel_rate_cfg", 20, FitContributor.DATA_TYPE_UINT8,  FitContributor.MESG_TYPE_SESSION, "Hz",    0);
        _fGyroCfg      = tryField(session, "diag_gyro_rate_cfg",  21, FitContributor.DATA_TYPE_UINT8,  FitContributor.MESG_TYPE_SESSION, "Hz",    0);
        _fAccelRate    = tryField(session, "diag_accel_rate_act", 22, FitContributor.DATA_TYPE_FLOAT,  FitContributor.MESG_TYPE_SESSION, "Hz",    0);
        _fGyroRate     = tryField(session, "diag_gyro_rate_act",  23, FitContributor.DATA_TYPE_FLOAT,  FitContributor.MESG_TYPE_SESSION, "Hz",    0);
        _fGpsRate      = tryField(session, "diag_gps_rate_act",   24, FitContributor.DATA_TYPE_FLOAT,  FitContributor.MESG_TYPE_SESSION, "Hz",    0);
        _fBatchesTotal = tryField(session, "diag_batches_total",  25, FitContributor.DATA_TYPE_UINT32, FitContributor.MESG_TYPE_SESSION, "count", 0);
        _fRecordSec    = tryField(session, "diag_record_seconds", 26, FitContributor.DATA_TYPE_UINT32, FitContributor.MESG_TYPE_SESSION, "s",     0);
        _fAxLo         = tryField(session, "diag_ax_lo",          27, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "mg",    0);
        _fAxHi         = tryField(session, "diag_ax_hi",          28, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "mg",    0);
        _fAyLo         = tryField(session, "diag_ay_lo",          29, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "mg",    0);
        _fAyHi         = tryField(session, "diag_ay_hi",          30, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "mg",    0);
        _fAzLo         = tryField(session, "diag_az_lo",          31, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "mg",    0);
        _fAzHi         = tryField(session, "diag_az_hi",          32, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "mg",    0);
        _fGxLo         = tryField(session, "diag_gx_lo",          33, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "dps",   0);
        _fGxHi         = tryField(session, "diag_gx_hi",          34, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "dps",   0);
        _fGyLo         = tryField(session, "diag_gy_lo",          35, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "dps",   0);
        _fGyHi         = tryField(session, "diag_gy_hi",          36, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "dps",   0);
        _fGzLo         = tryField(session, "diag_gz_lo",          37, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "dps",   0);
        _fGzHi         = tryField(session, "diag_gz_hi",          38, FitContributor.DATA_TYPE_SINT16, FitContributor.MESG_TYPE_SESSION, "dps",   0);
        _fAccelClip    = tryField(session, "diag_accel_clip",     39, FitContributor.DATA_TYPE_UINT32, FitContributor.MESG_TYPE_SESSION, "count", 0);
        _fAccelWrap    = tryField(session, "diag_accel_wrap",     40, FitContributor.DATA_TYPE_UINT32, FitContributor.MESG_TYPE_SESSION, "count", 0);
        _fGyroClip     = tryField(session, "diag_gyro_clip",      41, FitContributor.DATA_TYPE_UINT32, FitContributor.MESG_TYPE_SESSION, "count", 0);
        _fAHist        = tryField(session, "diag_a_hist",         42, FitContributor.DATA_TYPE_UINT16, FitContributor.MESG_TYPE_SESSION, "count", DIAG_HIST_BINS);
        _fGHist        = tryField(session, "diag_g_hist",         43, FitContributor.DATA_TYPE_UINT16, FitContributor.MESG_TYPE_SESSION, "count", DIAG_GYRO_HIST_BINS);

        setNum(_fAccelCfg, _accelCfg);
        setNum(_fGyroCfg, _gyroCfg);
    }

    // Called once per sensor callback. gyroN is 0 when the gyro is not armed
    // or the callback did not carry a matching gyro array.
    function onBatch(accelN as Number, gyroN as Number, cfgRate as Number) as Void {
        _recBatches += 1;
        _batchesTotal += 1;
        _recSamples += accelN;
        _recGyroSamples += gyroN;
        _accelSamplesTotal += accelN;
        _gyroSamplesTotal += gyroN;
        _recHasAccel = _recHasAccel || accelN > 0;
        if (cfgRate > 0 && accelN * 5 < cfgRate * 4) {
            _recFlags |= DIAG_FLAG_SHORT_BATCH;
        }
        _hasPrev = false;
    }

    function onPosition() as Void {
        _gpsTotal += 1;
        _recGps += 1;
    }

    // ax/ay/az are milli-g integers (same units the jump detector consumes).
    // gx/gy/gz are integer degrees-per-second; pass 0 when the gyro is off.
    function push(ax as Number, ay as Number, az as Number, gx as Number, gy as Number, gz as Number, gyroOn as Boolean) as Void {
        updateAxis(ax, 0);
        updateAxis(ay, 1);
        updateAxis(az, 2);
        if (absN(ax) >= DIAG_CLIP_ACCEL_MG || absN(ay) >= DIAG_CLIP_ACCEL_MG || absN(az) >= DIAG_CLIP_ACCEL_MG) {
            _accelClipTotal += 1;
            _recFlags |= DIAG_FLAG_ACCEL_CLIP;
        }
        if (_hasPrev && (wrapped(_prevAx, ax) || wrapped(_prevAy, ay) || wrapped(_prevAz, az))) {
            _accelWrapTotal += 1;
            _recFlags |= DIAG_FLAG_ACCEL_WRAP;
        }
        _prevAx = ax;
        _prevAy = ay;
        _prevAz = az;
        _hasPrev = true;

        var ss = ax * ax + ay * ay + az * az;
        var mg = isqrt(ss);
        if (mg > _recAPeakMg) {
            _recAPeakMg = mg;
        }
        if (mg < _recAMinMg) {
            _recAMinMg = mg;
        }
        var bin = mg / DIAG_HIST_BIN_MG;
        if (bin >= DIAG_HIST_BINS) {
            bin = DIAG_HIST_BINS - 1;
        }
        _aHist[bin] = _aHist[bin] + 1;

        if (gyroOn) {
            updateGyro(gx, 0);
            updateGyro(gy, 1);
            updateGyro(gz, 2);
            if (absN(gx) >= DIAG_CLIP_GYRO_DPS || absN(gy) >= DIAG_CLIP_GYRO_DPS || absN(gz) >= DIAG_CLIP_GYRO_DPS) {
                _gyroClipTotal += 1;
                _recFlags |= DIAG_FLAG_GYRO_CLIP;
            }
            var gss = gx * gx + gy * gy + gz * gz;
            var gmg = isqrt(gss);
            if (gmg > _recGPeakDps) {
                _recGPeakDps = gmg;
            }
            var gbin = gmg / DIAG_GYRO_BIN_DPS;
            if (gbin >= DIAG_GYRO_HIST_BINS) {
                gbin = DIAG_GYRO_HIST_BINS - 1;
            }
            _gHist[gbin] = _gHist[gbin] + 1;
        }
    }

    // Called once per second while the ride is recording, right after sample().
    function tick() as Void {
        _recordSec += 1;
        if (!_recHasAccel) {
            _recFlags |= DIAG_FLAG_NO_BATCH;
            _recAMinMg = 0;
        }
        setNum(_fRecSamples, u16(_recSamples));
        setNum(_fRecGps,     u8(_recGps));
        setNum(_fRecAPeak,   u16(_recAPeakMg));
        setNum(_fRecAMin,    u16(_recAMinMg));
        setNum(_fRecGPeak,   u16(_recGPeakDps));
        setNum(_fRecFlags,   u8(_recFlags));

        _recSamples = 0;
        _recGyroSamples = 0;
        _recBatches = 0;
        _recGps = 0;
        _recAPeakMg = 0;
        _recAMinMg = 65535;
        _recGPeakDps = 0;
        _recFlags = 0;
        _recHasAccel = false;
        _hasPrev = false;
    }

    function finishSession() as Void {
        setNum(_fAccelCfg, _accelCfg);
        setNum(_fGyroCfg, _gyroCfg);
        setFloat(_fAccelRate, perSec(_accelSamplesTotal));
        setFloat(_fGyroRate,  perSec(_gyroSamplesTotal));
        setFloat(_fGpsRate,   perSec(_gpsTotal));
        setNum(_fBatchesTotal, _batchesTotal);
        setNum(_fRecordSec,   _recordSec);
        setSigned(_fAxLo, _axLo); setSigned(_fAxHi, _axHi);
        setSigned(_fAyLo, _ayLo); setSigned(_fAyHi, _ayHi);
        setSigned(_fAzLo, _azLo); setSigned(_fAzHi, _azHi);
        setSigned(_fGxLo, _gxLo); setSigned(_fGxHi, _gxHi);
        setSigned(_fGyLo, _gyLo); setSigned(_fGyHi, _gyHi);
        setSigned(_fGzLo, _gzLo); setSigned(_fGzHi, _gzHi);
        setNum(_fAccelClip, _accelClipTotal);
        setNum(_fAccelWrap, _accelWrapTotal);
        setNum(_fGyroClip,  _gyroClipTotal);
        setArray(_fAHist, _aHist);
        setArray(_fGHist, _gHist);
        System.println("MX diag n=" + _recordSec.toString() + " a=" + _accelSamplesTotal.toString() + " g=" + _gyroSamplesTotal.toString() + " pos=" + _gpsTotal.toString() + " clip=" + _accelClipTotal.toString() + " wrap=" + _accelWrapTotal.toString());
    }

    private function updateAxis(v as Number, axis as Number) as Void {
        if (axis == 0) {
            if (v < _axLo) { _axLo = v; }
            if (v > _axHi) { _axHi = v; }
        } else if (axis == 1) {
            if (v < _ayLo) { _ayLo = v; }
            if (v > _ayHi) { _ayHi = v; }
        } else {
            if (v < _azLo) { _azLo = v; }
            if (v > _azHi) { _azHi = v; }
        }
    }

    private function updateGyro(v as Number, axis as Number) as Void {
        if (axis == 0) {
            if (v < _gxLo) { _gxLo = v; }
            if (v > _gxHi) { _gxHi = v; }
        } else if (axis == 1) {
            if (v < _gyLo) { _gyLo = v; }
            if (v > _gyHi) { _gyHi = v; }
        } else {
            if (v < _gzLo) { _gzLo = v; }
            if (v > _gzHi) { _gzHi = v; }
        }
    }

    private function wrapped(prev as Number, curr as Number) as Boolean {
        if (absN(prev) < DIAG_WRAP_MG || absN(curr) < DIAG_WRAP_MG) {
            return false;
        }
        return (prev > 0 && curr < 0) || (prev < 0 && curr > 0);
    }

    private function absN(v as Number) as Number {
        return v < 0 ? -v : v;
    }

    private function isqrt(ss as Number) as Number {
        if (ss <= 0) {
            return 0;
        }
        var r = Math.sqrt(ss.toFloat());
        return r.toNumber();
    }

    private function perSec(count as Number) as Float {
        if (_recordSec <= 0) {
            return 0.0;
        }
        return count.toFloat() / _recordSec.toFloat();
    }

    private function u16(v as Number) as Number {
        if (v < 0) { return 0; }
        if (v > 65535) { return 65535; }
        return v;
    }

    private function u8(v as Number) as Number {
        if (v < 0) { return 0; }
        if (v > 255) { return 255; }
        return v;
    }

    private function setNum(field as FitContributor.Field or Null, value as Number) as Void {
        if (field != null) {
            field.setData(value);
        }
    }

    private function setFloat(field as FitContributor.Field or Null, value as Float) as Void {
        if (field != null) {
            field.setData(value);
        }
    }

    private function setSigned(field as FitContributor.Field or Null, value as Number) as Void {
        if (field == null) {
            return;
        }
        var clipped = value;
        if (clipped > 32767) { clipped = 32767; }
        if (clipped < -32768) { clipped = -32768; }
        if (clipped == 32767 && value == 32767) {
            // untouched sentinel from initialize(); leave the field at zero
            // rather than claim an axis never fell below +32767 mg.
            clipped = 0;
        }
        if (clipped == -32768 && value == -32768) {
            clipped = 0;
        }
        field.setData(clipped);
    }

    private function setArray(field as FitContributor.Field or Null, values as Array<Number>) as Void {
        if (field == null) {
            return;
        }
        try {
            field.setData(values);
        } catch (ex) {
        }
    }

    private function tryField(session as ActivityRecording.Session, name as String, id as Number, type as FitContributor.DataType, mesg as FitContributor.MessageType, units as String, count as Number) as FitContributor.Field or Null {
        var field = null;
        try {
            if (count > 0) {
                field = session.createField(name, id, type, {
                    :mesgType => mesg,
                    :units => units,
                    :count => count
                });
            } else {
                field = session.createField(name, id, type, {
                    :mesgType => mesg,
                    :units => units
                });
            }
        } catch (ex) {
            System.println("MX diag field skipped " + name);
            field = null;
        }
        return field;
    }
}
