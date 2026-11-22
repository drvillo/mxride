import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

class RideView extends WatchUi.View {
    private var _snap as Snapshot;
    private var _digits as FontResource?;
    private var _labels as FontResource?;

    function initialize(snap as Snapshot) {
        View.initialize();
        _snap = snap;
    }

    function onLayout(dc as Dc) as Void {
        _digits = WatchUi.loadResource(Rez.Fonts.Digits) as FontResource;
        _labels = WatchUi.loadResource(Rez.Fonts.Labels) as FontResource;
    }

    function show(snap as Snapshot) as Void {
        _snap = snap;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (_digits == null || _labels == null) {
            return;
        }
        var digits = _digits as FontResource;
        var labels = _labels as FontResource;
        if (_snap.phase == PHASE_CONFIRM) {
            drawConfirm(dc, w, h, labels);
        } else if (_snap.page == PAGE_RIDE) {
            drawRide(dc, w, h, digits, labels);
        } else {
            drawStats(dc, w, h, digits, labels);
        }
        drawDots(dc, w, h);
    }

    private function drawRide(dc as Dc, w as Number, h as Number, digits as FontResource, labels as FontResource) as Void {
        var snap = _snap;
        var step = h >= 260 ? 26 : 24;
        var digitH = dc.getFontHeight(digits);
        var y = h >= 260 ? 10 : 6;
        text(dc, w / 2, y, labels, phaseWord(snap.phase), phaseColor(snap.phase), Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, digits, Mx.formatNumber(snap.speedKmh), Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        y += digitH + 4;
        if (snap.phase == PHASE_PAUSED) {
            text(dc, w / 2, y, labels, "START: SAVE", Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var course = "--";
            if (snap.headingDeg != null) {
                var deg = snap.headingDeg as Number;
                course = deg.toString() + " " + Mx.cardinal(deg);
                drawNeedle(dc, w / 2 + 68, y + 10, 11, deg);
            }
            text(dc, w / 2, y, labels, course, Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        }
        y += step;
        text(dc, w / 2, y, labels, "A " + Mx.formatNumber(snap.altitudeM), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        var hrColor = Graphics.COLOR_WHITE;
        if (snap.heartRate != null) {
            hrColor = zoneColor(snap.hrZone);
        }
        text(dc, w / 2, y, labels, "H " + Mx.formatNumber(snap.heartRate), hrColor, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        var dist = snap.distanceM;
        var distText = "--";
        if (dist != null) {
            distText = (dist / 1000.0).format("%.1f");
        }
        text(dc, w / 2, y, labels, Mx.formatTimer(snap.timerMs) + " " + distText, Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawStats(dc as Dc, w as Number, h as Number, digits as FontResource, labels as FontResource) as Void {
        var snap = _snap;
        var step = h >= 260 ? 26 : 24;
        var digitH = dc.getFontHeight(digits);
        var y = h >= 260 ? 10 : 6;
        text(dc, w / 2, y, labels, phaseWord(snap.phase), phaseColor(snap.phase), Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, labels, "MAX", Graphics.COLOR_LT_GRAY, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, digits, Mx.formatNumber(snap.maxSpeedKmh), Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        y += digitH + 4;
        if (snap.phase == PHASE_PAUSED) {
            text(dc, w / 2, y, labels, "START: SAVE", Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            text(dc, w / 2, y, labels, "UP " + Mx.formatNumber(snap.ascentM), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        }
        y += step;
        text(dc, w / 2, y, labels, "LAP " + Mx.formatTimer(snap.lapMs), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, labels, "LAPS " + snap.laps.toString(), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawConfirm(dc as Dc, w as Number, h as Number, labels as FontResource) as Void {
        var labelH = dc.getFontHeight(labels);
        var gap = labelH + 4;
        var mid = h / 2;
        text(dc, w / 2, mid - gap * 2, labels, "PAUSED", Graphics.COLOR_ORANGE, Graphics.TEXT_JUSTIFY_CENTER);
        choice(dc, w, mid - gap, "RESUME", labels, labelH, _snap.choice == CHOICE_RESUME);
        choice(dc, w, mid, "SAVE", labels, labelH, _snap.choice == CHOICE_SAVE);
        choice(dc, w, mid + gap, "DISCARD", labels, labelH, _snap.choice == CHOICE_DISCARD);
    }

    private function choice(dc as Dc, w as Number, y as Number, word as String, font as FontResource, labelH as Number, on as Boolean) as Void {
        if (on) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_YELLOW);
            dc.fillRectangle(w / 2 - 82, y - 2, 164, labelH + 4);
            text(dc, w / 2, y, font, word, Graphics.COLOR_BLACK, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            text(dc, w / 2, y, font, word, Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawDots(dc as Dc, w as Number, h as Number) as Void {
        if (_snap.phase == PHASE_CONFIRM) {
            return;
        }
        var y = h - 14;
        var x = w / 2 - 10;
        dc.setColor(_snap.page == PAGE_RIDE ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, 7, 7);
        dc.setColor(_snap.page == PAGE_STATS ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 12, y, 7, 7);
    }

    private function drawNeedle(dc as Dc, cx as Number, cy as Number, r as Number, deg as Number) as Void {
        var rad = Math.toRadians(deg);
        var tipX = cx + (Math.sin(rad) * r).toNumber();
        var tipY = cy - (Math.cos(rad) * r).toNumber();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(cx, cy, tipX, tipY);
        dc.setPenWidth(1);
    }

    private function text(dc as Dc, x as Number, y as Number, font as FontResource, value as String, color as Number, justify as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, value, justify);
    }

    private function phaseWord(phase as Phase) as String {
        if (phase == PHASE_RECORDING) {
            return "REC";
        }
        if (phase == PHASE_PAUSED) {
            return "PAUSED";
        }
        return "READY";
    }

    private function phaseColor(phase as Phase) as Number {
        if (phase == PHASE_RECORDING) {
            return Graphics.COLOR_YELLOW;
        }
        if (phase == PHASE_PAUSED) {
            return Graphics.COLOR_ORANGE;
        }
        return Graphics.COLOR_WHITE;
    }

    private function zoneColor(zone as Number) as Number {
        if (zone == 1) {
            return Graphics.COLOR_GREEN;
        }
        if (zone == 2) {
            return Graphics.COLOR_YELLOW;
        }
        if (zone == 3) {
            return Graphics.COLOR_ORANGE;
        }
        if (zone == 4) {
            return Graphics.COLOR_RED;
        }
        if (zone >= 5) {
            return Graphics.COLOR_PINK;
        }
        return Graphics.COLOR_WHITE;
    }
}
