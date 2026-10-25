import Toybox.Lang;
import Toybox.Math;
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

// A made-up night with 90 minute sleep cycles.
(:debug)
function demoReport() as Dictionary {
    var n = 450;
    var start = TimeUtil.nowSec() - n * 60;
    var stages = new Array<Number>[n];
    var hr = new Array<Number>[n];
    var light = new Array<Number>[n];
    for (var i = 0; i < n; i++) {
        var cycle = (i % 90) / 90.0;
        var depth = Math.sin(cycle * Math.PI) * (1.0 - i / (n * 1.4));
        var stage = (depth > 0.55) ? STAGE_DEEP : STAGE_LIGHT;
        if (i % 90 > 86 || i < 12 || (i % 137 == 0)) {
            stage = STAGE_WAKE;
        }
        stages[i] = stage;
        hr[i] = (60 - depth * 8).toNumber();
        light[i] = (70 - depth * 60).toNumber();
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
        "L" => light,
        "S" => stages,
        "H" => hr,
        "ev" => [
            TimeUtil.fmtClock(start) + "  Start, Wecker " + TimeUtil.fmtClock(start + n * 60 + 18 * 60),
            TimeUtil.fmtClock(start + n * 60) + "  Leichtschlaf: Puls höher, HRV niedriger",
            TimeUtil.fmtClock(start + n * 60 + 60) + "  Wecker aus"
        ]
    };
}
