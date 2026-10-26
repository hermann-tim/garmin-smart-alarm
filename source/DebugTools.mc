import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Tools for testing in the simulator. Only in debug builds,
// release builds (the version for the watch) leave them out.

(:debug)
function addDebugItems(menu as WatchUi.Menu2) as Void {
    menu.addItem(new WatchUi.MenuItem("Demo-Nacht", "Weckt in 2 Minuten", :demoNight, null));
    menu.addItem(new WatchUi.MenuItem("Demo-Bericht", "Beispieldaten anzeigen", :demoReport, null));
    menu.addItem(new WatchUi.MenuItem("Demo-Lernen", "8 Beispielnächte lernen", :demoLearn, null));
}

(:release)
function addDebugItems(menu as WatchUi.Menu2) as Void {
}

(:debug)
function handleDebugItem(id as Object) as Void {
    if (id == :demoNight) {
        var app = getApp();
        var session = new NightSession(app.settings);
        app.session = session;
        session.begin(TimeUtil.nowSec() + 120);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.switchToView(new NightView(session), new NightDelegate(session), WatchUi.SLIDE_UP);
    } else if (id == :demoReport) {
        var v = new SummaryView(demoReport(), false);
        WatchUi.pushView(v, new SummaryDelegate(v), WatchUi.SLIDE_LEFT);
    } else if (id == :demoLearn) {
        demoLearn(getApp().model);
        var pv = new ProfileView();
        WatchUi.pushView(pv, new ProfileDelegate(pv), WatchUi.SLIDE_LEFT);
    }
}

// Teaches the profile 8 made-up nights with morning answers.
(:debug)
function demoLearn(model as SleepModel) as Void {
    var now = TimeUtil.nowSec();
    var feels = [FEEL_FIT, FEEL_OKAY, FEEL_FIT, FEEL_TIRED];
    for (var i = 0; i < 8; i++) {
        var s = new Array<Numeric>[NS_SIZE];
        var t = now - (8 - i) * 86400;
        s[NS_TIME] = t;
        s[NS_CYCLE] = 86 + (i % 3) * 3;
        s[NS_MINHR] = 49 + (i % 2);
        s[NS_RMSSD] = 46.0 + i;
        s[NS_STRESS] = 14.0;
        s[NS_RESP] = 13.8;
        s[NS_LIGHTHR] = 5.2;
        s[NS_EARLY] = (i % 3 == 2) ? 0 : 1;
        s[NS_EARLYMIN] = 8 + i;
        s[NS_FEEL] = -1;
        s[NS_SLEEPMIN] = 420;
        var comps = [0.85, 0.6, 0.3, 0.5, 0.2, 0.3, 0.7];
        for (var k = 0; k < COMP_COUNT; k++) {
            s[NS_COMPS + k] = comps[k];
        }
        if (model.learnNight(s) == LEARN_OK) {
            model.applyFeedback(t, feels[i % 4], false);
        }
    }
}

(:release)
function handleDebugItem(id as Object) as Void {
}

// ------------------------------------------------------------ night replay

