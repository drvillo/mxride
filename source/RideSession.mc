import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.UserProfile;

enum Phase {
    PHASE_READY,
    PHASE_RECORDING,
    PHASE_PAUSED,
    PHASE_CONFIRM
}

enum Choice {
    CHOICE_SAVE,
    CHOICE_DISCARD
}

enum Page {
    PAGE_RIDE,
    PAGE_STATS
}

class Snapshot {
    var phase as Phase = PHASE_READY;
    var choice as Choice = CHOICE_SAVE;
    var page as Page = PAGE_RIDE;
    var speedKmh as Number or Null;
    var headingDeg as Number or Null;
    var altitudeM as Number or Null;
    var heartRate as Number or Null;
    var hrZone as Number = 0;
    var timerMs as Number = 0;
    var distanceM as Float or Null;
    var maxSpeedKmh as Number or Null;
    var ascentM as Number or Null;
    var lapMs as Number = 0;
    var laps as Number = 0;

    function initialize() {
    }
}

class RideSession {
    private var _phase as Phase = PHASE_READY;
    private var _choice as Choice = CHOICE_SAVE;
    private var _page as Page = PAGE_RIDE;
    private var _session as ActivityRecording.Session or Null;
    private var _maxField as FitContributor.Field or Null;
    private var _lapMaxField as FitContributor.Field or Null;
    private var _maxKmh as Float = 0.0;
    private var _lapMaxKmh as Float = 0.0;
    private var _lapStartMs as Number = 0;
    private var _laps as Number = 0;
    private var _position as Position.Info or Null;
    private var _zones as Array<Number>;

    function initialize() {
        _zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
    }

    function phase() as Phase {
        return _phase;
    }

    function startPositioning() as Void {
        if ((Position has :hasConfigurationSupport) && (Position has :CONFIGURATION_SAT_IQ) && Position.hasConfigurationSupport(Position.CONFIGURATION_SAT_IQ)) {
            Position.enableLocationEvents({
                :acquisitionType => Position.LOCATION_CONTINUOUS,
                :configuration => Position.CONFIGURATION_SAT_IQ
            }, method(:onPosition));
        } else {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }

    function stopPositioning() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        _position = info;
    }

