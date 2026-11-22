import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
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
    private var _usedMs as Number = -1000;

    function initialize(ride as RideSession, refresh as Method() as Void) {
        BehaviorDelegate.initialize();
        _ride = ride;
        _refresh = refresh;
    }

    function onSelect() as Boolean {
        if (!take()) {
            return true;
        }
        var phase = _ride.phase();
        if (phase == PHASE_READY) {
            _ride.startOrResume();
        } else if (phase == PHASE_RECORDING) {
            _ride.pause();
        } else if (phase == PHASE_PAUSED) {
            _ride.openConfirm();
        } else {
            _ride.acceptConfirm();
        }
        _refresh.invoke();
        return true;
    }

    function onMenu() as Boolean {
        if (!take()) {
            return true;
        }
        _ride.openConfirm();
        _refresh.invoke();
        return true;
    }

    function onBack() as Boolean {
        var phase = _ride.phase();
        if (phase == PHASE_READY) {
            return false;
        }
        if (!take()) {
            return true;
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
        if (!take()) {
            return true;
        }
        if (_ride.phase() == PHASE_CONFIRM) {
            _ride.moveChoice(true);
        } else {
            _ride.nextPage();
        }
        _refresh.invoke();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (!take()) {
            return true;
        }
        if (_ride.phase() == PHASE_CONFIRM) {
            _ride.moveChoice(false);
        } else {
            _ride.previousPage();
        }
        _refresh.invoke();
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        var type = evt.getType();
        if (type == WatchUi.PRESS_TYPE_DOWN) {
            return true;
        }
        if (isMenu(key, type)) {
            return onMenu();
        }
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            return onSelect();
        }
        if (key == WatchUi.KEY_ESC || key == WatchUi.KEY_LAP) {
            return onBack();
        }
        if (key == WatchUi.KEY_UP) {
            return onPreviousPage();
        }
        if (key == WatchUi.KEY_DOWN) {
            return onNextPage();
        }
        return false;
    }

    private function isMenu(key as WatchUi.Key, type as WatchUi.KeyPressType) as Boolean {
        if (key == WatchUi.KEY_MENU) {
            return true;
        }
        if (type != WatchUi.PRESS_TYPE_ACTION) {
            return false;
        }
        return key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START || key == WatchUi.KEY_UP;
    }

    // Behavior methods run first. On a fēnix 6 the same press can also
    // arrive as onKey, and a second call would undo the first. Ignore
    // anything that follows within a short window.
    private function take() as Boolean {
        var now = System.getTimer();
        var elapsed = now - _usedMs;
        if (elapsed >= 0 && elapsed < 120) {
            return false;
        }
        _usedMs = now;
        return true;
    }
}