// Replays a recorded night through the sleep engine and prints how every minute is
// classified now, next to the stages in the protocol and (if known) Garmin's stages.
// lines: the parts after "D<min>:" of the night protocol, in order (7 characters per minute).
// ref: Garmin's stage per minute as one letter (t deep, l light, r REM, w awake), or "".
// Used by tools/replay-night.ps1. The night data itself stays in the git-ignored logs folder.
(:debug)
function replayNight(lines as Array<String>, t0 as Number, ws as Number, dl as Number, sens as Number,
        model as SleepModel, ref as String) as Void {
    var e = new SleepEngine(model);
    e.setup(t0, ws, dl, sens);
    var oldS = "";
    var newS = "";
    var scores = "";
    var minute = 0;
    var wakeMin = -1;
    var wakeText = "";
    for (var l = 0; l < lines.size(); l++) {
        var line = lines[l];
        var n = line.length() / 7;
        for (var j = 0; j < n; j++) {
            var v = new Array<Number>[7];
            for (var k = 0; k < 7; k++) {
                v[k] = decodeLogChar(line, j * 7 + k);
            }
            var m = (v[0] < 0) ? 0.0 : v[0] / 63.0;
            var hr = (v[1] < 0) ? -1 : v[1] + 30;
            var rm = (v[2] < 0) ? -1.0 : v[2] * 3.0 + 1.0;
            var st = (v[3] < 0) ? -1 : v[3] * 2;
            var rr = (v[4] < 0) ? -1.0 : 4.0 + v[4] / 4.0;
            var t = t0 + (minute + 1) * 60;
            e.injectEpoch(t, m, hr, rm, st, rr);
            oldS += stageLetter(v[6]);
            newS += stageLetter(e.stageNow);
            if (t > ws - 600) {
                scores += " " + minute + ":" + e.lightNow();
            }
            if (wakeMin < 0 && e.pendingKind() >= 0) {
                wakeMin = minute;
                wakeText = e.pendingText();
            }
            minute += 1;
        }
    }

    System.println("REPLAY minutes=" + minute + " sens=" + sens);
    for (var i = 0; i < minute; i += 60) {
        var end = (i + 60 < minute) ? i + 60 : minute;
        if (ref.length() > i) {
            System.println("REPLAY " + i.format("%3d") + " garmin " + part(ref, i, end));
        }
        System.println("REPLAY " + i.format("%3d") + " before " + part(oldS, i, end));
        System.println("REPLAY " + i.format("%3d") + " now    " + part(newS, i, end));
    }

    // Count from Garmin's sleep onset if known, else from the start.
    var from = 0;
    while (from < ref.length() && part(ref, from, from + 1).equals("w")) {
        from += 1;
    }
    System.println("REPLAY counted from minute " + from);
    System.println("REPLAY before: " + compareStages(oldS, ref, from));
    System.println("REPLAY now:    " + compareStages(newS, ref, from));
    if (ref.length() > 0) {
        System.println("REPLAY garmin: deep=" + countLetter(ref, "t", from) + " rem=" + countLetter(ref, "r", from)
            + " light=" + countLetter(ref, "l", from) + " awake=" + countLetter(ref, "w", from));
    }
    System.println("REPLAY scores near the window:" + scores);
    if (wakeMin >= 0) {
        System.println("REPLAY wake decision: minute " + wakeMin + " kind " + e.pendingKind() + " (" + wakeText + ")");
    } else {
        System.println("REPLAY wake decision: none, rings at the wake time");
    }
}

// Tries many wake times on one recorded night: for every deadline from fromMin to toMin
// (minutes after the start) a fresh engine runs through the night, and the wake-up minute,
// its reason and Garmin's stage at that minute are printed.
(:debug)
function replaySweep(lines as Array<String>, t0 as Number, sens as Number, model as SleepModel, ref as String,
        fromMin as Number, toMin as Number, step as Number, windowMin as Number) as Void {
    for (var d = fromMin; d <= toMin; d += step) {
        var dl = t0 + d * 60;
        var e = new SleepEngine(model);
        e.setup(t0, dl - windowMin * 60, dl, sens);
        var minute = 0;
        var wakeMin = -1;
        for (var l = 0; l < lines.size() && wakeMin < 0 && minute < d; l++) {
            var line = lines[l];
            var n = line.length() / 7;
            for (var j = 0; j < n && wakeMin < 0 && minute < d; j++) {
                var v = new Array<Number>[5];
                for (var k = 0; k < 5; k++) {
                    v[k] = decodeLogChar(line, j * 7 + k);
                }
                e.injectEpoch(t0 + (minute + 1) * 60, (v[0] < 0) ? 0.0 : v[0] / 63.0, (v[1] < 0) ? -1 : v[1] + 30,
                    (v[2] < 0) ? -1.0 : v[2] * 3.0 + 1.0, (v[3] < 0) ? -1 : v[3] * 2, (v[4] < 0) ? -1.0 : 4.0 + v[4] / 4.0);
                if (e.pendingKind() >= 0) {
                    wakeMin = minute;
                }
                minute += 1;
            }
        }
        var at = (wakeMin >= 0) ? wakeMin : d;
        System.println("REPLAY deadline=" + d + " wake=" + at + " early=" + (d - at) + " kind="
            + ((wakeMin >= 0) ? e.pendingKind() : REASON_DEADLINE) + " garmin=" + part(ref, at, at + 1)
            + " (" + ((wakeMin >= 0) ? e.pendingText() : "Weckzeit") + ")");
    }
}

