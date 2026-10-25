import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Wake-up screen with a pulsing "sunrise". START = off, BACK = snooze.
class AlarmView extends WatchUi.View {

    private var _s as NightSession or Null;
    private var _p as AlarmPlayer;
    private var _test as Boolean;

    function initialize(session as NightSession or Null, player as AlarmPlayer, test as Boolean) {
        View.initialize();
        _s = session;
        _p = player;
        _test = test;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        // A soft glow in the middle and rings that grow outwards like a sunrise
        dc.setColor(0x140C04, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, cx * 0.78);
        var colors = [Ui.SUN, 0xC07A32, 0x7A4A1C, 0x3A2410];
        for (var i = 0; i < 3; i++) {
            var phase = ((_p.seconds + i * 2) % 6) / 6.0;
            var rr = cx * 0.80 + phase * cx * 0.18;
            Ui.ring(dc, cx, cy, rr, 3, colors[(phase * 3.99).toNumber()]);
        }

        Ui.title(dc, cx, cy - 104, _test ? "Test-Alarm" : "Guten Morgen", Ui.SUN);
        Ui.text(dc, cx, cy - 34, Graphics.FONT_NUMBER_HOT, TimeUtil.fmtClock(TimeUtil.nowSec()), Ui.FG);

        var line1 = "";
        var line2 = "";
        var canSnooze = false;
        var s = _s;
        if (_test) {
            line1 = "Stufe " + (_p.stage() + 1).format("%d") + " von 4";
            line2 = "Taste: Ende";
        } else if (s != null) {
            line1 = s.reasonText;
            var early = s.minutesEarly();
            if (early > 0) {
                line2 = early.format("%d") + " min vor " + TimeUtil.fmtClock(s.deadline);
            }
            canSnooze = s.canSnooze();
        }
        drawWrapped(dc, cx, cy + 50, line1, Ui.SUB);
        Ui.text(dc, cx, cy + 104, Graphics.FONT_XTINY, line2, Ui.ACCENT);

        Ui.buttonHint(dc, Ui.ANGLE_START, "AUS", Ui.SUN);
        if (canSnooze) {
            Ui.buttonHint(dc, Ui.ANGLE_BACK, "SCHLUMMERN", Ui.ACCENT);
        }
    }

    private function drawWrapped(dc as Dc, cx as Number, y as Number, s as String, color as Number) as Void {
        var fitted = Graphics.fitTextToArea(s, Graphics.FONT_XTINY, 270, dc.getFontHeight(Graphics.FONT_XTINY) * 2 + 20, true);
        if (fitted != null) {
            Ui.text(dc, cx, y, Graphics.FONT_XTINY, fitted, color);
        }
    }
}

// Night alarm: START switches off, every other button snoozes. Touch is ignored.
//
// The watch first reports a "behavior" (select, back, next page ...) and only
// if that is not handled the raw key or tap. Taps and swipes also arrive as
// behaviors. So all behaviors are passed on (return false) and the decision is
// made on the raw key, which only real buttons produce.
class AlarmDelegate extends WatchUi.BehaviorDelegate {

    private var _s as NightSession;

    function initialize(session as NightSession) {
        BehaviorDelegate.initialize();
        _s = session;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _s.dismiss();
        } else {
            _s.snooze();
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

// Test alarm from the settings: any button or tap ends it.
class TestAlarmDelegate extends WatchUi.BehaviorDelegate {

    private var _p as AlarmPlayer;

    function initialize(player as AlarmPlayer) {
        BehaviorDelegate.initialize();
        _p = player;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        return finish();
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return finish();
    }

    function onBack() as Boolean {
        return finish();
    }

    private function finish() as Boolean {
        if (_p.running || _p.seconds > 0) {
            _p.stop();
            _p.seconds = 0;
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }
}
