import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

const PHASE_TRACK = 0;
const PHASE_ALARM = 1;
const PHASE_SNOOZE = 2;

// One night: measuring, waking up, snoozing, morning report.
// The state is stored, so a night survives an app restart.
class NightSession {

    var phase as Number = PHASE_TRACK;
    var start as Number = 0;
    var windowStart as Number = 0;
    var deadline as Number = 0;
    var alarmAt as Number = 0;            // first alarm of the morning
    var ringAt as Number = 0;             // start of the current ringing (changes after snoozing)
    var restarts as Number = 0;           // how often the app was reopened during the night
    var snoozeUntil as Number = 0;
    var snoozeCount as Number = 0;
    var reasonKind as Number = REASON_DEADLINE;
    var reasonText as String = "";
    var engine as SleepEngine or Null = null;
    var player as AlarmPlayer;
    var overlayOpen as Boolean = false;   // exit dialog shown above the night screen
    var screenUntil as Number = 0;        // night screen shows its content until then (System.getTimer), then black

    private var _settings as AppSettings;
    private var _timer as Timer.Timer;
    private var _events as Array<String> = [] as Array<String>;
    private var _report as Dictionary or Null = null;

    function initialize(settings as AppSettings) {
        _settings = settings;
        _timer = new Timer.Timer();
        player = new AlarmPlayer();
    }

    // ------------------------------------------------------- start / resume

    function begin(deadlineSec as Number) as Void {
        var now = TimeUtil.nowSec();
        start = now;
        deadline = deadlineSec;
        windowStart = deadline - _settings.windowMin * 60;
        if (windowStart < now) {
            windowStart = now;
        }
        phase = PHASE_TRACK;
        log(now, "Start, Wecker " + TimeUtil.fmtClock(deadline));
        NightLog.write("START t=" + now + " dl=" + deadline + " ws=" + windowStart + " sens=" + _settings.sensitivity
            + " vibe=" + _settings.vibeLevel + " tone=" + _settings.toneOn);
        NightLog.write("MODEL " + getApp().model.describe());
        startTracking(now);
    }

    // Continue a stored night after the app was closed. Returns false if it is too old.
    function restore(d as Dictionary, now as Number) as Boolean {
        phase = num(d, "ph");
        start = num(d, "st");
        windowStart = num(d, "ws");
        deadline = num(d, "dl");
        alarmAt = num(d, "aa");
        ringAt = num(d, "ra");
        if (ringAt <= 0) {
            ringAt = alarmAt;
        }
        restarts = num(d, "rn");
        snoozeUntil = num(d, "su");
        snoozeCount = num(d, "sc");
        reasonKind = num(d, "rk");
        var rs = d.get("rs");
        reasonText = (rs instanceof String) ? rs : "";
        var ev = d.get("ev");
        if (ev instanceof Array) {
            for (var i = 0; i < ev.size(); i++) {
                var line = ev[i];
                if (line instanceof String) {
                    _events.add(line);
                }
            }
        }
        if (deadline <= 0) {
            return false;
        }

        if (phase == PHASE_TRACK) {
            // The measurement starts again from now on (the data before is lost),
            // the morning report shows that the night was interrupted.
            restarts += 1;
            if (now < deadline - 60) {
                log(now, "App neu gestartet");
                NightLog.write("RESTART t=" + now + " dl=" + deadline);
                startTracking(now);
                return true;
            }
            if (now < deadline + 1800) {
                // The wake time passed while the app was closed: ring now.
                phase = PHASE_ALARM;
                alarmAt = now;
                ringAt = now;
                reasonKind = REASON_DEADLINE;
                reasonText = "Weckzeit erreicht";
                log(now, reasonText);
                NightLog.write("LATE t=" + now + " dl=" + deadline);
                persist();
                keepReport(minimalReport(now, reasonKind, reasonText));
                return true;
            }
            return false;
        }

        loadReport();
        if (phase == PHASE_ALARM) {
            // Counted from the current ringing, so a snoozed alarm survives a restart too.
            return now < ringAt + 1800;
        }
        if (phase == PHASE_SNOOZE) {
            if (now < snoozeUntil) {
                _timer.start(method(:onTick), 1000, true);
                return true;
            }
            if (now < snoozeUntil + 1800) {
                phase = PHASE_ALARM;
                ringAt = now;
                persist();
                return true;
            }
        }
        return false;
    }

