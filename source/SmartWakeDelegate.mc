import Toybox.Lang;
import Toybox.WatchUi;

class SmartWakeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new SmartWakeMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}