import Toybox.Attention;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Plays the wake-up alarm: starts gentle and gets more insistent over time.
// Forerunner watches cannot change the vibration strength, so the alarm
// escalates with longer pulses, shorter pauses and (optionally) tones.
class AlarmPlayer {

    const MAX_SECONDS = 900;   // stop by itself after 15 minutes

    var running as Boolean = false;
    var seconds as Number = 0;     // real seconds since start

    private var _timer as Timer.Timer;
    private var _level as Number = 2;
    private var _tone as Boolean = false;
    private var _speed as Number = 1;     // > 1 = faster escalation (test alarm)
    private var _lastPulse as Number = -100;

    function initialize() {
        _timer = new Timer.Timer();
    }

    // level: 1 = gentle, 2 = normal, 3 = intense. speed: escalation speed-up for tests.
    function start(level as Number, tone as Boolean, speed as Number) as Void {
        _level = (level < 1) ? 1 : ((level > 3) ? 3 : level);
        _tone = tone;
        _speed = speed;
        seconds = 0;
        _lastPulse = -100;
        running = true;
        _timer.stop();
        _timer.start(method(:onTick), 1000, true);
        lightUp();
        pulse();
    }

    function stop() as Void {
        running = false;
        _timer.stop();
    }

    // 0 = gentle start ... 3 = maximum
    function stage() as Number {
        var t = seconds * _speed;
        if (t < 30) {
            return 0;
        }
        if (t < 60) {
            return 1;
        }
        if (t < 120) {
            return 2;
        }
        return 3;
    }

    function onTick() as Void {
        seconds += 1;
        if (seconds >= MAX_SECONDS) {
            stop();
            WatchUi.requestUpdate();
            return;
        }
        var period = [4, 3, 2, 2][stage()];
        if (seconds - _lastPulse >= period) {
            pulse();
        }
        if (seconds % 10 == 0) {
            lightUp();
        }
        WatchUi.requestUpdate();
    }

    private function pulse() as Void {
        _lastPulse = seconds;
        var s = stage();
        // vibration length in ms per level (rows) and stage (columns)
        var lengths = [
            [300, 600, 900, 1500],
            [500, 800, 1200, 1700],
            [800, 1100, 1500, 1900]
        ];
        var ms = lengths[_level - 1][s];
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, ms)]);
        }
        if (_tone && s >= 1 && (Attention has :playTone)) {
            if (s == 1) {
                Attention.playTone({:toneProfile => [
                    new Attention.ToneProfile(1500, 120),
                    new Attention.ToneProfile(2000, 120)
                ]});
            } else {
                Attention.playTone(Attention.TONE_ALARM);
            }
        }
    }

    private function lightUp() as Void {
        if (Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e) {
            }
        }
    }
}