    function initialView() as [WatchUi.Views, WatchUi.InputDelegates] {
        if (phase == PHASE_ALARM) {
            player.start(_settings.vibeLevel, _settings.toneOn, 1);
            return [new AlarmView(self, player, false), new AlarmDelegate(self)];
        }
        if (phase == PHASE_SNOOZE) {
            return [new SnoozeView(self), new SnoozeDelegate(self)];
        }
        return [new NightView(self), new NightDelegate(self)];
    }

    private function startTracking(now as Number) as Void {
        var e = new SleepEngine(getApp().model);
        e.start(now, windowStart, deadline, _settings.sensitivity);
        engine = e;
        persist();
        _timer.stop();
        _timer.start(method(:onTick), 5000, true);
    }

    function onTick() as Void {
        var now = TimeUtil.nowSec();
        if (phase == PHASE_TRACK) {
            var e = engine;
            if (e != null) {
                e.tick(now);
                if (e.pendingKind() >= 0) {
                    ring(e.pendingKind(), e.pendingText());
                    return;
                }
            }
            if (now >= deadline) {
                ring(REASON_DEADLINE, "Weckzeit erreicht");
                return;
            }
        } else if (phase == PHASE_SNOOZE) {
            if (now >= snoozeUntil) {
                ringAgain();
                return;
            }
        }
        WatchUi.requestUpdate();
    }

    // ---------------------------------------------------------------- alarm