// Stage counts and, with Garmin's stages, how many deep minutes match.
(:debug)
function compareStages(s as String, ref as String, from as Number) as String {
    var out = "deep=" + countLetter(s, "t", from) + " light=" + countLetter(s, "l", from)
        + " awake=" + countLetter(s, "w", from) + " nodata=" + countLetter(s, "-", from);
    if (ref.length() > 0) {
        var hit = 0;
        var wrong = 0;
        var remDeep = 0;
        for (var i = from; i < s.length() && i < ref.length(); i++) {
            if (part(s, i, i + 1).equals("t")) {
                var g = part(ref, i, i + 1);
                if (g.equals("t")) {
                    hit += 1;
                } else {
                    wrong += 1;
                    if (g.equals("r")) {
                        remDeep += 1;
                    }
                }
            }
        }
        out += " | deep same as garmin=" + hit + " deep where garmin not=" + wrong + " (of it REM=" + remDeep + ")";
    }
    return out;
}

(:debug)
function countLetter(s as String, letter as String, from as Number) as Number {
    var n = 0;
    for (var i = from; i < s.length(); i++) {
        if (part(s, i, i + 1).equals(letter)) {
            n += 1;
        }
    }
    return n;
}

(:debug)
function part(s as String, a as Number, b as Number) as String {
    if (b > s.length()) {
        b = s.length();
    }
    if (a >= b) {
        return "";
    }
    var p = s.substring(a, b);
    return (p != null) ? p : "";
}

(:debug)
function decodeLogChar(s as String, i as Number) as Number {
    var c = part(s, i, i + 1);
    if (c.length() == 0) {
        return -1;
    }
    var idx = NightLog.ALPHABET.find(c);
    return (idx != null) ? idx : -1;
}

// t = deep, l = light, w = awake, - = no data
(:debug)
function stageLetter(stage as Number) as String {
    if (stage < 0 || stage > 3) {
        return "?";
    }
    return ["t", "l", "w", "-"][stage];
}

// A made-up night with 90 minute sleep cycles.
(:debug)
function demoReport() as Dictionary {
    var n = 450;
    var start = TimeUtil.nowSec() - n * 60;
    var stages = new Array<Number>[n];
    for (var i = 0; i < n; i++) {
        var cycle = (i % 90) / 90.0;
        var depth = Math.sin(cycle * Math.PI) * (1.0 - i / (n * 1.4));
        var stage = (depth > 0.55) ? STAGE_DEEP : STAGE_LIGHT;
        if (i % 90 > 86 || i < 12 || (i % 137 == 0)) {
            stage = STAGE_WAKE;
        }
        if (i >= 300 && i < 306) {
            stage = STAGE_NODATA;
        }
        stages[i] = stage;
    }
    return {
        "v" => 1,
        "st" => start,
        "on" => start + 14 * 60,
        "wu" => start + n * 60,
        "dl" => start + n * 60 + 18 * 60,
        "ws" => start + n * 60 - 12 * 60,
        "rk" => REASON_LIGHT,
        "rs" => "Leichtschlaf: Puls höher, HRV niedriger",
        "sl" => (n - 30) * 60,
        "pc" => [21, 72, 7],
        "mv" => 23,
        "hrA" => 56,
        "hrM" => 49,
        "rm" => 46,
        "sa" => 14,
        "rr" => 138,
        "bb" => 54,
        "S" => stages,
        "nd" => 6,
        "ev" => [
            TimeUtil.fmtClock(start) + "  Start, Wecker " + TimeUtil.fmtClock(start + n * 60 + 18 * 60),
            TimeUtil.fmtClock(start + n * 60) + "  Leichtschlaf: Puls höher, HRV niedriger",
            TimeUtil.fmtClock(start + n * 60 + 60) + "  Wecker aus"
        ]
    };
}
