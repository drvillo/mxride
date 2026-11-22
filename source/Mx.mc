import Toybox.Lang;
import Toybox.Math;

module Mx {
    const CARDINALS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] as Array<String>;

    function headingDegrees(radians as Float) as Number {
        return (Math.toDegrees(radians) + 360.5).toNumber() % 360;
    }

    function cardinal(degrees as Number) as String {
        return CARDINALS[((degrees * 2 + 45) / 90) % 8];
    }

    function kmh(metersPerSecond as Float) as Float {
        return metersPerSecond * 3.6;
    }

    function zoneIndex(heartRate as Number, zones as Array<Number>) as Number {
        if (zones.size() < 6 || heartRate < zones[0]) {
            return 0;
        }
        for (var i = 1; i <= 5; i++) {
            if (heartRate <= zones[i]) {
                return i;
            }
        }
        return 5;
    }

    function formatTimer(milliseconds as Number) as String {
        var seconds = milliseconds / 1000;
        var hours = seconds / 3600;
        var minutes = (seconds / 60) % 60;
        var rest = (seconds % 60).format("%02d");
        if (hours > 0) {
            return Lang.format("$1$:$2$:$3$", [hours, minutes.format("%02d"), rest]);
        }
        return Lang.format("$1$:$2$", [minutes, rest]);
    }

    function formatDistance(meters as Float or Null) as String {
        if (meters == null) {
            return "--";
        }
        return (meters / 1000.0).format("%.2f");
    }

    function formatNumber(value as Number or Null) as String {
        return value == null ? "--" : value.toString();
    }
}
