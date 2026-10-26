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
    // Corrects for daylight saving changes during the night. A time that the clock
    // skips in spring (e.g. 02:30) becomes the time an hour later (03:30), never earlier.
    // A time that happens twice in autumn is the first one.
    function atMinuteOfDay(midnight as Number, minutes as Number) as Number {
        var t = midnight + minutes * 60;
        var diff = minutes - minuteOfDay(t);
        if (diff > 720) {
            diff -= 1440;
        } else if (diff < -720) {
            diff += 1440;
        }
        var c = t + diff * 60;
        if (c < t && minuteOfDay(c) != minutes) {
            return t;
        }
        return c;
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

    // Tonight's alarm from the weekly plan plus a change for tonight only (offsetMin).
    // Returns [deadlineSec, dayIndex, wakeMinutes, planMinutes].
    // The alarm stays on the day the plan entry belongs to, e.g. Friday 08:00 with
    // "Friday 07:00, Saturday 09:00" gives Saturday 09:00 (not Friday 09:00).
    function planTarget(plan as Array<Number>, offsetMin as Number, now as Number) as Array<Number> {
        var next = nextDeadline(plan, now);
        var planMin = plan[next[1]];
        var wake = planMin + offsetMin;
        if (wake < 0) {
            wake = 0;
        } else if (wake > 1435) {
            wake = 1435;
        }
        var dl = atMinuteOfDay(midnightOf(next[0]), wake);
        if (dl <= now + 60) {
            // the changed time is already over on that day: the next time the clock shows it
            dl = nextOccurrence(wake, now);
        }
        return [dl, weekdayIndex(dl), wake, planMin];
    }

    // Next time the clock shows this minute of the day: today if still ahead, otherwise tomorrow.
    function nextOccurrence(minutes as Number, now as Number) as Number {
        var mid = midnightOf(now);
        var t = atMinuteOfDay(mid, minutes);
        if (t <= now + 60) {
            t = atMinuteOfDay(midnightOf(mid + 36 * 3600), minutes);
        }
        return t;
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
