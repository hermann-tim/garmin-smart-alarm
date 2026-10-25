import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Start screen: tonight's wake time and window. START begins the night.
class HomeView extends WatchUi.View {

    var offsetMin as Number = 0;   // change for tonight only

    private var _timer as Timer.Timer or Null = null;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onRefresh), 30000, true);
        _timer = t;
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
    }

    function onRefresh() as Void {
        WatchUi.requestUpdate();
    }

    // Tonight's target: [deadlineSec, dayIndex, wakeMinutes, planMinutes]
    function target() as Array<Number> {
        var s = getApp().settings;
        var now = TimeUtil.nowSec();
        var next = TimeUtil.nextDeadline(s.plan, now);
        var planMin = s.plan[next[1]];
        var wake = planMin + offsetMin;
        if (wake < 0) {
            wake = 0;
        } else if (wake > 1435) {
            wake = 1435;
        }
        // The next time the clock shows this wake time: today if it is still ahead, otherwise tomorrow.
        var mid = TimeUtil.midnightOf(now);
        var dl = TimeUtil.atMinuteOfDay(mid, wake);
        if (dl <= now + 60) {
            dl = TimeUtil.atMinuteOfDay(TimeUtil.midnightOf(mid + 36 * 3600), wake);
        }
        return [dl, TimeUtil.weekdayIndex(dl), wake, planMin];
    }

    function changeBy(delta as Number) as Void {
        var t = target();
        var wake = t[2] + delta;
        if (wake < 0 || wake > 1435) {
            return;
        }
        offsetMin = wake - t[3];
        WatchUi.requestUpdate();
    }

    function setWake(minutes as Number) as Void {
        offsetMin = minutes - target()[3];
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var s = getApp().settings;
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var t = target();
        var wake = t[2];
        var winStart = wake - s.windowMin;

        if (offsetMin != 0) {
            Ui.pill(dc, cx, cy - 138, "NUR HEUTE", Ui.FG, Ui.ACCENT_DIM);
        } else {
            Ui.moon(dc, cx, cy - 136, 13, Ui.ACCENT);
        }
        Ui.title(dc, cx, cy - 100, TimeUtil.DAY_NAMES[t[1]], Ui.SUB);
        Ui.text(dc, cx, cy - 32, Graphics.FONT_NUMBER_THAI_HOT, TimeUtil.fmtHM(wake), Ui.FG);
        windowBar(dc, cx, cy + 40, winStart, wake);

        Ui.text(dc, cx, cy + 92, Graphics.FONT_XTINY, "in " + TimeUtil.fmtDur(t[0] - TimeUtil.nowSec()), Ui.SUB);

        var battery = System.getSystemStats().battery;
        if (battery < 25.0) {
            Ui.text(dc, cx, cy + 148, Graphics.FONT_XTINY, "Akku " + battery.format("%d") + " %, bitte laden", Ui.WARN);
        } else {
            Ui.text(dc, cx, cy + 148, Graphics.FONT_XTINY, "UP halten: Menü", Ui.DIM);
        }

        Ui.buttonHint(dc, Ui.ANGLE_START, "START", Ui.ACCENT);
        Ui.stepHints(dc, "+5", "-5", Ui.SUB);
    }

    // Small timeline of the wake window: "07:30 ———● 08:00"
    private function windowBar(dc as Dc, cx as Number, y as Number, from as Number, to as Number) as Void {
        var half = 62;
        dc.setColor(Ui.ACCENT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - half, y - 4, half * 2, 8, 4);
        dc.setColor(Ui.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - half, y, 6);
        dc.setColor(Ui.SUN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx + half, y, 8);
        dc.setColor(Ui.ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - half - 16, y, Graphics.FONT_XTINY, TimeUtil.fmtHM(from), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Ui.SUN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + half + 16, y, Graphics.FONT_XTINY, TimeUtil.fmtHM(to), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class HomeDelegate extends WatchUi.BehaviorDelegate {

    private var _view as HomeView;

    function initialize(view as HomeView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Taps also arrive as "select". Returning false lets the key or tap
    // handlers below decide, so only the real START button begins the night.
    function onSelect() as Boolean {
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            startNight();
            return true;
        }
        return false;
    }

    private function startNight() as Void {
        var app = getApp();
        var session = new NightSession(app.settings);
        app.session = session;
        session.begin(_view.target()[0]);
        WatchUi.switchToView(new NightView(session), new NightDelegate(session), WatchUi.SLIDE_UP);
    }

    function onPreviousPage() as Boolean {
        _view.changeBy(5);
        return true;
    }

    function onNextPage() as Boolean {
        _view.changeBy(-5);
        return true;
    }

    function onMenu() as Boolean {
        openSettings();
        return true;
    }

    // Touch: tap the time to pick it, tap the lower part for the menu.
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var y = evt.getCoordinates()[1];
        var h = System.getDeviceSettings().screenHeight;
        if (y > h * 0.78) {
            openSettings();
        } else if (y > h * 0.2 && y < h * 0.62) {
            var v = new TimePickerView("Heute Nacht", _view.target()[2]);
            WatchUi.pushView(v, new TimePickerDelegate(v, :tonight, method(:onTimePicked)), WatchUi.SLIDE_UP);
        }
        return true;
    }

    function onTimePicked(key as Object, minutes as Number) as Void {
        _view.setWake(minutes);
    }
}
