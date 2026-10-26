import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Round slider for a number setting. UP/DOWN or dragging along the arc changes it,
// START saves, BACK cancels.
class SliderView extends WatchUi.View {

    var value as Number;

    private var _title as String;
    private var _min as Number;
    private var _max as Number;
    private var _step as Number;
    private var _unit as String;
    private var _labels as Array<String> or Null;
    private var _hint as String;

    // labels: optional names for each value (starting at min), shown under the number
    function initialize(title as String, min as Number, max as Number, step as Number, current as Number,
            unit as String, labels as Array<String> or Null, hint as String) {
        View.initialize();
        _title = title;
        _min = min;
        _max = max;
        _step = step;
        _unit = unit;
        _labels = labels;
        _hint = hint;
        value = clampValue(current);
    }

    function change(dir as Number) as Void {
        value = clampValue(value + dir * _step);
        WatchUi.requestUpdate();
    }

    // Touch: set the value from a point on the arc. Returns false if the point is not near the arc.
    function setFromPoint(x as Number, y as Number) as Boolean {
        var ds = System.getDeviceSettings();
        var cx = ds.screenWidth / 2;
        var cy = ds.screenHeight / 2;
        var dx = (x - cx).toFloat();
        var dy = (cy - y).toFloat();
        if (Math.sqrt(dx * dx + dy * dy) < cx * 0.55) {
            return false;
        }
        var deg = Math.atan2(dy, dx) * 180.0 / Math.PI;
        var along = 225.0 - deg;     // clockwise distance from the start of the arc
        while (along < 0.0) {
            along += 360.0;
        }
        while (along >= 360.0) {
            along -= 360.0;
        }
        // The gap at the bottom between both ends: a tap close to an end snaps to it,
        // a tap in the middle of the gap is ignored (no jump to min or max).
        if (along > 285.0 && along < 345.0) {
            return true;
        }
        if (along > 270.0) {
            along = (along < 315.0) ? 270.0 : 0.0;
        }
        var steps = (along / 270.0 * (_max - _min) / _step + 0.5).toNumber();
        value = clampValue(_min + steps * _step);
        WatchUi.requestUpdate();
        return true;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var r = cx - 52;
        var f = (_max > _min) ? (value - _min).toFloat() / (_max - _min) : 0.0;
        var end = 225.0 - 270.0 * f;

        Ui.arc(dc, cx, cy, r, 14, Ui.TRACK, 225, 315);
        if (f > 0.004) {
            Ui.arc(dc, cx, cy, r, 14, Ui.ACCENT, 225, end);
        }
        var knob = Ui.polar(cx, cy, r, end);
        dc.setColor(Ui.FG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(knob[0], knob[1], 16);
        dc.setColor(Ui.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(knob[0], knob[1], 7);

        Ui.title(dc, cx, cy - 92, _title, Ui.SUB);
        Ui.text(dc, cx, cy - 30, Graphics.FONT_NUMBER_HOT, value.format("%d"), Ui.FG);
        var labels = _labels;
        if (labels != null) {
            Ui.text(dc, cx, cy + 32, Graphics.FONT_TINY, labels[(value - _min) / _step], Ui.ACCENT);
        } else {
            Ui.text(dc, cx, cy + 32, Graphics.FONT_SMALL, _unit, Ui.SUB);
        }
        var fitted = Graphics.fitTextToArea(_hint, Graphics.FONT_XTINY, 200, 76, true);
        if (fitted != null) {
            Ui.text(dc, cx, cy + 94, Graphics.FONT_XTINY, fitted, Ui.DIM);
        }

        var pMin = Ui.polar(cx, cy, r, 225);
        var pMax = Ui.polar(cx, cy, r, 315);
        Ui.text(dc, pMin[0], pMin[1] + 32, Graphics.FONT_XTINY, _min.format("%d"), Ui.DIM);
        Ui.text(dc, pMax[0], pMax[1] + 32, Graphics.FONT_XTINY, _max.format("%d"), Ui.DIM);

        Ui.buttonHint(dc, Ui.ANGLE_START, "OK", Ui.ACCENT);
    }

    private function clampValue(v as Number) as Number {
        if (v < _min) {
            return _min;
        }
        return (v > _max) ? _max : v;
    }
}

class SliderDelegate extends WatchUi.BehaviorDelegate {

    private var _v as SliderView;
    private var _key as Object;
    private var _done as Method;
    private var _lastDrag as Number = -10000;

    // done: function(key as Object, value as Number) as Void
    function initialize(view as SliderView, key as Object, done as Method) {
        BehaviorDelegate.initialize();
        _v = view;
        _key = key;
        _done = done;
    }

    function onPreviousPage() as Boolean {
        if (!justDragged()) {
            _v.change(1);
        }
        return true;
    }

    function onNextPage() as Boolean {
        if (!justDragged()) {
            _v.change(-1);
        }
        return true;
    }

    // A tap also arrives as "select": pass it on so onTap gets the position.
    function onSelect() as Boolean {
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            save();
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        if (!justDragged()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    // Tap on the arc sets the value, tap in the middle saves.
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        if (!_v.setFromPoint(c[0], c[1])) {
            save();
        }
        return true;
    }

    function onDrag(evt as WatchUi.DragEvent) as Boolean {
        var c = evt.getCoordinates();
        if (_v.setFromPoint(c[0], c[1])) {
            _lastDrag = System.getTimer();
        }
        return true;
    }

    private function save() as Void {
        _done.invoke(_key, _v.value);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    // The end of a drag can look like a swipe; ignore swipes right after dragging.
    private function justDragged() as Boolean {
        return System.getTimer() - _lastDrag < 600;
    }
}
