import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Colors and drawing helpers for a clean, dark look (AMOLED friendly: black = pixels off).
module Ui {

    const BG = 0x000000;
    const FG = 0xFFFFFF;
    const SUB = 0x9C9CB4;
    const DIM = 0x5A5A70;
    const FAINT = 0x2A2A38;
    const TRACK = 0x1C1C28;
    const ACCENT = 0x8F7BFF;      // violet
    const ACCENT_DIM = 0x3E3478;
    const SUN = 0xFFA94D;         // sunrise orange
    const SUN_DIM = 0x6B4518;
    const DEEP = 0x5B4BD6;
    const LIGHT = 0xB9AEFF;
    const AWAKE = 0xFFA94D;
    const WARN = 0xFF6B6B;

    // Night screen: very dim so it does not wake you up
    const NIGHT_TEXT = 0x6E6E86;
    const NIGHT_SUB = 0x4A4A5E;
    const NIGHT_FAINT = 0x2C2C3A;

    // Button positions on the Forerunner 265 (degrees, counter-clockwise from 3 o'clock)
    const ANGLE_START = 38;
    const ANGLE_BACK = 322;
    const ANGLE_UP = 180;
    const ANGLE_DOWN = 222;

    var _hintFont as Graphics.VectorFont or Null = null;
    var _hintTried as Boolean = false;
    var _titleFont as Graphics.VectorFont or Null = null;
    var _labelFont as Graphics.VectorFont or Null = null;
    var _fontsTried as Boolean = false;

    function loadFonts() as Void {
        if (!_fontsTried) {
            _fontsTried = true;
            if (Graphics has :getVectorFont) {
                _titleFont = Graphics.getVectorFont({:face => ["RobotoCondensedBold", "RobotoRegular"], :size => 28});
                _labelFont = Graphics.getVectorFont({:face => ["RobotoCondensedBold", "RobotoRegular"], :size => 23});
            }
        }
    }

    // Small uppercase heading in a narrow font, e.g. "WECKFENSTER".
    function title(dc as Dc, x as Numeric, y as Numeric, s as String, color as Number) as Void {
        loadFonts();
        var f = _titleFont;
        text(dc, x, y, (f != null) ? f : Graphics.FONT_XTINY, s.toUpper(), color);
    }

    // Even smaller uppercase label, e.g. above a value.
    function label(dc as Dc, x as Numeric, y as Numeric, s as String, color as Number) as Void {
        loadFonts();
        var f = _labelFont;
        text(dc, x, y, (f != null) ? f : Graphics.FONT_XTINY, s.toUpper(), color);
    }

    function clear(dc as Dc) as Void {
        dc.setColor(BG, BG);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
    }

    function jc() as Number {
        return Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    }

