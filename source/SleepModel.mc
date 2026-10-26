import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

// Starting weights: movement counts most, the cycle clock and breathing least.
function defaultSignalWeights() as Array<Float> {
    return [0.30, 0.18, 0.10, 0.12, 0.12, 0.06, 0.12] as Array<Float>;
}

function signalName(k as Number) as String {
    return ["Bewegung", "Puls", "Pulsunruhe", "HRV", "Stress", "Atmung", "Zyklus"][k];
}

// Signals the sleep engine combines. The model learns how much each one counts.
const COMP_MOVE = 0;      // movement
const COMP_HR = 1;        // heart rate above the resting level
const COMP_UNREST = 2;    // heart rate changing from minute to minute
const COMP_HRV = 3;       // HRV below the usual level
const COMP_STRESS = 4;    // Garmin stress above the usual level
const COMP_RESP = 5;      // breathing faster or less even
const COMP_CYCLE = 6;     // end of a sleep cycle is near
const COMP_COUNT = 7;

// Result of learning from a night
const LEARN_OK = 0;
const LEARN_SHORT = 1;    // too short (nap, test) or too little heart rate data
const LEARN_OUTLIER = 2;  // unusual night (alcohol, illness, late training ...)
const LEARN_NONE = 3;     // nothing learned (night ended early)

// Morning answer
const FEEL_TIRED = 0;
const FEEL_OKAY = 1;
const FEEL_FIT = 2;

// One night in the history is a short array with these fields
const NS_TIME = 0;        // wake-up time (unix seconds), used as key
const NS_CYCLE = 1;       // cycle length seen this night (minutes), -1 = unknown
const NS_MINHR = 2;       // lowest 10 % heart rate, -1 = unknown
const NS_RMSSD = 3;       // average HRV (RMSSD, ms), -1 = unknown
const NS_STRESS = 4;      // average stress, -1 = unknown
const NS_RESP = 5;        // average breathing rate, -1 = unknown
const NS_LIGHTHR = 6;     // typical heart rate rise in light sleep, -1 = unknown
const NS_EARLY = 7;       // 1 = woken early by the smart logic, 0 = at the wake time
const NS_EARLYMIN = 8;    // minutes before the wake time
const NS_FEEL = 9;        // FEEL_* or -1
const NS_SLEEPMIN = 10;   // minutes asleep
const NS_COMPS = 11;      // COMP_COUNT signal values at the wake-up moment (-1 = missing)
const NS_SIZE = 18;

// The personal memory of SmartWake. Keeps compact summaries of the last 21
// nights (no raw data) and learned values:
//   - resting heart rate, HRV, stress and breathing as the user's normal level
//   - typical heart rate rise in light sleep and the personal cycle length
//   - how much each signal counts, and how strict the wake decision is
// Recent nights count most (exponential average), the first nights count extra
// so the profile becomes personal quickly. Unusual nights are left out.
class SleepModel {

    const MAX_NIGHTS = 21;
    const ALPHA = 0.18;
    const MIN_SLEEP_MIN = 180;

    var nights as Number = 0;        // learned nights in total
    var minHr as Float = -1.0;
    var hrStd as Float = 3.5;
    var rmssd as Float = -1.0;
    var stress as Float = -1.0;
    var resp as Float = -1.0;
    var lightHr as Float = 4.5;
    var cycleMin as Float = 90.0;
    var shift as Float = 0.0;        // + = stricter wake decision, - = wakes more readily
    var weights as Array<Float>;
    var history as Array<Array<Numeric>>;
    var persist as Boolean = true;   // false in unit tests: nothing is written to storage

    function initialize() {
        weights = defaultSignalWeights();
        history = [] as Array<Array<Numeric>>;
    }

    // ----------------------------------------------------------- storage

    function load() as Void {
        var d = Application.Storage.getValue("model");
        if (!(d instanceof Dictionary)) {
            return;
        }
        nights = num(d.get("n"), 0);
        minHr = flt(d.get("hr"), -1.0);
        hrStd = flt(d.get("hs"), 3.5);
        rmssd = flt(d.get("rm"), -1.0);
        stress = flt(d.get("st"), -1.0);
        resp = flt(d.get("rr"), -1.0);
        lightHr = flt(d.get("lh"), 4.5);
        cycleMin = flt(d.get("cy"), 90.0);
        shift = flt(d.get("sh"), 0.0);
        var w = d.get("w");
        if (w instanceof Array && w.size() == COMP_COUNT) {
            for (var k = 0; k < COMP_COUNT; k++) {
                weights[k] = flt(w[k], weights[k]);
            }
        }
        var h = d.get("h");
        if (h instanceof Array) {
            for (var i = 0; i < h.size(); i++) {
                var night = h[i];
                if (night instanceof Array && night.size() == NS_SIZE) {
                    history.add(night as Array<Numeric>);
                }
            }
        }
    }

