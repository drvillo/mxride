import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
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
        if (_snap.phase == PHASE_READY) {
            drawGpsRing(dc, w, h);
        }
        if (_snap.phase == PHASE_CONFIRM) {
            drawConfirm(dc, w, h, labels);
        } else if (_snap.page == PAGE_RIDE) {
            drawRide(dc, w, h, digits, labels);
        } else if (_snap.page == PAGE_STATS) {
            drawStats(dc, w, h, digits, labels);
        } else if (_snap.page == PAGE_TRACK) {
            drawTrack(dc, w, h, labels);
        } else {
            drawJumps(dc, w, h, digits, labels);
        }
        drawGpsBars(dc, w, h);
        drawDots(dc, w, h);
    }

    private function drawRide(dc as Dc, w as Number, h as Number, digits as FontResource, labels as FontResource) as Void {
        var snap = _snap;
        if (snap.phase == PHASE_RECORDING || snap.phase == PHASE_PAUSED) {
            drawGRing(dc, w, h, snap);
        }
        var step = lineStep(h);
        var digitH = dc.getFontHeight(digits);
        var y = rideTop(h, step, digitH);
        text(dc, w / 2, y, labels, phaseWord(snap.phase), phaseColor(snap.phase), Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, digits, Mx.formatNumber(snap.speedKmh), Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        y += digitH + 4;
        if (snap.phase == PHASE_READY) {
            var color = gpsColor(snap.gpsAccuracy);
            text(dc, w / 2, y, labels, "GPS", color, Graphics.TEXT_JUSTIFY_CENTER);
            y += step;
            text(dc, w / 2, y, labels, gpsDetail(snap.gpsAccuracy), color, Graphics.TEXT_JUSTIFY_CENTER);
            y += step;
            // HR is the only other live value until the ride starts.
            var hrReadyColor = Graphics.COLOR_WHITE;
            if (snap.heartRate != null) {
                hrReadyColor = zoneColor(snap.hrZone);
            }
            text(dc, w / 2, y, labels, "H " + Mx.formatNumber(snap.heartRate), hrReadyColor, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
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
        y += step;
        drawGLine(dc, w, y, labels, snap);
    }

    private function drawGLine(dc as Dc, w as Number, y as Number, labels as FontResource, snap as Snapshot) as Void {
        if (snap.phase == PHASE_PAUSED) {
            text(dc, w / 2, y, labels, "START: SAVE", Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        // Air time wins over the G line while a jump is in progress.
        if (snap.airLiveMs > 0) {
            var tenths = (snap.airLiveMs + 50) / 100;
            var whole = tenths / 10;
            var frac = tenths % 10;
            var airText = "AIR " + whole.toString() + "." + frac.toString();
            text(dc, w / 2, y, labels, airText, Graphics.COLOR_RED, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        // LAND takes over for 3 s after a landing window closes, showing
        // the peak |a| of that landing. After 3 s we fall back to the ring
        // value.
        if (snap.landShowMs > 0 && snap.landPeak > 0.0) {
            var landText = "LAND " + snap.landPeak.format("%.1f");
            text(dc, w / 2, y, labels, landText, Graphics.COLOR_GREEN, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var ringText = Mx.formatG(snap.ringG) + " G";
        var ringColor = Graphics.COLOR_WHITE;
        if (snap.ringG >= 0.1) {
            ringColor = Graphics.COLOR_GREEN;
        } else if (snap.ringG <= -0.1) {
            ringColor = Graphics.COLOR_RED;
        }
        text(dc, w / 2, y, labels, ringText, ringColor, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawStats(dc as Dc, w as Number, h as Number, digits as FontResource, labels as FontResource) as Void {
        var snap = _snap;
        var step = lineStep(h);
        var digitH = dc.getFontHeight(digits);
        var y = lineTop(h, step, digitH);
        text(dc, w / 2, y, labels, phaseWord(snap.phase), phaseColor(snap.phase), Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, labels, "MAX", Graphics.COLOR_LT_GRAY, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, digits, Mx.formatNumber(snap.maxSpeedKmh), Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        y += digitH + 4;
        if (snap.phase == PHASE_PAUSED) {
            text(dc, w / 2, y, labels, "START: SAVE", Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
            y += step;
            text(dc, w / 2, y, labels, "LAP " + Mx.formatTimer(snap.lapMs), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
            y += step;
            text(dc, w / 2, y, labels, "LAPS " + snap.laps.toString(), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (snap.phase == PHASE_READY) {
            var color = gpsColor(snap.gpsAccuracy);
            text(dc, w / 2, y, labels, "GPS", color, Graphics.TEXT_JUSTIFY_CENTER);
            y += step;
            text(dc, w / 2, y, labels, gpsDetail(snap.gpsAccuracy), color, Graphics.TEXT_JUSTIFY_CENTER);
            y += step;
            text(dc, w / 2, y, labels, "LAPS " + snap.laps.toString(), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        // Heading and altitude moved here from the main page in 1.0.6 to
        // make room for the G-ring. UP (total ascent) and LAP were the two
        // extras here before; LAP keeps its row, UP folds into the altitude
        // row because the two are closely related.
        var course = "--";
        if (snap.headingDeg != null) {
            var deg = snap.headingDeg as Number;
            course = deg.toString() + " " + Mx.cardinal(deg);
        }
        text(dc, w / 2, y, labels, course, Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, labels, "A " + Mx.formatNumber(snap.altitudeM) + " / UP " + Mx.formatNumber(snap.ascentM), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, labels, "LAP " + Mx.formatTimer(snap.lapMs) + " / " + snap.laps.toString(), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawJumps(dc as Dc, w as Number, h as Number, digits as FontResource, labels as FontResource) as Void {
        var snap = _snap;
        var step = lineStep(h);
        var digitH = dc.getFontHeight(digits);
        var y = lineTop(h, step, digitH);
        text(dc, w / 2, y, labels, phaseWord(snap.phase), phaseColor(snap.phase), Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, labels, "JUMPS", Graphics.COLOR_LT_GRAY, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, digits, snap.jumpCount.toString(), Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        y += digitH + 4;
        if (snap.phase == PHASE_PAUSED) {
            text(dc, w / 2, y, labels, "START: SAVE", Graphics.COLOR_YELLOW, Graphics.TEXT_JUSTIFY_CENTER);
        } else if (snap.phase == PHASE_READY) {
            text(dc, w / 2, y, labels, Mx.formatRate(snap.accelRate, snap.gyroRate), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            text(dc, w / 2, y, labels, "LAST " + Mx.formatAir(snap.jumpLastMs), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        }
        y += step;
        text(dc, w / 2, y, labels, "BEST " + Mx.formatAir(snap.jumpLongestMs), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        y += step;
        text(dc, w / 2, y, labels, "SUM " + Mx.formatAir(snap.jumpTotalMs), Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawTrack(dc as Dc, w as Number, h as Number, labels as FontResource) as Void {
        var snap = _snap;
        var lats = snap.trackLats;
        var lons = snap.trackLons;
        var n = lats.size();
        var hasHere = snap.hereLat != null && snap.hereLon != null;
        if (n < 2) {
            drawTrackStatus(dc, w, h, labels);
            return;
        }
        var minLat = hasHere ? snap.hereLat as Float : lats[0] as Float;
        var maxLat = minLat;
        var minLon = hasHere ? snap.hereLon as Float : lons[0] as Float;
        var maxLon = minLon;
        for (var i = 0; i < n; i++) {
            var lat = lats[i] as Float;
            var lon = lons[i] as Float;
            if (lat < minLat) {
                minLat = lat;
            }
            if (lat > maxLat) {
                maxLat = lat;
            }
            if (lon < minLon) {
                minLon = lon;
            }
            if (lon > maxLon) {
                maxLon = lon;
            }
        }
        var midLat = ((minLat + maxLat) / 2.0).toFloat();
        var midLon = ((minLon + maxLon) / 2.0).toFloat();
        var cosLat = Math.cos(Math.toRadians(midLat)).toFloat();
        if (cosLat < 0.2) {
            cosLat = 0.2.toFloat();
        }
        var spanLat = (maxLat - minLat).toFloat();
        var spanLon = ((maxLon - minLon) * cosLat).toFloat();
        if (spanLat < 0.0015) {
            spanLat = 0.0015.toFloat();
        }
        if (spanLon < 0.0015) {
            spanLon = 0.0015.toFloat();
        }
        var span = spanLat;
        if (spanLon > spanLat) {
            span = spanLon;
        }
        var box = trackBox(w < h ? w : h);
        var scale = ((box * 2.0) / span).toFloat();
        var cx = w / 2;
        var cy = h / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var prevX = 0;
        var prevY = 0;
        var hasPrev = false;
        for (var j = 0; j < n; j++) {
            var px = projectX(lons[j] as Float, midLon, cosLat, scale, cx);
            var py = projectY(lats[j] as Float, midLat, scale, cy);
            if (hasPrev) {
                dc.drawLine(prevX, prevY, px, py);
            }
            prevX = px;
            prevY = py;
            hasPrev = true;
        }
        var mx = cx;
        var my = cy;
        if (hasHere) {
            mx = projectX(snap.hereLon as Float, midLon, cosLat, scale, cx);
            my = projectY(snap.hereLat as Float, midLat, scale, cy);
            if (hasPrev) {
                dc.drawLine(prevX, prevY, mx, my);
            }
        } else if (hasPrev) {
            mx = prevX;
            my = prevY;
        }
        dc.setPenWidth(1);
        if (snap.headingDeg != null) {
            drawNeedle(dc, mx, my, 16, snap.headingDeg as Number);
        }
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_YELLOW);
        dc.fillCircle(mx, my, 4);
        text(dc, cx, cy - box, labels, "N", Graphics.COLOR_LT_GRAY, Graphics.TEXT_JUSTIFY_CENTER);
        drawScale(dc, labels, cx, cy + box - 20, scale);
        if (snap.phase == PHASE_READY) {
            drawTrackStatus(dc, w, h, labels);
        }
    }

    private function drawTrackStatus(dc as Dc, w as Number, h as Number, labels as FontResource) as Void {
        var color = gpsColor(_snap.gpsAccuracy);
        var y = h / 2 - 16;
        if (_snap.phase == PHASE_READY) {
            text(dc, w / 2, y, labels, "GPS", color, Graphics.TEXT_JUSTIFY_CENTER);
            text(dc, w / 2, y + 26, labels, gpsDetail(_snap.gpsAccuracy), color, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            text(dc, w / 2, y, labels, "NO TRACK", Graphics.COLOR_LT_GRAY, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawScale(dc as Dc, labels as FontResource, cx as Number, y as Number, scale as Float) as Void {
        var metersPerPx = 111320.0 / scale;
        var target = 52.0 * metersPerPx;
        var nice = 50.0;
        if (target > 75.0) {
            nice = 100.0;
        }
        if (target > 150.0) {
            nice = 200.0;
        }
        if (target > 350.0) {
            nice = 500.0;
        }
        if (target > 750.0) {
            nice = 1000.0;
        }
        if (target > 1500.0) {
            nice = 2000.0;
        }
        if (target > 3500.0) {
            nice = 5000.0;
        }
        var px = (nice / metersPerPx).toNumber();
        if (px < 8) {
            px = 8;
        }
        var x0 = cx - px / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x0, y, x0 + px, y);
        dc.drawLine(x0, y - 3, x0, y + 3);
        dc.drawLine(x0 + px, y - 3, x0 + px, y + 3);
        dc.setPenWidth(1);
        var label = nice.toNumber().toString() + "M";
        if (nice >= 1000.0) {
            label = (nice / 1000.0).toNumber().toString() + "KM";
        }
        text(dc, cx, y - 24, labels, label, Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function projectX(lon as Float, midLon as Float, cosLat as Float, scale as Float, cx as Number) as Number {
        return cx + ((lon - midLon) * cosLat * scale).toNumber();
    }

    private function projectY(lat as Float, midLat as Float, scale as Float, cy as Number) as Number {
        return cy - ((lat - midLat) * scale).toNumber();
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
        // The G-ring on the main page eats the bottom bezel. Move the dots
        // up so they sit inside the ring instead of under it. On other
        // pages the dots keep their old position (no ring there).
        if (_snap.page == PAGE_RIDE && (_snap.phase == PHASE_RECORDING || _snap.phase == PHASE_PAUSED)) {
            var side = w < h ? w : h;
            y = h / 2 + side / 2 - ringOuterInset(side) - ringWidthFor(side) - 10;
        }
        var x = w / 2 - 16;
        dc.setColor(_snap.page == PAGE_RIDE ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, 7, 7);
        dc.setColor(_snap.page == PAGE_STATS ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 12, y, 7, 7);
        dc.setColor(_snap.page == PAGE_TRACK ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 24, y, 7, 7);
        dc.setColor(_snap.page == PAGE_JUMPS ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 36, y, 7, 7);
    }

    // Per-size tables keep the ring geometry readable across 240, 260,
    // 280, 416, 454 and 466 faces. The bitmap fonts are fixed, so these
    // table values were picked against the mockups and the existing layout.
    private function ringWidthFor(side as Number) as Number {
        if (side >= 450) {
            return 14;
        }
        if (side >= 400) {
            return 12;
        }
        if (side >= 280) {
            return 11;
        }
        if (side >= 260) {
            return 10;
        }
        return 9;
    }

    private function ringOuterInset(side as Number) as Number {
        if (side >= 400) {
            return 10;
        }
        return 3;
    }

    private function rideTop(h as Number, step as Number, digitH as Number) as Number {
        // The ring takes the top and bottom bezels, so the content stack
        // on the ride page lives in a slightly smaller box than the other
        // pages. 10 px above REC fits the 260 px mockup.
        if (h < 260) {
            return 14;
        }
        if (h < 400) {
            return 14;
        }
        var block = step + digitH + 4 + step * 3;
        var y = (h - block) / 2;
        if (y < 36) {
            return 36;
        }
        return y;
    }

    private function drawGRing(dc as Dc, w as Number, h as Number, snap as Snapshot) as Void {
        var side = w < h ? w : h;
        var outer = side / 2 - ringOuterInset(side);
        var ringWidth = ringWidthFor(side);
        var midR = outer - ringWidth / 2;
        var cx = w / 2;
        var cy = h / 2;
        // Base unlit ring: 60 short arcs (30 per side) so the segmented look
        // of the mockup is preserved and the lit arcs can overdraw a single
        // segment cleanly.
        dc.setPenWidth(ringWidth);
        drawSegments(dc, cx, cy, midR, true, 30, Graphics.COLOR_DK_GRAY);
        drawSegments(dc, cx, cy, midR, false, 30, Graphics.COLOR_DK_GRAY);
        // Lit segments. 0.1 g per step on the compression side (up to +3 g),
        // 0.033 g per step on the unloading side (down to -1 g = free fall).
        // Only the current second's ring value drives the lit count; the
        // 3 s peak-hold tick carries the earlier reading above the
        // fresh-lit segments.
        var instPos = snap.ringG > 0.0 ? (snap.ringG * 10.0 + 0.5).toNumber() : 0;
        if (instPos < 0) {
            instPos = 0;
        }
        if (instPos > 30) {
            instPos = 30;
        }
        var instNeg = snap.ringG < 0.0 ? (-snap.ringG / 0.0333 + 0.5).toNumber() : 0;
        if (instNeg < 0) {
            instNeg = 0;
        }
        if (instNeg > 30) {
            instNeg = 30;
        }
        drawSegments(dc, cx, cy, midR, true, instPos, Graphics.COLOR_GREEN);
        drawSegments(dc, cx, cy, midR, false, instNeg, Graphics.COLOR_RED);
        // Peak-hold ticks. White, radial, sitting on the outside edge of
        // the ring.
        dc.setPenWidth(2);
        if (snap.peakHoldPos > 0.01) {
            drawTick(dc, cx, cy, outer, ringWidth, snap.peakHoldPos, true, Graphics.COLOR_WHITE);
        }
        if (snap.peakHoldNeg < -0.01) {
            drawTick(dc, cx, cy, outer, ringWidth, -snap.peakHoldNeg, false, Graphics.COLOR_WHITE);
        }
        // Zero mark at 12.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx, cy - outer - 1, cx, cy - outer + ringWidth + 2);
        // Scale notches at +1 g, +2 g and -0.5 g.
        drawNotch(dc, cx, cy, outer, ringWidth, 1.0, true);
        drawNotch(dc, cx, cy, outer, ringWidth, 2.0, true);
        drawNotch(dc, cx, cy, outer, ringWidth, 0.5 / 0.0333 * 0.1, false);
        // Inner yellow arc for horizontal G direction (felt-force).
        drawHArc(dc, cx, cy, midR - ringWidth / 2 - 10, snap.latG, snap.lonG);
        dc.setPenWidth(1);
    }

    // Draw |count| segments of 5° width on the positive (right) or negative
    // (left) half-ring. Segments are 6° apart, with a 1° gap.
    private function drawSegments(dc as Dc, cx as Number, cy as Number, r as Number, positive as Boolean, count as Number, color as Number) as Void {
        if (count <= 0) {
            return;
        }
        if (count > 30) {
            count = 30;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < count; i++) {
            var startDeg = 0.0;
            var endDeg = 0.0;
            if (positive) {
                startDeg = 89.5 - 6.0 * i;
                endDeg = 84.5 - 6.0 * i;
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, startDeg, endDeg);
            } else {
                startDeg = 90.5 + 6.0 * i;
                endDeg = 95.5 + 6.0 * i;
                dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, startDeg, endDeg);
            }
        }
    }

    private function drawTick(dc as Dc, cx as Number, cy as Number, outer as Number, ringWidth as Number, value as Float, positive as Boolean, color as Number) as Void {
        var angleDeg = 90.0;
        if (positive) {
            var step = value * 10.0;
            if (step > 30.0) {
                step = 30.0;
            }
            angleDeg = 90.0 - 6.0 * step;
        } else {
            var stepN = value / 0.0333;
            if (stepN > 30.0) {
                stepN = 30.0;
            }
            angleDeg = 90.0 + 6.0 * stepN;
        }
        var rad = Math.toRadians(angleDeg);
        var cosA = Math.cos(rad);
        var sinA = Math.sin(rad);
        var r1 = outer + 2;
        var r2 = outer - ringWidth - 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx + (r1 * cosA).toNumber(), cy - (r1 * sinA).toNumber(), cx + (r2 * cosA).toNumber(), cy - (r2 * sinA).toNumber());
    }

    private function drawNotch(dc as Dc, cx as Number, cy as Number, outer as Number, ringWidth as Number, step as Float, positive as Boolean) as Void {
        var angleDeg = positive ? 90.0 - 6.0 * step : 90.0 + 6.0 * step;
        var rad = Math.toRadians(angleDeg);
        var cosA = Math.cos(rad);
        var sinA = Math.sin(rad);
        var r1 = outer + 1;
        var r2 = outer - ringWidth / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx + (r1 * cosA).toNumber(), cy - (r1 * sinA).toNumber(), cx + (r2 * cosA).toNumber(), cy - (r2 * sinA).toNumber());
    }

    // Inner thin yellow arc. Felt-force convention: right turn → 3 o'clock,
    // braking → 12 o'clock. Length grows with the planar G magnitude.
    private function drawHArc(dc as Dc, cx as Number, cy as Number, r as Number, latG as Float, lonG as Float) as Void {
        if (r < 20) {
            return;
        }
        var mag2 = latG * latG + lonG * lonG;
        if (mag2 < 0.04) {
            return;
        }
        var mag = Math.sqrt(mag2);
        // Felt direction: the force on the body opposes the bike's accel.
        // Braking (lonG < 0) → body pushed forward → arc at 12 (90°).
        // Right turn (latG > 0) → body pushed right → arc at 3 (0°).
        var feltAngle = Math.toDegrees(Math.atan2(-lonG, latG));
        var halfSweep = mag * 30.0;
        if (halfSweep > 60.0) {
            halfSweep = 60.0;
        }
        var start = feltAngle - halfSweep;
        var end = feltAngle + halfSweep;
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, start, end);
    }

    private function drawGpsRing(dc as Dc, w as Number, h as Number) as Void {
        dc.setColor(gpsColor(_snap.gpsAccuracy), Graphics.COLOR_TRANSPARENT);
        // Thin stroke on a black field. AMOLED faces get a little more inset so the ring is not parked on the bezel.
        dc.setPenWidth(h >= 400 ? 3 : 4);
        var r = w / 2 - 3;
        if (h < w) {
            r = h / 2 - 3;
        }
        if (r > 200) {
            r = r - 8;
        }
        dc.drawCircle(w / 2, h / 2, r);
        dc.setPenWidth(1);
    }

    private function lineStep(h as Number) as Number {
        if (h >= 450) {
            return 36;
        }
        if (h >= 400) {
            return 32;
        }
        if (h >= 260) {
            return 26;
        }
        return 24;
    }

    // 240, 260, and 280 keep the top-weighted stack that fits the round MIP faces.
    // 416, 454, and 466 center that same stack so it does not sit in the top of the circle.
    private function lineTop(h as Number, step as Number, digitH as Number) as Number {
        if (h < 400) {
            return h >= 260 ? 10 : 6;
        }
        var block = step + digitH + 4 + step * 4;
        var y = (h - block) / 2;
        if (y < 28) {
            return 28;
        }
        return y;
    }

    private function trackBox(side as Number) as Number {
        var inset = 46;
        if (side >= 450) {
            inset = 78;
        } else if (side >= 400) {
            inset = 70;
        }
        return side / 2 - inset;
    }

    private function drawGpsBars(dc as Dc, w as Number, h as Number) as Void {
        var phase = _snap.phase;
        if (phase != PHASE_RECORDING && phase != PHASE_PAUSED) {
            return;
        }
        var acc = _snap.gpsAccuracy;
        var level = 0;
        var color = Graphics.COLOR_DK_GRAY;
        if (acc >= Position.QUALITY_GOOD) {
            level = 4;
            color = Graphics.COLOR_GREEN;
        } else if (acc >= Position.QUALITY_USABLE) {
            level = 2;
            color = Graphics.COLOR_YELLOW;
        } else if (acc >= Position.QUALITY_POOR) {
            level = 1;
            color = Graphics.COLOR_RED;
        }
        var bx = w / 2 + 76;
        if (w >= 280) {
            bx = w / 2 + 96;
        } else if (w >= 260) {
            bx = w / 2 + 86;
        }
        var base = h / 2 - 54;
        if (h >= 260) {
            base = h / 2 - 62;
        }
        var heights = [4, 7, 10, 13] as Array<Number>;
        for (var i = 0; i < 4; i++) {
            var bh = heights[i];
            dc.setColor(i < level ? color : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + i * 5, base - bh, 3, bh);
        }
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

    private function gpsDetail(accuracy as Number) as String {
        if (accuracy >= Position.QUALITY_USABLE) {
            return "READY";
        }
        return "SEARCHING";
    }

    private function gpsColor(accuracy as Number) as Number {
        if (accuracy >= Position.QUALITY_USABLE) {
            return Graphics.COLOR_GREEN;
        }
        if (accuracy >= Position.QUALITY_POOR) {
            return Graphics.COLOR_ORANGE;
        }
        return Graphics.COLOR_RED;
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
