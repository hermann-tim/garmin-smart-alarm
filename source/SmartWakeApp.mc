import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Entry point of SmartWake.
class SmartWakeApp extends Application.AppBase {

    var settings as AppSettings;
    var model as SleepModel;     // what SmartWake has learned about your sleep
    var session as NightSession or Null = null;

    function initialize() {
        AppBase.initialize();
        settings = new AppSettings();
        model = new SleepModel();
    }

    function onStart(state as Dictionary?) as Void {
        settings.load();
        model.load();
    }

    // The app is closing. Sensors and timers stop, but a running night stays
    // in storage so it can continue when the app is opened again.
    function onStop(state as Dictionary?) as Void {
        var s = session;
        if (s != null) {
            s.shutdown();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var resumed = resumeNightSession(settings);
        if (resumed != null) {
            session = resumed;
            return resumed.initialView();
        }
        var home = new HomeView();
        return [home, new HomeDelegate(home)];
    }
}

function getApp() as SmartWakeApp {
    return Application.getApp() as SmartWakeApp;
}