    // A full watch storage must not crash the app (it is called right after the alarm
    // starts); then this night's learning is simply not kept.
    function save() as Void {
        if (!persist) {
            return;
        }
        try {
            Application.Storage.setValue("model", {
                "v" => 1,
                "n" => nights,
                "hr" => minHr,
                "hs" => hrStd,
                "rm" => rmssd,
                "st" => stress,
                "rr" => resp,
                "lh" => lightHr,
                "cy" => cycleMin,
                "sh" => shift,
                "w" => weights,
                "h" => history
            });
        } catch (e) {
        }
    }

    function reset() as Void {
        nights = 0;
        minHr = -1.0;
        hrStd = 3.5;
        rmssd = -1.0;
        stress = -1.0;
        resp = -1.0;
        lightHr = 4.5;
        cycleMin = 90.0;
        shift = 0.0;
        weights = defaultSignalWeights();
        history = [] as Array<Array<Numeric>>;
        save();
    }

    // ---------------------------------------------------------- learning

    // Step 1 (right when the alarm goes off): learn the night's values.
    function learnNight(s as Array<Numeric>) as Number {
        if (s[NS_SLEEPMIN] < MIN_SLEEP_MIN || s[NS_MINHR] <= 0) {
            return LEARN_SHORT;
        }
        // A resting heart rate far above normal points to alcohol, illness or a hard
        // late workout. Such a night would distort the profile, so it is skipped.
        if (history.size() >= 5 && minHr > 0.0) {
            var z = (s[NS_MINHR].toFloat() - minHr) / maxf(1.5, hrStd);
            if (z > 1.8) {
                return LEARN_OUTLIER;
            }
        }

        history.add(s);
        if (history.size() > MAX_NIGHTS) {
            history = history.slice(1, null) as Array<Array<Numeric>>;
        }
        nights += 1;

        // Recent nights count most. The first nights count extra (1/n),
        // so after about five nights the values are personal.
        var a = 1.0 / nights;
        if (a < ALPHA) {
            a = ALPHA;
        }
        minHr = ewma(minHr, s[NS_MINHR].toFloat(), a);
        if (s[NS_RMSSD] > 0) {
            rmssd = ewma(rmssd, s[NS_RMSSD].toFloat(), a);
        }
        if (s[NS_STRESS] >= 0) {
            stress = ewma(stress, s[NS_STRESS].toFloat(), a);
        }
        if (s[NS_RESP] > 0) {
            resp = ewma(resp, s[NS_RESP].toFloat(), a);
        }
        if (s[NS_LIGHTHR] > 0) {
            lightHr = clampf(ewma(lightHr, s[NS_LIGHTHR].toFloat(), a), 1.5, 12.0);
        }
        // Cycle length: this night's value plus the median of all stored nights
        if (s[NS_CYCLE] > 0) {
            var target = 0.6 * s[NS_CYCLE].toFloat() + 0.4 * medianCycle();
            cycleMin = clampf((1.0 - a) * cycleMin + a * target, 75.0, 110.0);
        }
        // How much the resting heart rate varies between nights
        if (history.size() >= 3) {
            var mean = 0.0;
            for (var i = 0; i < history.size(); i++) {
                mean += history[i][NS_MINHR].toFloat();
            }
            mean /= history.size();
            var v = 0.0;
            for (var i = 0; i < history.size(); i++) {
                var d = history[i][NS_MINHR].toFloat() - mean;
                v += d * d;
            }
            hrStd = maxf(1.5, Math.sqrt(v / history.size()).toFloat());
        }
        save();
        return LEARN_OK;
    }

