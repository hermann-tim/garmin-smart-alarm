import Toybox.Application;
import Toybox.Lang;
import Toybox.UserProfile;

// All user settings. Stored on the watch.
class AppSettings {

    // Wake time per weekday in minutes after midnight. Index 0 = Monday ... 6 = Sunday.
    var plan as Array<Number> = [420, 420, 420, 420, 420, 420, 420];
    var windowMin as Number = 30;    // wake window before the wake time (10-60, steps of 5)
    var snoozeOn as Boolean = true;
    var snoozeMin as Number = 5;
    var snoozeMax as Number = 3;
    var vibeLevel as Number = 2;     // 1 = gentle, 2 = normal, 3 = intense
    var toneOn as Boolean = false;
    var sensitivity as Number = 3;   // 1 = only clear signals ... 5 = wakes earliest

    function initialize() {
    }

    function load() as Void {
        var d = Application.Storage.getValue("settings");
        if (d instanceof Dictionary) {
            var p = d.get("plan");
            if (p instanceof Array && p.size() == 7) {
                for (var i = 0; i < 7; i++) {
                    var v = p[i];
                    if (v instanceof Number && v >= 0 && v < 1440) {
                        plan[i] = v;
                    }
                }
            }
            windowMin = readNum(d, "win", windowMin, 10, 60);
            snoozeOn = readBool(d, "snz", snoozeOn);
            snoozeMin = readNum(d, "snzMin", snoozeMin, 1, 20);
            snoozeMax = readNum(d, "snzMax", snoozeMax, 1, 5);
            vibeLevel = readNum(d, "vibe", vibeLevel, 1, 3);
            toneOn = readBool(d, "tone", toneOn);
            sensitivity = readNum(d, "sens", sensitivity, 1, 5);
        } else {
            // First start: take the wake time from the Garmin user profile.
            var wake = profileWakeMinutes();
            if (wake != null) {
                for (var i = 0; i < 7; i++) {
                    plan[i] = wake;
                }
            }
            save();
        }
    }

    function save() as Void {
        Application.Storage.setValue("settings", {
            "plan" => plan,
            "win" => windowMin,
            "snz" => snoozeOn,
            "snzMin" => snoozeMin,
            "snzMax" => snoozeMax,
            "vibe" => vibeLevel,
            "tone" => toneOn,
            "sens" => sensitivity
        });
    }

    function vibeLabel() as String {
        return ["Sanft", "Normal", "Intensiv"][vibeLevel - 1];
    }

    function sensLabel() as String {
        return ["Sehr vorsichtig", "Vorsichtig", "Ausgewogen", "Früher", "Am frühesten"][sensitivity - 1];
    }

    // "Mo-Fr 06:30 · Sa-So 09:00"
    function planSummary() as String {
        var out = "";
        var i = 0;
        while (i < 7) {
            var j = i;
            while (j + 1 < 7 && plan[j + 1] == plan[i]) {
                j++;
            }
            if (i == 0 && j == 6) {
                return "Täglich " + TimeUtil.fmtHM(plan[0]);
            }
            var days = (i == j) ? TimeUtil.DAY_SHORT[i] : TimeUtil.DAY_SHORT[i] + "-" + TimeUtil.DAY_SHORT[j];
            if (out.length() > 0) {
                out += " · ";
            }
            out += days + " " + TimeUtil.fmtHM(plan[i]);
            i = j + 1;
        }
        return out;
    }

    private function readNum(d as Dictionary, key as String, def as Number, lo as Number, hi as Number) as Number {
        var v = d.get(key);
        if (v instanceof Number && v >= lo && v <= hi) {
            return v;
        }
        return def;
    }

    private function readBool(d as Dictionary, key as String, def as Boolean) as Boolean {
        var v = d.get(key);
        if (v instanceof Boolean) {
            return v;
        }
        return def;
    }

    private function profileWakeMinutes() as Number or Null {
        try {
            var p = UserProfile.getProfile();
            var w = p.wakeTime;
            if (w != null) {
                var m = ((w.value() / 60 + 2) / 5) * 5;
                if (m >= 0 && m < 1440) {
                    return m;
                }
            }
        } catch (e) {
        }
        return null;
    }
}
