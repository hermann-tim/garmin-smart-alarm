import Toybox.Lang;
import Toybox.System;

// Temporary night protocol for tuning the sleep detection.
//
// Writes compact lines with System.println. On the watch they are saved to
// GARMIN/APPS/LOGS/<app file name>.TXT, but only if that (empty) file exists.
// Garmin limits these files to about 5 KB (+ one 5 KB backup), so the minute
// values are packed into one character each (see SleepEngine.writeLog).
//
// To switch it off: set ENABLED to false (or delete the TXT file on the watch).
module NightLog {

    const ENABLED = true;
    const ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_";

    function write(line as String) as Void {
        if (ENABLED) {
            System.println("SW " + line);
        }
    }

    // 0..63 -> one character (larger values are capped), below 0 -> "." (no value)
    function enc(v as Number) as String {
        if (v < 0) {
            return ".";
        }
        if (v > 63) {
            v = 63;
        }
        var s = ALPHABET.substring(v, v + 1);
        return (s != null) ? s : "?";
    }
}
