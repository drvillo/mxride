import Toybox.Application;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class MxRideApp extends Application.AppBase {
    private var _ride as RideSession;
    private var _view as RideView;
    private var _timer as Timer.Timer;

    function initialize() {
        AppBase.initialize();
        _ride = new RideSession();
        _view = new RideView(_ride.snapshot());
        _timer = new Timer.Timer();
    }

    function onStart(state as Dictionary?) as Void {
        _ride.startPositioning();
        _timer.start(method(:onTick), 1000, true);
    }

    function onStop(state as Dictionary?) as Void {
        _timer.stop();
        _ride.stopPositioning();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [_view, new RideDelegate(_ride, method(:refresh))];
    }

    function onTick() as Void {
        _ride.sample();
        refresh();
    }

    function refresh() as Void {
        _view.show(_ride.snapshot());
        WatchUi.requestUpdate();
    }
}

class RideDelegate extends WatchUi.BehaviorDelegate {
    private var _ride as RideSession;
    private var _refresh as Method() as Void;
    private var _enterHeld as Boolean = false;

    function initialize(ride as RideSession, refresh as Method() as Void) {
        BehaviorDelegate.initialize();
        _ride = ride;
        _refresh = refresh;
    }

    function onSelect() as Boolean {
        var phase = _ride.phase();
        if (phase == PHASE_READY || phase == PHASE_PAUSED) {
            _ride.startOrResume();
        } else if (phase == PHASE_RECORDING) {
            _ride.pause();
        } else {
            _ride.acceptConfirm();
        }
        _refresh.invoke();
        return true;
    }

    function onBack() as Boolean {
        var phase = _ride.phase();
        if (phase == PHASE_READY) {
            return false;
        }
        if (phase == PHASE_CONFIRM) {
            _ride.cancelConfirm();
        } else {
            _ride.lap();
        }
        _refresh.invoke();
        return true;
    }

    function onNextPage() as Boolean {
        if (_ride.phase() == PHASE_CONFIRM) {
            _ride.chooseConfirm(CHOICE_DISCARD);
        } else {
            _ride.nextPage();
        }
        _refresh.invoke();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_ride.phase() == PHASE_CONFIRM) {
            _ride.chooseConfirm(CHOICE_SAVE);
        } else {
            _ride.previousPage();
        }
        _refresh.invoke();
        return true;
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _enterHeld = false;
        }
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        var phase = _ride.phase();
        if (key == WatchUi.KEY_ENTER) {
            var type = evt.getType();
            if (type == WatchUi.PRESS_TYPE_ACTION) {
                _enterHeld = true;
                _ride.openConfirm();
            } else if (type == WatchUi.PRESS_TYPE_DOWN) {
                return true;
            } else if (_enterHeld) {
                _enterHeld = false;
                return true;
            } else if (phase == PHASE_READY || phase == PHASE_PAUSED) {
                _ride.startOrResume();
            } else if (phase == PHASE_RECORDING) {
                _ride.pause();
            } else {
                _ride.acceptConfirm();
            }
        } else if (key == WatchUi.KEY_ESC) {
            if (phase == PHASE_READY) {
                return false;
            } else if (phase == PHASE_CONFIRM) {
                _ride.cancelConfirm();
            } else {
                _ride.lap();
            }
        } else if (key == WatchUi.KEY_UP) {
            if (phase == PHASE_CONFIRM) {
                _ride.chooseConfirm(CHOICE_SAVE);
            } else {
                _ride.previousPage();
            }
        } else if (key == WatchUi.KEY_DOWN) {
            if (phase == PHASE_CONFIRM) {
                _ride.chooseConfirm(CHOICE_DISCARD);
            } else {
                _ride.nextPage();
            }
        } else if (key == WatchUi.KEY_MENU) {
            _ride.openConfirm();
        } else {
            return false;
        }
        _refresh.invoke();
        return true;
    }
}
