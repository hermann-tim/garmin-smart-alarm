import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// What SmartWake has learned about your sleep, on three pages:
// progress and morning answers, your values, and how much each signal counts.
class ProfileView extends WatchUi.View {

    var page as Number = 0;

    function initialize() {
        View.initialize();
    }

    function pageCount() as Number {
        return 3;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var m = getApp().model;
        if (page == 0) {
            drawProgress(dc, m);
        } else if (page == 1) {
            drawValues(dc, m);
        } else {
            drawWeights(dc, m);
        }
        Ui.pageDots(dc, pageCount(), page);
    }

    private function drawProgress(dc as Dc, m as SleepModel) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var n = m.storedNights();
        var r = cx - 36;
        Ui.ring(dc, cx, cy, r, 8, Ui.TRACK);
        if (n > 0) {
            Ui.arc(dc, cx, cy, r, 8, Ui.ACCENT, 90, 90 - 359.0 * n / 21);
        }
        Ui.title(dc, cx, cy - 116, "Schlafprofil", Ui.SUB);
        Ui.text(dc, cx, cy - 46, Graphics.FONT_NUMBER_HOT, n.format("%d"), Ui.FG);
        Ui.text(dc, cx, cy + 14, Graphics.FONT_XTINY, "von 21 Nächten", Ui.SUB);

        if (n == 0) {
            var hint = Graphics.fitTextToArea("Lernt ab der ersten Nacht mit 3 Stunden Schlaf.",
                Graphics.FONT_XTINY, 240, dc.getFontHeight(Graphics.FONT_XTINY) * 3 + 20, true);
            if (hint != null) {
                Ui.text(dc, cx, cy + 94, Graphics.FONT_XTINY, hint, Ui.DIM);
            }
            return;
        }
        // Morning answers: fit, okay, tired
        var counts = m.feelCounts();
        for (var i = 0; i < 3; i++) {
            var x = cx - 76 + i * 76;
            var mood = 2 - i;
            Ui.face(dc, x, cy + 66, 15, mood, Ui.SUB);
            Ui.text(dc, x, cy + 102, Graphics.FONT_XTINY, counts[mood].format("%d"), Ui.FG);
        }
    }

    private function drawValues(dc as Dc, m as SleepModel) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.title(dc, cx, cy - 130, "Deine Werte", Ui.SUB);

        var labels = ["Schlafzyklus", "Ruhepuls", "HRV", "Stress", "Atmung", "Puls leicht", "Schwelle", "Ø früher"];
        var values = [
            round(m.cycleMin).format("%d") + " min",
            (m.minHr > 0.0) ? round(m.minHr).format("%d") + " bpm" : "-",
            (m.rmssd > 0.0) ? round(m.rmssd).format("%d") + " ms" : "-",
            (m.stress >= 0.0) ? round(m.stress).format("%d") : "-",
            (m.resp > 0.0) ? tenths(m.resp) + " /min" : "-",
            "+" + tenths(m.lightHr) + " bpm",
            shiftText(m.shift),
            (m.avgEarlyMinutes() >= 0) ? m.avgEarlyMinutes().format("%d") + " min" : "-"
        ];
        var y = cy - 96;
        for (var i = 0; i < labels.size(); i++) {
            dc.setColor(Ui.SUB, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 132, y, Graphics.FONT_XTINY, labels[i], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Ui.FG, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 132, y, Graphics.FONT_XTINY, values[i], Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            y += 31;
        }
    }

    private function drawWeights(dc as Dc, m as SleepModel) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.title(dc, cx, cy - 130, "Gewichtung", Ui.SUB);
        var y = cy - 92;
        for (var k = 0; k < COMP_COUNT; k++) {
            var w = m.weights[k];
            Ui.labelAt(dc, cx - 142, y, signalName(k), Ui.SUB, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Ui.TRACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx - 30, y - 6, 100, 12, 6);
            var len = (w / 0.45 * 100.0).toNumber();
            if (len > 100) {
                len = 100;
            }
            if (len > 3) {
                dc.setColor(Ui.ACCENT, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(cx - 30, y - 6, len, 12, 6);
            }
            dc.setColor(Ui.FG, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 126, y, Graphics.FONT_XTINY, round(w * 100.0).format("%d") + "%",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            y += 31;
        }
    }

    private function shiftText(s as Float) as String {
        if (s > 0.9) {
            return "strenger +" + round(s).format("%d");
        }
        if (s < -0.9) {
            return "lockerer " + round(s).format("%d");
        }
        return "neutral";
    }

    private function round(v as Float) as Number {
        return (v < 0.0) ? (v - 0.5).toNumber() : (v + 0.5).toNumber();
    }

    // 13.84 -> "13,8"
    private function tenths(v as Float) as String {
        var t = round(v * 10.0);
        return (t / 10).format("%d") + "," + (t % 10).format("%d");
    }
}

class ProfileDelegate extends WatchUi.BehaviorDelegate {

    private var _v as ProfileView;

    function initialize(view as ProfileView) {
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
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
