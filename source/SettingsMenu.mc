import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Opens the settings menu (UP hold on the start screen).
function openSettings() as Void {
    var s = getApp().settings;
    var menu = new WatchUi.Menu2({:title => "Einstellungen", :theme => WatchUi.MENU_THEME_PURPLE});
    menu.addItem(new WatchUi.MenuItem("Wochenplan", s.planSummary(), :plan, null));
    menu.addItem(new WatchUi.MenuItem("Weckfenster", s.windowMin.format("%d") + " min vor der Weckzeit", :window, null));
    menu.addItem(new WatchUi.ToggleMenuItem("Schlummern", {:enabled => "An", :disabled => "Aus"}, :snooze, s.snoozeOn, null));
    menu.addItem(new WatchUi.MenuItem("Schlummerdauer", s.snoozeMin.format("%d") + " min", :snoozeMin, null));
    menu.addItem(new WatchUi.MenuItem("Max. Schlummern", s.snoozeMax.format("%d") + " mal", :snoozeMax, null));
    menu.addItem(new WatchUi.MenuItem("Vibration", s.vibeLabel(), :vibe, null));
    menu.addItem(new WatchUi.ToggleMenuItem("Ton", {:enabled => "An, ab 30 s Alarm", :disabled => "Aus, nur Vibration"}, :tone, s.toneOn, null));
    menu.addItem(new WatchUi.MenuItem("Empfindlichkeit", s.sensLabel(), :sens, null));
    menu.addItem(new WatchUi.MenuItem("Wecker testen", "Alarm jetzt ausprobieren", :test, null));
    menu.addItem(new WatchUi.MenuItem("Letzte Nacht", lastNightLabel(), :last, null));
    menu.addItem(new WatchUi.MenuItem("Schlafprofil", profileLabel(), :profile, null));
    menu.addItem(new WatchUi.MenuItem("Lernen zurücksetzen", "Profil löschen", :resetModel, null));
    menu.addItem(new WatchUi.MenuItem("So funktioniert's", null, :help, null));
    addDebugItems(menu);
    WatchUi.pushView(menu, new SettingsDelegate(menu), WatchUi.SLIDE_UP);
}

function profileLabel() as String {
    return getApp().model.storedNights().format("%d") + " von 21 Nächten gelernt";
}

function lastNightLabel() as String {
    var r = Application.Storage.getValue("lastNight");
    if (r instanceof Dictionary) {
        var wake = r.get("wu");
        if (wake instanceof Number) {
            return "Geweckt um " + TimeUtil.fmtClock(wake);
        }
    }
    return "Noch keine Daten";
}

class SettingsDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as WatchUi.Menu2;

    function initialize(menu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var s = getApp().settings;
        if (id == :plan) {
            openPlan(self);
        } else if (id == :window) {
            slider(new SliderView("Weckfenster", 10, 60, 5, s.windowMin, "Minuten", null,
                "Vorlauf vor der Weckzeit"), :window);
        } else if (id == :snoozeMin) {
            slider(new SliderView("Schlummerdauer", 1, 20, 1, s.snoozeMin, "Minuten", null,
                "Pause bis zum nächsten Alarm"), :snoozeMin);
        } else if (id == :snoozeMax) {
            slider(new SliderView("Max. Schlummern", 1, 5, 1, s.snoozeMax, "mal", null,
                "Danach geht nur noch Aus"), :snoozeMax);
        } else if (id == :vibe) {
            slider(new SliderView("Vibration", 1, 3, 1, s.vibeLevel, "", ["Sanft", "Normal", "Intensiv"],
                "Wird mit der Zeit stärker"), :vibe);
        } else if (id == :sens) {
            slider(new SliderView("Empfindlichkeit", 1, 5, 1, s.sensitivity, "",
                ["Sehr vorsichtig", "Vorsichtig", "Ausgewogen", "Früher", "Am frühesten"],
                "Höher = weckt früher"), :sens);
        } else if (id == :snooze) {
            s.snoozeOn = (item as WatchUi.ToggleMenuItem).isEnabled();
            s.save();
        } else if (id == :tone) {
            s.toneOn = (item as WatchUi.ToggleMenuItem).isEnabled();
            s.save();
            if (s.toneOn && (Attention has :playTone)) {
                Attention.playTone(Attention.TONE_ALARM);
            }
        } else if (id == :test) {
            var p = new AlarmPlayer();
            WatchUi.pushView(new AlarmView(null, p, true), new TestAlarmDelegate(p), WatchUi.SLIDE_UP);
            p.start(s.vibeLevel, s.toneOn, 6);
        } else if (id == :last) {
            var r = Application.Storage.getValue("lastNight");
            if (r instanceof Dictionary) {
                var v = new SummaryView(r, false);
                WatchUi.pushView(v, new SummaryDelegate(v), WatchUi.SLIDE_LEFT);
            }
        } else if (id == :help) {
            var help = new HelpView();
            WatchUi.pushView(help, new HelpDelegate(help), WatchUi.SLIDE_LEFT);
        } else if (id == :profile) {
            var pv = new ProfileView();
            WatchUi.pushView(pv, new ProfileDelegate(pv), WatchUi.SLIDE_LEFT);
        } else if (id == :resetModel) {
            var cv = new ConfirmView("Profil löschen?", "Alles Gelernte geht verloren.", "LÖSCHEN", "ABBRECHEN");
            WatchUi.pushView(cv, new ConfirmDelegate(method(:onResetAnswer)), WatchUi.SLIDE_IMMEDIATE);
        } else {
            handleDebugItem(id);
        }
    }

    function onResetAnswer(yes as Boolean) as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (yes) {
            getApp().model.reset();
            refresh();
        }
    }

    function onValue(key as Object, value as Number) as Void {
        var s = getApp().settings;
        if (key == :window) {
            s.windowMin = value;
        } else if (key == :snoozeMin) {
            s.snoozeMin = value;
        } else if (key == :snoozeMax) {
            s.snoozeMax = value;
        } else if (key == :vibe) {
            s.vibeLevel = value;
        } else if (key == :sens) {
            s.sensitivity = value;
        }
        s.save();
        refresh();
    }

    // Updates the small texts under the menu entries.
    function refresh() as Void {
        var s = getApp().settings;
        setSub(:plan, s.planSummary());
        setSub(:window, s.windowMin.format("%d") + " min vor der Weckzeit");
        setSub(:snoozeMin, s.snoozeMin.format("%d") + " min");
        setSub(:snoozeMax, s.snoozeMax.format("%d") + " mal");
        setSub(:vibe, s.vibeLabel());
        setSub(:sens, s.sensLabel());
        setSub(:profile, profileLabel());
        WatchUi.requestUpdate();
    }

    private function slider(view as SliderView, key as Symbol) as Void {
        WatchUi.pushView(view, new SliderDelegate(view, key, method(:onValue)), WatchUi.SLIDE_LEFT);
    }

    private function setSub(id as Symbol, text as String) as Void {
        var index = _menu.findItemById(id);
        if (index >= 0) {
            var item = _menu.getItem(index);
            if (item != null) {
                item.setSubLabel(text);
            }
        }
    }
}

