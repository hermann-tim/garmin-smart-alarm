import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Snooze countdown. START = get up (alarm off).
class SnoozeView extends WatchUi.View {

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
        var total = s.snoozeMinutes() * 60;
        var left = s.snoozeUntil - TimeUtil.nowSec();
        if (left < 0) {
            left = 0;
        }
        if (total < 1) {
            total = 1;
        }

        var r = cx - 50;
        Ui.ring(dc, cx, cy, r, 10, Ui.TRACK);
        var f = left.toFloat() / total;
        if (f > 0.004) {
            Ui.arc(dc, cx, cy, r, 10, Ui.ACCENT, 90, 90 - 359.0 * f);
        }

        Ui.moon(dc, cx, cy - 104, 14, Ui.ACCENT);
        Ui.title(dc, cx, cy - 60, "Schlummern " + s.snoozeCount.format("%d") + "/" + s.snoozeMaxCount().format("%d"), Ui.SUB);
        Ui.text(dc, cx, cy + 4, Graphics.FONT_NUMBER_HOT, (left / 60).format("%d") + ":" + (left % 60).format("%02d"), Ui.FG);
        Ui.text(dc, cx, cy + 74, Graphics.FONT_XTINY, "Alarm um " + TimeUtil.fmtClock(s.snoozeUntil), Ui.SUB);

        Ui.buttonHint(dc, Ui.ANGLE_START, "AUFSTEHEN", Ui.SUN);
    }
}

class SnoozeDelegate extends WatchUi.BehaviorDelegate {

    private var _s as NightSession;

    function initialize(session as NightSession) {
        BehaviorDelegate.initialize();
        _s = session;
    }

    // Only the real START button ends snoozing (see AlarmDelegate for why
    // behaviors are passed on). Everything else is swallowed.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _s.dismiss();
        }
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    function onHold(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSelect() as Boolean {
        return false;
    }

    function onBack() as Boolean {
        return false;
    }

    function onMenu() as Boolean {
        return false;
    }

    function onNextPage() as Boolean {
        return false;
    }

    function onPreviousPage() as Boolean {
        return false;
    }
}
