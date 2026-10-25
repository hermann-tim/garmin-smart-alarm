import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Simple yes/no question. START = yes, BACK = no.
class ConfirmView extends WatchUi.View {

    private var _title as String;
    private var _sub as String;
    private var _yes as String;
    private var _no as String;

    function initialize(title as String, sub as String, yes as String, no as String) {
        View.initialize();
        _title = title;
        _sub = sub;
        _yes = yes;
        _no = no;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.text(dc, cx, cy - 34, Graphics.FONT_MEDIUM, _title, Ui.FG);
        var sub = Graphics.fitTextToArea(_sub, Graphics.FONT_XTINY, 280, dc.getFontHeight(Graphics.FONT_XTINY) * 2 + 20, true);
        if (sub != null) {
            Ui.text(dc, cx, cy + 34, Graphics.FONT_XTINY, sub, Ui.SUB);
        }
        Ui.buttonHint(dc, Ui.ANGLE_START, _yes, Ui.WARN);
        Ui.buttonHint(dc, Ui.ANGLE_BACK, _no, Ui.ACCENT);
    }
}

class ConfirmDelegate extends WatchUi.BehaviorDelegate {

    private var _answer as Method;

    // answer: function(yes as Boolean) as Void
    function initialize(answer as Method) {
        BehaviorDelegate.initialize();
        _answer = answer;
    }

    // Only the real START button says yes. A tap also arrives as "select",
    // so select is passed on and taps are ignored below.
    function onSelect() as Boolean {
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _answer.invoke(true);
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        _answer.invoke(false);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onMenu() as Boolean {
        return true;
    }
}