    // Step 2 (after the morning question): learn from how the wake-up felt.
    // implicit = no answer given, but snoozed a lot (counts as half "tired").
    function applyFeedback(key as Number, feel as Number, implicit as Boolean) as Boolean {
        var s = findNight(key);
        if (s == null) {
            return false;
        }
        s[NS_FEEL] = implicit ? -1 : feel;
        var reward = implicit ? -0.5 : [-1.0, 0.0, 1.0][feel];
        var early = s[NS_EARLY] > 0;

        // Signal weights: only when SmartWake chose the moment itself.
        // Good wake-up: signals that were above average at that moment count more.
        // Bad wake-up: those signals misled, they count less.
        if (early && reward != 0.0) {
            var mean = 0.0;
            var n = 0;
            for (var k = 0; k < COMP_COUNT; k++) {
                var c = s[NS_COMPS + k].toFloat();
                if (c >= 0.0) {
                    mean += c;
                    n += 1;
                }
            }
            if (n > 0) {
                mean /= n;
                for (var k = 0; k < COMP_COUNT; k++) {
                    var c = s[NS_COMPS + k].toFloat();
                    if (c >= 0.0) {
                        weights[k] = clampf(weights[k] + 0.04 * reward * (c - mean), 0.04, 0.45);
                    }
                }
                normalizeWeights();
            }
        }

        // Strictness of the wake decision
        if (reward < 0.0) {
            var step = implicit ? 1.5 : 3.0;
            // woken early but tired: be stricter. Woken at the wake time and tired: be more willing.
            shift += early ? step : -step;
        } else if (reward > 0.0 && early && shift > 0.0) {
            // Woken early and fit: the setting worked. Earlier strictness slowly fades,
            // but good mornings never make it looser than neutral (that would drift
            // towards waking too early).
            shift = maxf(0.0, shift - 0.5);
        }
        shift = clampf(shift, -12.0, 12.0);
        save();
        return true;
    }

    // --------------------------------------------------------- read-outs

    function storedNights() as Number {
        return history.size();
    }

    // [tired, okay, fit] answers among the stored nights
    function feelCounts() as Array<Number> {
        var c = [0, 0, 0];
        for (var i = 0; i < history.size(); i++) {
            var f = history[i][NS_FEEL].toNumber();
            if (f >= 0 && f <= 2) {
                c[f] += 1;
            }
        }
        return c;
    }

    // Average minutes woken before the wake time (only early wake-ups), -1 = none
    function avgEarlyMinutes() as Number {
        var sum = 0;
        var n = 0;
        for (var i = 0; i < history.size(); i++) {
            if (history[i][NS_EARLY] > 0) {
                sum += history[i][NS_EARLYMIN].toNumber();
                n += 1;
            }
        }
        return (n > 0) ? (sum + n / 2) / n : -1;
    }

    // One line with everything learned, for the night protocol
    function describe() as String {
        var w = "";
        for (var k = 0; k < COMP_COUNT; k++) {
            w += ((k > 0) ? "," : "") + (weights[k] * 100.0 + 0.5).toNumber();
        }
        return "n=" + nights + " stored=" + history.size() + " hr=" + minHr.format("%.1f") + " hs=" + hrStd.format("%.1f")
            + " rm=" + rmssd.format("%.1f") + " st=" + stress.format("%.1f") + " rr=" + resp.format("%.1f")
            + " lh=" + lightHr.format("%.1f") + " cy=" + cycleMin.format("%.1f") + " sh=" + shift.format("%.1f") + " w=" + w;
    }

    // ----------------------------------------------------------- helpers

    private function findNight(key as Number) as Array<Numeric> or Null {
        for (var i = history.size() - 1; i >= 0; i--) {
            if (history[i][NS_TIME].toNumber() == key) {
                return history[i];
            }
        }
        return null;
    }

    private function medianCycle() as Float {
        var vals = [] as Array<Float>;
        for (var i = 0; i < history.size(); i++) {
            var c = history[i][NS_CYCLE].toFloat();
            if (c > 0.0) {
                vals.add(c);
            }
        }
        if (vals.size() == 0) {
            return cycleMin;
        }
        // small insertion sort (at most 21 values)
        for (var i = 1; i < vals.size(); i++) {
            var x = vals[i];
            var j = i - 1;
            while (j >= 0 && vals[j] > x) {
                vals[j + 1] = vals[j];
                j--;
            }
            vals[j + 1] = x;
        }
        return vals[vals.size() / 2];
    }

    private function normalizeWeights() as Void {
        var sum = 0.0;
        for (var k = 0; k < COMP_COUNT; k++) {
            sum += weights[k];
        }
        if (sum > 0.0) {
            for (var k = 0; k < COMP_COUNT; k++) {
                weights[k] = weights[k] / sum;
            }
        }
    }

    private function ewma(old as Float, value as Float, a as Float) as Float {
        if (old < 0.0) {
            return value;
        }
        return (1.0 - a) * old + a * value;
    }

    private function clampf(v as Float, lo as Float, hi as Float) as Float {
        if (v < lo) {
            return lo;
        }
        return (v > hi) ? hi : v;
    }

    private function maxf(a as Float, b as Float) as Float {
        return (a > b) ? a : b;
    }

    private function num(v, def as Number) as Number {
        return (v instanceof Number) ? v : def;
    }

    private function flt(v, def as Float) as Float {
        if (v instanceof Float) {
            return v;
        }
        if (v instanceof Number) {
            return v.toFloat();
        }
        return def;
    }
}