    private function ring(kind as Number, text as String) as Void {
        var now = TimeUtil.nowSec();
        _timer.stop();
        phase = PHASE_ALARM;
        alarmAt = now;
        ringAt = now;
        reasonKind = kind;
        reasonText = text;
        log(now, text);

        // The alarm itself comes first: nothing after it (report, learning, storage)
        // may keep it from ringing.
        player.start(_settings.vibeLevel, _settings.toneOn, 1);
        if (overlayOpen) {
            overlayOpen = false;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        WatchUi.switchToView(new AlarmView(self, player, false), new AlarmDelegate(self), WatchUi.SLIDE_IMMEDIATE);
        persist();

        // Then the morning report and the learning.
        var e = engine;
        engine = null;
        var status = LEARN_NONE;
        var r = (e != null) ? e.report(now, kind, text) : minimalReport(now, kind, text);
        if (e != null) {
            e.stop();
            // Learn this night's values right away (the morning answer follows later).
            status = getApp().model.learnNight(e.learningSummary(now, kind));
            r.put("ls", status);
            r.put("lk", now);
        }
        keepReport(r);

        // Night protocol last.
        NightLog.write("RING t=" + now + " kind=" + kind + " " + text);
        if (e != null) {
            e.writeLog();
            NightLog.write("LEARN status=" + status + " " + getApp().model.describe());
        }
    }

    private function ringAgain() as Void {
        var now = TimeUtil.nowSec();
        _timer.stop();
        phase = PHASE_ALARM;
        ringAt = now;
        log(now, "Alarm erneut");
        persist();
        player.start(_settings.vibeLevel, _settings.toneOn, 1);
        WatchUi.switchToView(new AlarmView(self, player, false), new AlarmDelegate(self), WatchUi.SLIDE_IMMEDIATE);
    }

    // Show the night screen for 20 seconds, afterwards it goes black.
    function showScreen() as Void {
        screenUntil = System.getTimer() + 20000;
        WatchUi.requestUpdate();
    }

    function canSnooze() as Boolean {
        return _settings.snoozeOn && snoozeCount < _settings.snoozeMax;
    }

    function snoozeMinutes() as Number {
        return _settings.snoozeMin;
    }

    function snoozeMaxCount() as Number {
        return _settings.snoozeMax;
    }

    function snooze() as Void {
        if (phase != PHASE_ALARM || !canSnooze()) {
            return;
        }
        var now = TimeUtil.nowSec();
        player.stop();
        snoozeCount += 1;
        phase = PHASE_SNOOZE;
        snoozeUntil = now + _settings.snoozeMin * 60;
        log(now, "Schlummern bis " + TimeUtil.fmtClock(snoozeUntil));
        NightLog.write("SNOOZE t=" + now + " n=" + snoozeCount);
        persist();
        _timer.stop();
        _timer.start(method(:onTick), 1000, true);
        WatchUi.switchToView(new SnoozeView(self), new SnoozeDelegate(self), WatchUi.SLIDE_DOWN);
    }

    function dismiss() as Void {
        var now = TimeUtil.nowSec();
        player.stop();
        _timer.stop();
        log(now, "Wecker aus");
        NightLog.write("OFF t=" + now + " snoozes=" + snoozeCount);
        var r = finishReport(now);
        Application.Storage.deleteValue("session");
        getApp().session = null;
        // Ask how the wake-up felt; the answer feeds the learning (see FeedbackView).
        var v = new FeedbackView();
        WatchUi.switchToView(v, new FeedbackDelegate(v, r, snoozeCount), WatchUi.SLIDE_UP);
    }

    // The user ends the night early from the night screen.
    function cancel() as Void {
        var now = TimeUtil.nowSec();
        _timer.stop();
        player.stop();
        var e = engine;
        NightLog.write("CANCEL t=" + now);
        if (e != null) {
            if (now - start >= 1800) {
                log(now, "Selbst beendet");
                keepReport(e.report(now, REASON_CANCEL, "Selbst beendet"));
                finishReport(now);
                e.writeLog();
            }
            e.stop();
            engine = null;
        }
        Application.Storage.deleteValue("session");
        getApp().session = null;
        var home = new HomeView();
        WatchUi.switchToView(home, new HomeDelegate(home), WatchUi.SLIDE_DOWN);
    }

    // The app closes (also when the watch closes it, e.g. for Garmin's morning report):
    // stop the hardware, keep the stored state for a restart. The night protocol notes
    // when this happened and keeps the minutes measured so far, which would be lost otherwise.
    function shutdown() as Void {
        _timer.stop();
        player.stop();
        NightLog.write("STOP t=" + TimeUtil.nowSec() + " ph=" + phase);
        var e = engine;
        if (e != null) {
            e.stop();
            e.writeLog();
        }
    }

    function minutesEarly() as Number {
        var d = (deadline - alarmAt) / 60;
        return (d > 0) ? d : 0;
    }

    // --------------------------------------------------------------- storage

    // Storage errors (watch storage full) must never stop the night or the alarm,
    // so they are caught: then only the restart after closing the app is lost.
    private function persist() as Void {
        try {
            Application.Storage.setValue("session", {
                "ph" => phase,
                "st" => start,
                "ws" => windowStart,
                "dl" => deadline,
                "aa" => alarmAt,
                "ra" => ringAt,
                "rn" => restarts,
                "su" => snoozeUntil,
                "sc" => snoozeCount,
                "rk" => reasonKind,
                "rs" => reasonText,
                "ev" => _events
            });
        } catch (ex) {
        }
    }

    private function keepReport(r as Dictionary) as Void {
        if (restarts > 0) {
            r.put("rst", restarts);   // the report then says that the night was interrupted
        }
        _report = r;
        storeReport(r);
    }

    private function finishReport(now as Number) as Dictionary {
        var r = _report;
        if (r == null) {
            r = minimalReport(now, reasonKind, reasonText);
        }
        r.put("off", now);
        r.put("sn", snoozeCount);
        r.put("ev", _events);
        storeReport(r);
        return r;
    }

    private function storeReport(r as Dictionary) as Void {
        try {
            Application.Storage.setValue("lastNight", r);
        } catch (e) {
            // Too big: keep the summary without the per-minute stages.
            r.put("S", [] as Array<Number>);
            try {
                Application.Storage.setValue("lastNight", r);
            } catch (e2) {
            }
        }
    }

    // Only a report of this night: if saving it failed, the stored one is still last night's.
    private function loadReport() as Void {
        var r = Application.Storage.getValue("lastNight");
        if (r instanceof Dictionary && num(r, "wu") >= start) {
            _report = r;
        }
    }

    private function minimalReport(now as Number, kind as Number, text as String) as Dictionary {
        return {
            "v" => 1,
            "st" => start,
            "on" => start,
            "wu" => now,
            "dl" => deadline,
            "ws" => windowStart,
            "rk" => kind,
            "rs" => text,
            "sl" => now - start,
            "pc" => [0, 0, 0],
            "mv" => 0,
            "S" => [] as Array<Number>
        };
    }

    private function log(sec as Number, text as String) as Void {
        _events.add(TimeUtil.fmtClock(sec) + "  " + text);
        if (_events.size() > 20) {
            _events = _events.slice(1, null) as Array<String>;
        }
    }

    private function num(d as Dictionary, key as String) as Number {
        var v = d.get(key);
        return (v instanceof Number) ? v : 0;
    }
}

// Picks up a stored night when the app starts. Returns null if there is none.
function resumeNightSession(settings as AppSettings) as NightSession or Null {
    var d = Application.Storage.getValue("session");
    if (!(d instanceof Dictionary)) {
        return null;
    }
    var s = new NightSession(settings);
    if (s.restore(d, TimeUtil.nowSec())) {
        return s;
    }
    Application.Storage.deleteValue("session");
    return null;
}
