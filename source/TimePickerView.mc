import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Time picker: first the hour, then the minutes (5 minute steps).
class TimePickerView extends WatchUi.View {

    var hour as Number;
    var minute as Number;
    var field as Number = 0;   // 0 = hour, 1 = minutes

    private var _title as String;

    function initialize(title as String, minutes as Number) {
        View.initialize();
        _title = title;
        var m = TimeUtil.wrapMin(minutes);
        hour = m / 60;
        minute = ((m % 60) / 5) * 5;
    }

    function minutes() as Number {
        return hour * 60 + minute;
    }

    function change(dir as Number) as Void {
        if (field == 0) {
            hour = (hour + dir + 24) % 24;
        } else {
            minute = (minute + dir * 5 + 60) % 60;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var font = Graphics.FONT_NUMBER_THAI_HOT;
        var hs = hour.format("%02d");
        var ms = minute.format("%02d");
        var wh = dc.getTextWidthInPixels(hs, font);
        var wc = dc.getTextWidthInPixels(":", font);
        var wm = dc.getTextWidthInPixels(ms, font);
        var x = cx - (wh + wc + wm) / 2;
        var y = cy - 4;
        var hx = x + wh / 2;
        var mx = x + wh + wc + wm / 2;

        Ui.title(dc, cx, cy - 128, _title, Ui.SUB);
        Ui.text(dc, hx, y, font, hs, (field == 0) ? Ui.FG : Ui.DIM);
        Ui.text(dc, x + wh + wc / 2, y, font, ":", Ui.DIM);
        Ui.text(dc, mx, y, font, ms, (field == 1) ? Ui.FG : Ui.DIM);

        var fx = (field == 0) ? hx : mx;
        var fw = (field == 0) ? wh : wm;
        dc.setColor(Ui.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(fx - fw / 2, y + 56, fw, 6, 3);
        Ui.chevron(dc, fx, y - 80, 14, true, Ui.ACCENT);
        Ui.chevron(dc, fx, y + 88, 14, false, Ui.ACCENT);

        Ui.text(dc, cx, cy + 128, Graphics.FONT_XTINY, (field == 0) ? "Stunde" : "Minute", Ui.SUB);
        Ui.buttonHint(dc, Ui.ANGLE_START, (field == 0) ? "WEITER" : "OK", Ui.ACCENT);
    }
}

class TimePickerDelegate extends WatchUi.BehaviorDelegate {

    private var _v as TimePickerView;
    private var _key as Object;
    private var _done as Method;

    // done: function(key as Object, minutes as Number) as Void
    function initialize(view as TimePickerView, key as Object, done as Method) {
        BehaviorDelegate.initialize();
        _v = view;
        _key = key;
        _done = done;
    }

    function onPreviousPage() as Boolean {
        _v.change(1);
        return true;
    }

    function onNextPage() as Boolean {
        _v.change(-1);
        return true;
    }

    // A tap also arrives as "select": pass it on, START is handled in onKey.
    function onSelect() as Boolean {
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() != WatchUi.KEY_ENTER) {
            return false;
        }
        if (_v.field == 0) {
            _v.field = 1;
            WatchUi.requestUpdate();
        } else {
            _done.invoke(_key, _v.minutes());
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    function onBack() as Boolean {
        if (_v.field == 1) {
            _v.field = 0;
            WatchUi.requestUpdate();
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    // Touch: tap a number to select it, tap above/below it to change it.
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        var ds = System.getDeviceSettings();
        var cx = ds.screenWidth / 2;
        var cy = ds.screenHeight / 2;
        var tapped = (c[0] < cx) ? 0 : 1;
        if (tapped != _v.field) {
            _v.field = tapped;
            WatchUi.requestUpdate();
        } else if (c[1] < cy - 50) {
            _v.change(1);
        } else if (c[1] > cy + 50) {
            _v.change(-1);
        }
        return true;
    }
}