    function text(dc as Dc, x as Numeric, y as Numeric, font as Graphics.FontType, s as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, s, jc());
    }

    function norm(deg as Numeric) as Number {
        var d = deg.toNumber() % 360;
        if (d < 0) {
            d += 360;
        }
        return d;
    }

    function polar(cx as Numeric, cy as Numeric, r as Numeric, deg as Numeric) as Array<Float> {
        var rad = deg.toFloat() * Math.PI / 180.0;
        return [(cx + r * Math.cos(rad)).toFloat(), (cy - r * Math.sin(rad)).toFloat()];
    }

    // Arc with round ends, drawn clockwise from startDeg to endDeg.
    function arc(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, width as Number, color as Number, startDeg as Numeric, endDeg as Numeric) as Void {
        var s = norm(startDeg);
        var e = norm(endDeg);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(width);
        if (s != e) {
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, s, e);
        }
        dc.setPenWidth(1);
        var p1 = polar(cx, cy, r, s);
        var p2 = polar(cx, cy, r, e);
        dc.fillCircle(p1[0], p1[1], width / 2);
        dc.fillCircle(p2[0], p2[1], width / 2);
    }

    function ring(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, width as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(width);
        dc.drawCircle(cx, cy, r);
        dc.setPenWidth(1);
    }

    // 12-hour dial: minute of the day -> angle (12 o'clock = 90 degrees)
    function clockAngle(minuteOfDay as Number) as Number {
        var m = minuteOfDay % 720;
        if (m < 0) {
            m += 720;
        }
        return norm(90 - m / 2);
    }

    function hintFont() as Graphics.VectorFont or Null {
        if (!_hintTried) {
            _hintTried = true;
            if (Graphics has :getVectorFont) {
                _hintFont = Graphics.getVectorFont({:face => ["RobotoCondensedBold", "RobotoRegular"], :size => 26});
            }
        }
        return _hintFont;
    }

    // Marks a physical button at the edge and writes its label along the edge.
    function buttonHint(dc as Dc, angle as Number, label as String, color as Number) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        arc(dc, cx, cy, cx - 5, 6, color, angle + 8, angle - 8);
        var f = hintFont();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (f != null && (dc has :drawRadialText)) {
            // Clockwise text grows outwards from its radius, counter-clockwise text inwards.
            if (angle > 0 && angle < 180) {
                dc.drawRadialText(cx, cy, f, label, Graphics.TEXT_JUSTIFY_CENTER, angle, cx - 32, Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
            } else {
                dc.drawRadialText(cx, cy, f, label, Graphics.TEXT_JUSTIFY_CENTER, angle, cx - 14, Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE);
            }
        } else {
            var p = polar(cx, cy, cx - 40, angle);
            dc.drawText(p[0], p[1], Graphics.FONT_XTINY, label, jc());
        }
    }

    // Small "+" / "-" hints next to the UP and DOWN buttons.
    function stepHints(dc as Dc, upLabel as String, downLabel as String, color as Number) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        arc(dc, cx, cy, cx - 5, 6, color, ANGLE_UP + 6, ANGLE_UP - 6);
        arc(dc, cx, cy, cx - 5, 6, color, ANGLE_DOWN + 6, ANGLE_DOWN - 6);
        var p = polar(cx, cy, cx - 34, ANGLE_UP);
        chevron(dc, p[0], p[1] - 14, 9, true, color);
        text(dc, p[0], p[1] + 12, Graphics.FONT_XTINY, upLabel, color);
        p = polar(cx, cy, cx - 34, ANGLE_DOWN);
        chevron(dc, p[0] + 4, p[1] - 14, 9, false, color);
        text(dc, p[0] + 4, p[1] + 12, Graphics.FONT_XTINY, downLabel, color);
    }

    function chevron(dc as Dc, x as Numeric, y as Numeric, size as Numeric, up as Boolean, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var h = size * 0.6;
        if (up) {
            dc.fillPolygon([[x - size, y + h], [x + size, y + h], [x, y - h]]);
        } else {
            dc.fillPolygon([[x - size, y - h], [x + size, y - h], [x, y + h]]);
        }
    }

    // Rounded label ("pill")
    function pill(dc as Dc, cx as Numeric, cy as Numeric, label as String, fg as Number, bg as Number) as Void {
        var font = Graphics.FONT_XTINY;
        var w = dc.getTextWidthInPixels(label, font) + 28;
        var h = 34;
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - w / 2, cy - h / 2, w, h, h / 2);
        text(dc, cx, cy, font, label, fg);
    }

    // Crescent moon icon
    function moon(dc as Dc, x as Numeric, y as Numeric, r as Numeric, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r * 0.5, y - r * 0.35, r * 0.85);
    }

    // Page dots at the right edge
    function pageDots(dc as Dc, count as Number, current as Number) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var step = 7;
        var first = (count - 1) * step / 2;
        for (var i = 0; i < count; i++) {
            var p = polar(cx, cy, cx - 16, first - i * step);
            dc.setColor((i == current) ? FG : DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(p[0], p[1], (i == current) ? 6 : 4);
        }
    }
}
