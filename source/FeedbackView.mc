import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Morning question right after the alarm: "How do you feel?" fit / okay / tired.
// The answer teaches SmartWake which wake-up moments suit you.
class FeedbackView extends WatchUi.View {

    var selected as Number = 1;   // 0 = fit, 1 = okay, 2 = tired

    function initialize() {
        View.initialize();
    }

    function move(dir as Number) as Void {
        selected += dir;
        if (selected < 0) {
            selected = 0;
        } else if (selected > 2) {
            selected = 2;
        }
        WatchUi.requestUpdate();
    }

    // FEEL_* value of the selected row
    function feel() as Number {
        return 2 - selected;
    }

    // Row index for a touch position, -1 = no row
    function rowAt(y as Number) as Number {
        var cy = System.getDeviceSettings().screenHeight / 2;
        for (var i = 0; i < 3; i++) {
            var ry = rowY(cy, i);
            if (y > ry - 30 && y < ry + 30) {
                return i;
            }
        }
        return -1;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.title(dc, cx, cy - 128, "Guten Morgen", Ui.SUN);
        Ui.text(dc, cx, cy - 84, Graphics.FONT_TINY, "Wie fühlst du dich?", Ui.FG);

        var labels = ["Fit", "Okay", "Müde"];
        for (var i = 0; i < 3; i++) {
            var y = rowY(cy, i);
            var active = (i == selected);
            if (active) {
                dc.setColor(Ui.ACCENT_DIM, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(cx - 118, y - 27, 236, 54, 27);
            }
            var color = active ? Ui.FG : Ui.SUB;
            Ui.face(dc, cx - 70, y, 17, 2 - i, active ? Ui.FG : Ui.DIM);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 38, y, Graphics.FONT_SMALL, labels[i], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Ui.buttonHint(dc, Ui.ANGLE_START, "OK", Ui.ACCENT);
        Ui.buttonHint(dc, Ui.ANGLE_BACK, "SPÄTER", Ui.DIM);
    }

    private function rowY(cy as Number, i as Number) as Number {
        return cy - 20 + i * 62;
    }
}

class FeedbackDelegate extends WatchUi.BehaviorDelegate {

    private var _v as FeedbackView;
    private var _report as Dictionary;
    private var _snoozes as Number;
    private var _done as Boolean = false;

    function initialize(view as FeedbackView, report as Dictionary, snoozes as Number) {
        BehaviorDelegate.initialize();
        _v = view;
        _report = report;
        _snoozes = snoozes;
    }

    function onPreviousPage() as Boolean {
        _v.move(-1);
        return true;
    }

    function onNextPage() as Boolean {
        _v.move(1);
        return true;
    }

    // Taps also arrive as "select": pass them on to onTap, START is handled in onKey.
    function onSelect() as Boolean {
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            answer(_v.feel());
            return true;
        }
        return false;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var row = _v.rowAt(evt.getCoordinates()[1]);
        if (row >= 0) {
            _v.selected = row;
            answer(_v.feel());
        }
        return true;
    }

    // BACK: answer later (no answer)
    function onBack() as Boolean {
        answer(-1);
        return true;
    }

    private function answer(feel as Number) as Void {
        if (!_done) {
            _done = true;
            finishMorning(_report, feel, _snoozes);
        }
    }
}

// Applies the morning answer to the learning, notes it in the report and shows the report.
// feel = FEEL_* or -1 (no answer). Without an answer, snoozing twice or more counts as a hint.
function finishMorning(r as Dictionary, feel as Number, snoozes as Number) as Void {
    var model = getApp().model;
    var now = TimeUtil.nowSec();
    var ev = r.get("ev");
    var events = (ev instanceof Array) ? ev : [] as Array<String>;
    var stamp = TimeUtil.fmtClock(now) + "  ";

    if (feel >= 0) {
        r.put("fb", feel);
        events.add(stamp + "Gefühl: " + ["müde", "okay", "fit"][feel]);
    }
    var status = r.get("ls");
    var key = r.get("lk");
    if (status == LEARN_OK && key instanceof Number) {
        if (feel >= 0) {
            model.applyFeedback(key, feel, false);
        } else if (snoozes >= 2) {
            model.applyFeedback(key, FEEL_TIRED, true);
        }
        events.add(stamp + "Gelernt: Nacht " + model.storedNights().format("%d") + " von 21");
    } else if (status == LEARN_SHORT) {
        events.add(stamp + "Nicht gelernt: zu kurz");
    } else if (status == LEARN_OUTLIER) {
        events.add(stamp + "Nicht gelernt: ungewöhnliche Nacht");
    }
    NightLog.write("FEEL " + feel + " snoozes=" + snoozes + " status=" + status);
    NightLog.write("MODEL " + model.describe());
    r.put("ev", events);
    try {
        Application.Storage.setValue("lastNight", r);
    } catch (e) {
    }
    var v = new SummaryView(r, true);
    WatchUi.switchToView(v, new SummaryDelegate(v), WatchUi.SLIDE_LEFT);
}
