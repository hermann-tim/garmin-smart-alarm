import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Night screen: very dim. Shows the time, the wake time and a ring from
// "start" (top) clockwise to the wake time, with the wake window in orange.
class NightView extends WatchUi.View {

    private var _s as NightSession;

    function initialize(session as NightSession) {
        View.initialize();
        _s = session;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var s = _s;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var now = TimeUtil.nowSec();
        var total = s.deadline - s.start;
        if (total < 60) {
            total = 60;
        }

        var r = cx - 8;
        Ui.ring(dc, cx, cy, r, 3, Ui.NIGHT_FAINT);
        if (s.windowStart > s.start) {
            Ui.arc(dc, cx, cy, r, 6, Ui.SUN_DIM, 90 - 360.0 * (s.windowStart - s.start) / total, 91);
        }
        var progress = (now - s.start).toFloat() / total;
        if (progress > 1.0) {
            progress = 1.0;
        }
        if (progress > 0.004) {
            Ui.arc(dc, cx, cy, r, 6, Ui.ACCENT_DIM, 90, 90 - 359.0 * progress);
        }

        Ui.moon(dc, cx, cy - 112, 16, Ui.ACCENT_DIM);
        Ui.text(dc, cx, cy - 42, Graphics.FONT_NUMBER_MEDIUM, TimeUtil.fmtClock(now), Ui.NIGHT_TEXT);
        Ui.text(dc, cx, cy + 28, Graphics.FONT_SMALL, "Wecker " + TimeUtil.fmtClock(s.deadline), Ui.NIGHT_TEXT);

        if (now >= s.windowStart) {
            Ui.text(dc, cx, cy + 70, Graphics.FONT_XTINY, "Weckfenster aktiv", Ui.SUN_DIM);
        } else {
            Ui.text(dc, cx, cy + 70, Graphics.FONT_XTINY, "Fenster ab " + TimeUtil.fmtClock(s.windowStart), Ui.NIGHT_SUB);
        }

        var e = s.engine;
        if (e != null) {
            var status = e.stageLabel();
            if (e.hrNow > 0) {
                status += "  ·  " + e.hrNow.format("%d") + " bpm";
            }
            Ui.text(dc, cx, cy + 104, Graphics.FONT_XTINY, status, Ui.NIGHT_SUB);
        }
        Ui.text(dc, cx, cy + 146, Graphics.FONT_XTINY, "BACK: beenden", Ui.NIGHT_FAINT);
    }
}

class NightDelegate extends WatchUi.BehaviorDelegate {

    private var _s as NightSession;

    function initialize(session as NightSession) {
        BehaviorDelegate.initialize();
        _s = session;
    }

    // BACK asks before the night is ended.
    function onBack() as Boolean {
        _s.overlayOpen = true;
        var v = new ConfirmView("Wecker beenden?", "Die Messung dieser Nacht stoppt.", "BEENDEN", "WEITER");
        WatchUi.pushView(v, new ConfirmDelegate(method(:onAnswer)), WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function onAnswer(yes as Boolean) as Void {
        _s.overlayOpen = false;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (yes) {
            _s.cancel();
        }
    }

    // Everything else is ignored, so nothing happens by accident at night.
    function onSelect() as Boolean {
        return true;
    }

    function onMenu() as Boolean {
        return true;
    }

    function onNextPage() as Boolean {
        return true;
    }

    function onPreviousPage() as Boolean {
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }
}