// ------------------------------------------------------------- weekly plan

function openPlan(parent as SettingsDelegate) as Void {
    var s = getApp().settings;
    var menu = new WatchUi.Menu2({:title => "Wochenplan", :theme => WatchUi.MENU_THEME_PURPLE});
    menu.addItem(new WatchUi.MenuItem("Mo-Fr gleich", "Alle Werktage", :weekdays, null));
    menu.addItem(new WatchUi.MenuItem("Sa-So gleich", "Wochenende", :weekend, null));
    for (var i = 0; i < 7; i++) {
        menu.addItem(new WatchUi.MenuItem(TimeUtil.DAY_NAMES[i], TimeUtil.fmtHM(s.plan[i]), i, null));
    }
    WatchUi.pushView(menu, new PlanDelegate(menu, parent), WatchUi.SLIDE_LEFT);
}

class PlanDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as WatchUi.Menu2;
    private var _parent as SettingsDelegate;

    function initialize(menu as WatchUi.Menu2, parent as SettingsDelegate) {
        Menu2InputDelegate.initialize();
        _menu = menu;
        _parent = parent;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var s = getApp().settings;
        var title = "";
        var current = 420;
        if (id == :weekdays) {
            title = "Montag bis Freitag";
            current = s.plan[0];
        } else if (id == :weekend) {
            title = "Samstag und Sonntag";
            current = s.plan[5];
        } else if (id instanceof Number) {
            title = TimeUtil.DAY_NAMES[id];
            current = s.plan[id];
        }
        var v = new TimePickerView(title, current);
        WatchUi.pushView(v, new TimePickerDelegate(v, id, method(:onValue)), WatchUi.SLIDE_LEFT);
    }

    function onValue(key as Object, minutes as Number) as Void {
        var s = getApp().settings;
        if (key == :weekdays) {
            for (var i = 0; i < 5; i++) {
                s.plan[i] = minutes;
            }
        } else if (key == :weekend) {
            s.plan[5] = minutes;
            s.plan[6] = minutes;
        } else if (key instanceof Number) {
            s.plan[key] = minutes;
        }
        s.save();
        for (var i = 0; i < 7; i++) {
            var index = _menu.findItemById(i);
            if (index >= 0) {
                var item = _menu.getItem(index);
                if (item != null) {
                    item.setSubLabel(TimeUtil.fmtHM(s.plan[i]));
                }
            }
        }
        _parent.refresh();
    }
}

// ------------------------------------------------------------------- help

// Short instructions on three pages (UP/DOWN to switch).
class HelpView extends WatchUi.View {

    var page as Number = 0;

    function initialize() {
        View.initialize();
    }

    function pageCount() as Number {
        return 3;
    }

    function onUpdate(dc as Dc) as Void {
        Ui.clear(dc);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        Ui.title(dc, cx, cy - 136, "So funktioniert's", Ui.ACCENT);
        var pages = [
            "Abends START drücken und die Uhr am Handgelenk lassen. Im Weckfenster weckt sie dich bei leichtem Schlaf, spätestens zur Weckzeit.",
            "Beim Alarm: START = Aus, jede andere Taste = Schlummern. Morgens zeigt der Bericht, wie deine Nacht war.",
            "Wichtig: Der Wecker klingelt nur, solange SmartWake offen ist. Stell zur Sicherheit den Garmin-Wecker ein paar Minuten später."
        ];
        var fitted = Graphics.fitTextToArea(pages[page], Graphics.FONT_XTINY, 310, 270, true);
        if (fitted != null) {
            Ui.text(dc, cx, cy + 20, Graphics.FONT_XTINY, fitted, Ui.FG);
        }
        Ui.pageDots(dc, pageCount(), page);
    }
}

class HelpDelegate extends WatchUi.BehaviorDelegate {

    private var _v as HelpView;

    function initialize(view as HelpView) {
        BehaviorDelegate.initialize();
        _v = view;
    }

    function onNextPage() as Boolean {
        _v.page = (_v.page + 1) % _v.pageCount();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        return onNextPage();
    }

    // START or tap: next page, after the last page back to the menu
    function onSelect() as Boolean {
        if (_v.page + 1 < _v.pageCount()) {
            return onNextPage();
        }
        return onBack();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
