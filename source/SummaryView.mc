import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Morning report with four pages: overview, sleep chart, measurements, timeline.
class SummaryView extends WatchUi.View {

    var page as Number = 0;
    var fromAlarm as Boolean;

    private var _r as Dictionary;

    function initialize(report as Dictionary, afterAlarm as Boolean) {
        View.initialize();
        _r = report;
        fromAlarm = afterAlarm;
    }

    function pageCount() as Number {
        return 4;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        if (page == 0) {
            drawOverview(dc);
        } else if (page == 1) {
            drawChart(dc);
        } else if (page == 2) {
            drawStats(dc);
        } else {
            drawTimeline(dc);
        }
        Ui.pageDots(dc, pageCount(), page);
    }

    // ------------------------------------------------------------- pages

    private function drawOverview(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var wake = num("wu");
        var deadline = num("dl");

        Ui.title(dc, cx, cy - 128, fromAlarm ? "Guten Morgen" : "Letzte Nacht", Ui.SUB);
        Ui.text(dc, cx, cy - 70, Graphics.FONT_NUMBER_HOT, (wake > 0) ? TimeUtil.fmtClock(wake) : "--:--", Ui.FG);

        var titles = ["Pünktlich geweckt", "Bewegung erkannt", "Leichtschlaf erkannt", "Du warst schon wach", "Leichte Phase am Ende", "Selbst beendet"];
        var kind = num("rk");
        var title = (kind >= 0 && kind < titles.size()) ? titles[kind] : "";
        Ui.text(dc, cx, cy - 2, Graphics.FONT_TINY, title, Ui.ACCENT);

        var early = (deadline - wake) / 60;
        var line = (early > 0) ? early.format("%d") + " min vor " + TimeUtil.fmtClock(deadline) : "Weckzeit " + TimeUtil.fmtClock(deadline);
        Ui.text(dc, cx, cy + 32, Graphics.FONT_XTINY, line, Ui.SUB);

        var hrMin = num("hrM");
        var bbVal = _r.get("bb");
        var bb = (bbVal instanceof Number) ? ((bbVal >= 0) ? "+" : "") + bbVal.format("%d") : "-";
        var sleep = num("sl");
        tile(dc, cx - 104, cy + 92, "Schlaf", (sleep / 3600).format("%d") + ":" + ((sleep / 60) % 60).format("%02d"));
        tile(dc, cx, cy + 92, "Puls min", (hrMin > 0) ? hrMin.format("%d") : "-");
        tile(dc, cx + 104, cy + 92, "Battery", bb);
    }

