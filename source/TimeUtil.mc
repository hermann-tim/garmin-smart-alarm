import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Helpers for local time, weekdays and formatting.
module TimeUtil {

    const DAY_NAMES = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];
    const DAY_SHORT = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];

    function nowSec() as Number {
        return Time.now().value();
    }

    function info(sec as Number) as Gregorian.Info {
        return Gregorian.info(new Time.Moment(sec), Time.FORMAT_SHORT);
    }

    // 0 = Monday ... 6 = Sunday
    function weekdayIndex(sec as Number) as Number {
        var dow = info(sec).day_of_week as Number; // 1 = Sunday ... 7 = Saturday
        return (dow + 5) % 7;
    }

    // Local midnight of the day that contains sec.
    function midnightOf(sec as Number) as Number {
        var i = info(sec);
        return sec - ((i.hour as Number) * 3600 + (i.min as Number) * 60 + (i.sec as Number));
    }

    // Point in time on a day (given by its midnight) at a minute of the day.
    // Corrects for daylight saving changes during the night.
    function atMinuteOfDay(midnight as Number, minutes as Number) as Number {
        var t = midnight + minutes * 60;
        var diff = minutes - minuteOfDay(t);
        if (diff > 720) {
            diff -= 1440;
        } else if (diff < -720) {
            diff += 1440;
        }
        return t + diff * 60;
    }

    // Next wake time from the weekly plan. Returns [deadlineSec, dayIndex].
    function nextDeadline(plan as Array<Number>, now as Number) as Array<Number> {
        var mid = midnightOf(now);
        var day = weekdayIndex(now);
        var today = atMinuteOfDay(mid, plan[day]);
        if (today > now + 60) {
            return [today, day];
        }
        var dayT = (day + 1) % 7;
        var midT = midnightOf(mid + 36 * 3600);
        return [atMinuteOfDay(midT, plan[dayT]), dayT];
    }

    function minuteOfDay(sec as Number) as Number {
        var i = info(sec);
        return (i.hour as Number) * 60 + (i.min as Number);
    }

    function wrapMin(m as Number) as Number {
        var r = m % 1440;
        if (r < 0) {
            r += 1440;
        }
        return r;
    }

    // 390 -> "06:30"
    function fmtHM(minutes as Number) as String {
        var m = wrapMin(minutes);
        return (m / 60).format("%02d") + ":" + (m % 60).format("%02d");
    }

    // Unix seconds -> local "06:42"
    function fmtClock(sec as Number) as String {
        return fmtHM(minuteOfDay(sec));
    }

    // Seconds -> "7:05 h"
    function fmtDur(sec as Number) as String {
        if (sec < 0) {
            sec = 0;
        }
        var mins = sec / 60;
        return (mins / 60).format("%d") + ":" + (mins % 60).format("%02d") + " h";
    }
}