    function startOrResume() as Void {
        if (_phase == PHASE_READY) {
            var options = {
                :name => "Motocross",
                :sport => Activity.SPORT_MOTORCYCLING
            };
            if (Activity has :SUB_SPORT_MOTOCROSS) {
                options[:subSport] = Activity.SUB_SPORT_MOTOCROSS;
            }
            var session = ActivityRecording.createSession(options);
            _maxField = session.createField("max_speed", 0, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "km/h" });
            _lapMaxField = session.createField("lap_max_speed", 1, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "km/h" });
            _maxKmh = 0.0;
            _lapMaxKmh = 0.0;
            _lapStartMs = 0;
            _laps = 0;
            if (!session.start()) {
                session.discard();
                _maxField = null;
                _lapMaxField = null;
                return;
            }
            _session = session;
            _phase = PHASE_RECORDING;
        } else if (_phase == PHASE_PAUSED) {
            liveSession().start();
            _phase = PHASE_RECORDING;
        }
    }

    function pause() as Void {
        if (_phase == PHASE_RECORDING) {
            sample();
            liveSession().stop();
            _phase = PHASE_PAUSED;
        }
    }

    function lap() as Void {
        if (_phase != PHASE_RECORDING && _phase != PHASE_PAUSED) {
            return;
        }
        sample();
        var lapField = _lapMaxField as FitContributor.Field;
        lapField.setData(_lapMaxKmh);
        var session = liveSession();
        var stored = session.addLap();
        if (!stored && !session.isRecording()) {
            session.start();
            lapField.setData(_lapMaxKmh);
            stored = session.addLap();
            session.stop();
        }
        if (!stored) {
            return;
        }
        _laps += 1;
        _lapStartMs = timerMs(Activity.getActivityInfo());
        _lapMaxKmh = 0.0;
        lapField.setData(_lapMaxKmh);
    }

    function openConfirm() as Void {
        pause();
        if (_phase == PHASE_PAUSED) {
            _choice = CHOICE_SAVE;
            _phase = PHASE_CONFIRM;
        }
    }

    function chooseConfirm(choice as Choice) as Void {
        if (_phase == PHASE_CONFIRM) {
            _choice = choice;
        }
    }

    function acceptConfirm() as Void {
        if (_phase != PHASE_CONFIRM) {
            return;
        }
        if (_choice == CHOICE_SAVE) {
            liveSession().save();
        } else {
            liveSession().discard();
        }
        _session = null;
        _maxField = null;
        _lapMaxField = null;
        _maxKmh = 0.0;
        _lapMaxKmh = 0.0;
        _lapStartMs = 0;
        _laps = 0;
        _phase = PHASE_READY;
    }

    function cancelConfirm() as Void {
        if (_phase == PHASE_CONFIRM) {
            _phase = PHASE_PAUSED;
        }
    }

    function nextPage() as Void {
        _page = _page == PAGE_RIDE ? PAGE_STATS : PAGE_RIDE;
    }

    function previousPage() as Void {
        nextPage();
    }

    function sample() as Void {
        if (_phase != PHASE_RECORDING) {
            return;
        }
        var info = Activity.getActivityInfo();
        var max = info.maxSpeed;
        if (max != null && Mx.kmh(max) > _maxKmh) {
            _maxKmh = Mx.kmh(max);
            (_maxField as FitContributor.Field).setData(_maxKmh);
        }
        var speed = info.currentSpeed;
        if (hasFix() && speed != null && Mx.kmh(speed) > _lapMaxKmh) {
            _lapMaxKmh = Mx.kmh(speed);
            (_lapMaxField as FitContributor.Field).setData(_lapMaxKmh);
        }
    }

    function snapshot() as Snapshot {
        var snap = new Snapshot();
        snap.phase = _phase;
        snap.choice = _choice;
        snap.page = _page;
        snap.laps = _laps;
        var fix = hasFix();
        if (_session != null) {
            var info = Activity.getActivityInfo();
            if (fix) {
                snap.speedKmh = roundKmh(info.currentSpeed);
                snap.headingDeg = degrees(info.currentHeading);
            }
            snap.altitudeM = rounded(info.altitude);
            snap.heartRate = info.currentHeartRate;
            snap.timerMs = timerMs(info);
            snap.distanceM = info.elapsedDistance;
            var climbed = info.totalAscent;
            if (climbed != null) {
                snap.ascentM = rounded(climbed.toFloat());
            }
            snap.maxSpeedKmh = (_maxKmh + 0.5).toNumber();
            snap.lapMs = snap.timerMs - _lapStartMs;
        } else {
            var position = _position;
            if (fix && position != null) {
                snap.speedKmh = roundKmh(position.speed);
                snap.headingDeg = degrees(position.heading);
                snap.altitudeM = rounded(position.altitude);
            }
            snap.heartRate = Sensor.getInfo().heartRate;
        }
        var hr = snap.heartRate;
        if (hr != null) {
            snap.hrZone = Mx.zoneIndex(hr, _zones);
        }
        return snap;
    }

    private function liveSession() as ActivityRecording.Session {
        return _session as ActivityRecording.Session;
    }

    private function hasFix() as Boolean {
        var position = _position;
        return position != null && position.accuracy >= Position.QUALITY_POOR;
    }

    private function timerMs(info as Activity.Info) as Number {
        var timer = info.timerTime;
        return timer == null ? 0 : timer;
    }

    private function roundKmh(metersPerSecond as Float or Null) as Number or Null {
        return metersPerSecond == null ? null : (Mx.kmh(metersPerSecond) + 0.5).toNumber();
    }

    private function degrees(radians as Float or Null) as Number or Null {
        return radians == null ? null : Mx.headingDegrees(radians);
    }

    private function rounded(value as Float or Null) as Number or Null {
        return value == null ? null : Math.round(value).toNumber();
    }
}