    private function drawChart(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.title(dc, cx, cy - 128, "Schlafverlauf", Ui.SUB);
        var stages = arr("S");
        var n = stages.size();
        if (n < 5) {
            Ui.text(dc, cx, cy, Graphics.FONT_SMALL, "Zu wenig Daten", Ui.DIM);
            return;
        }
        var x0 = cx - 150;
        var cw = 300;
        var top = cy - 86;
        var rowH = 38;

        // wake window in the background
        var start = num("st");
        var winIdx = (num("ws") - start) / 60;
        if (winIdx >= 0 && winIdx < n) {
            var xa = x0 + winIdx * cw / n;
            dc.setColor(0x17132E, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(xa, top - 6, x0 + cw - xa, rowH * 3 + 12);
        }
        // guide lines
        dc.setColor(Ui.FAINT, Graphics.COLOR_TRANSPARENT);
        for (var row = 0; row < 3; row++) {
            dc.fillRectangle(x0, top + row * rowH + rowH / 2, cw, 1);
        }
        // one block per run of equal stages: awake on top, deep at the bottom,
        // minutes without data stay empty
        var stageColors = [Ui.DEEP, Ui.LIGHT, Ui.AWAKE];
        var i = 0;
        while (i < n) {
            var stage = stages[i];
            var j = i;
            while (j + 1 < n && stages[j + 1] == stage) {
                j++;
            }
            if (stage >= STAGE_DEEP && stage <= STAGE_WAKE) {
                var xa = x0 + i * cw / n;
                var xb = x0 + (j + 1) * cw / n;
                var width = (xb - xa < 2) ? 2 : xb - xa;
                dc.setColor(stageColors[stage], Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(xa, top + (2 - stage) * rowH + 5, width, rowH - 10, 4);
            }
            i = j + 1;
        }
        Ui.text(dc, x0 + 30, top + rowH * 3 + 22, Graphics.FONT_XTINY, TimeUtil.fmtClock(start), Ui.DIM);
        Ui.text(dc, x0 + cw - 30, top + rowH * 3 + 22, Graphics.FONT_XTINY, TimeUtil.fmtClock(num("wu")), Ui.DIM);

        // legend with shares
        var pc = arr("pc");
        var names = ["Tief", "Leicht", "Wach"];
        for (var k = 0; k < 3; k++) {
            var x = cx - 96 + k * 96;
            dc.setColor(stageColors[k], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, cy + 86, 6);
            Ui.label(dc, x, cy + 110, names[k], Ui.SUB);
            Ui.text(dc, x, cy + 138, Graphics.FONT_XTINY, (pc.size() == 3) ? pc[k].format("%d") + " %" : "-", Ui.FG);
        }

        // The stages are an estimate; say so, and say when data is missing.
        // (Room for about 16 characters at the round edge.)
        var note = "Phasen geschätzt";
        if (num("rst") > 0) {
            note = "Nach Neustart";            // the chart then starts at the restart
        } else if (num("nd") >= 5) {
            note = num("nd").format("%d") + " min ohne Puls";
        }
        Ui.text(dc, cx, cy + 172, Graphics.FONT_XTINY, note, Ui.DIM);
    }

    private function drawStats(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.title(dc, cx, cy - 128, "Messwerte", Ui.SUB);

        var labels = [] as Array<String>;
        var values = [] as Array<String>;
        addRow(labels, values, "Ø Puls", num("hrA"), " bpm");
        addRow(labels, values, "Min. Puls", num("hrM"), " bpm");
        addRow(labels, values, "HRV", num("rm"), " ms");
        var rr = num("rr");
        if (rr > 0) {
            labels.add("Atmung");
            values.add((rr / 10).format("%d") + "," + (rr % 10).format("%d") + " /min");
        }
        addRow(labels, values, "Stress Ø", num("sa"), "");
        labels.add("Bewegungen");
        values.add(num("mv").format("%d"));
        var onset = num("on");
        if (onset > 0) {
            labels.add("Eingeschlafen");
            values.add(TimeUtil.fmtClock(onset));
        }

        var count = (labels.size() < 7) ? labels.size() : 7;
        var y = cy - 94;
        for (var i = 0; i < count; i++) {
            dc.setColor(Ui.SUB, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 130, y, Graphics.FONT_XTINY, labels[i], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Ui.FG, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 130, y, Graphics.FONT_XTINY, values[i], Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            y += 34;
        }
    }

    // Events of the night: time on the left, text (up to two lines) on the right.
    // Shows as many of the newest entries as fit.
    private function drawTimeline(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.title(dc, cx, cy - 128, "Ablauf", Ui.SUB);
        var ev = _r.get("ev");
        if (!(ev instanceof Array) || ev.size() == 0) {
            Ui.text(dc, cx, cy, Graphics.FONT_SMALL, "Keine Einträge", Ui.DIM);
            return;
        }
        var times = [] as Array<String>;
        var bodies = [] as Array<String>;
        var heights = [] as Array<Number>;
        var lineH = dc.getFontHeight(Graphics.FONT_XTINY) + 4;
        var used = 0;
        for (var i = ev.size() - 1; i >= 0; i--) {
            var line = ev[i];
            if (!(line instanceof String) || line.length() < 8) {
                continue;
            }
            var body = Graphics.fitTextToArea(line.substring(7, line.length()), Graphics.FONT_XTINY, 250, lineH * 2 + 12, true);
            if (body == null) {
                continue;
            }
            var h = lineCount(body) * lineH + 8;
            if (used + h > 250) {
                break;
            }
            used += h;
            times.add(line.substring(0, 5));
            bodies.add(body);
            heights.add(h);
        }
        var y = cy - 100;
        for (var k = times.size() - 1; k >= 0; k--) {
            var newest = (k == 0);
            dc.setColor(newest ? Ui.ACCENT : Ui.DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 154, y, Graphics.FONT_XTINY, times[k], Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(newest ? Ui.FG : Ui.SUB, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 74, y, Graphics.FONT_XTINY, bodies[k], Graphics.TEXT_JUSTIFY_LEFT);
            y += heights[k];
        }
    }

    // ----------------------------------------------------------- helpers

    private function lineCount(s as String) as Number {
        var count = 1;
        var rest = s;
        var idx = rest.find("\n");
        while (idx != null) {
            count += 1;
            rest = rest.substring(idx + 1, rest.length());
            idx = rest.find("\n");
        }
        return count;
    }

    private function tile(dc as Dc, x as Number, y as Number, label as String, value as String) as Void {
        Ui.label(dc, x, y - 18, label, Ui.DIM);
        Ui.text(dc, x, y + 14, Graphics.FONT_TINY, value, Ui.FG);
    }

    private function addRow(labels as Array<String>, values as Array<String>, label as String, v as Number, unit as String) as Void {
        if (v > 0) {
            labels.add(label);
            values.add(v.format("%d") + unit);
        }
    }

    private function num(key as String) as Number {
        var v = _r.get(key);
        return (v instanceof Number) ? v : 0;
    }

    private function arr(key as String) as Array<Number> {
        var v = _r.get(key);
        if (v instanceof Array) {
            return v as Array<Number>;
        }
        return [] as Array<Number>;
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    private var _v as SummaryView;

    function initialize(view as SummaryView) {
        BehaviorDelegate.initialize();
        _v = view;
    }

    function onNextPage() as Boolean {
        _v.page = (_v.page + 1) % _v.pageCount();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _v.page = (_v.page + _v.pageCount() - 1) % _v.pageCount();
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        return onNextPage();
    }

    function onBack() as Boolean {
        if (_v.fromAlarm) {
            var home = new HomeView();
            WatchUi.switchToView(home, new HomeDelegate(home), WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }
}
