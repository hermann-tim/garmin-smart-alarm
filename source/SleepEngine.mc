import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.SensorHistory;

// Our own sleep stage estimate (Garmin's stages are not available to apps).
// REM sleep is not told apart and counts as light sleep.
const STAGE_DEEP = 0;
const STAGE_LIGHT = 1;
const STAGE_WAKE = 2;
const STAGE_NODATA = 3;   // no pulse while lying still (watch off the wrist, sensor gap)

// Why the alarm went off.
const REASON_DEADLINE = 0;
const REASON_MOVEMENT = 1;
const REASON_LIGHT = 2;
const REASON_AWAKE = 3;
const REASON_LATE = 4;
const REASON_CANCEL = 5;

// Reads the watch sensors through the night, rates every minute how light the
// sleep looks and decides when it is a good moment to wake up.
//
// Signals (see COMP_* in SleepModel.mc):
//   movement, heart rate above resting level, heart rate unrest, HRV,
//   Garmin's live stress score, breathing, and the personal sleep cycle.
// Each signal is compared to the user's normal values: learned from earlier
// nights at first, then more and more from this night itself. How much each
// signal counts is learned from the morning feedback (SleepModel).
class SleepEngine {

    const EPOCH = 60;         // seconds per analysis step
    const MAX_EPOCHS = 900;   // 15 hours
    const MIN_SLEEP = 1200;   // no early wake-up during the first 20 minutes

    // Live values for the night screen
    var hrNow as Number = 0;
    var stageNow as Number = -1;
    var epochs as Number = 0;

    // Night setup
    private var _start as Number = 0;
    private var _windowStart as Number = 0;
    private var _deadline as Number = 0;
    private var _sens as Number = 3;
    private var _rate as Number = 10;

    // Learned profile from earlier nights (-1 = not known yet)
    private var _weights as Array<Float>;
    private var _priorHr as Float;
    private var _priorRm as Float;
    private var _priorSt as Float;
    private var _priorRr as Float;
    private var _lightHr as Float;
    private var _cycle as Float;
    private var _shift as Float;

    // Running minute
    private var _epochStart as Number = 0;
    private var _act as Float = 0.0;
    private var _hrSum as Number = 0;
    private var _hrN as Number = 0;
    private var _ibiPrev as Number = 0;
    private var _ibiSq as Float = 0.0;
    private var _ibiN as Number = 0;
    private var _stSum as Number = 0;
    private var _stN as Number = 0;
    private var _rrSum as Number = 0;
    private var _rrN as Number = 0;
    private var _accN as Number = 0;          // accelerometer deliveries (0 = movement unknown)
    private var _ticks as Number = 0;

    // Accelerometer state
    private var _hasPrev as Boolean = false;
    private var _px as Number = 0;
    private var _py as Number = 0;
    private var _pz as Number = 0;
    private var _noise as Float = 12.0;

    // Last minutes, index 0 = newest, -1.0 = no value
    private var _mHist as Array<Float> = [0.0, 0.0, 0.0];
    private var _hrHist as Array<Float> = [-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0];
    private var _rrHist as Array<Float> = [-1.0, -1.0, -1.0, -1.0, -1.0];
    private var _moveRun as Number = 0;       // minutes in a row with clear movement
    private var _prevLight as Number = 0;

    // Distributions over the night (101 bins) = this night's normal values
    private var _hHr as Array<Number>;
    private var _hRm as Array<Number>;
    private var _hSt as Array<Number>;
    private var _hLight as Array<Number>;
    private var _nHr as Number = 0;
    private var _nRm as Number = 0;
    private var _nSt as Number = 0;
    private var _nLight as Number = 0;

    // Sums for the morning report
    private var _sumRm as Float = 0.0;
    private var _cntRm as Number = 0;
    private var _sumSt as Float = 0.0;
    private var _cntSt as Number = 0;
    private var _sumRr as Float = 0.0;
    private var _cntRr as Number = 0;
    private var _bbStart as Number or Null = null;

    // One value per minute
    private var _logLight as Array<Number>;
    private var _logStage as Array<Number>;
    private var _logHr as Array<Number>;
    private var _logMove as Array<Number>;
    private var _logRm as Array<Number>;     // RMSSD in ms, 0 = none
    private var _logSt as Array<Number>;     // stress, -1 = none
    private var _logRr as Array<Number>;     // breathing in tenths per minute, 0 = none

    // For the night protocol: cycle changes (negative = assumed) and the wake-up moment
    private var _bounds as Array<Number> = [] as Array<Number>;
    private var _lastLight as Number = 0;
    private var _lastBody as Number = 0;
    private var _lastLimit as Number = -1;
    private var _wakeInfo as String = "";

    // Falling asleep and sleep cycles
    private var _onset as Number = -1;          // minute index where sleep began
    private var _calmRun as Number = 0;
    private var _lastBoundary as Number = -1;   // minute index of the last cycle change
    private var _cycSum as Number = 0;
    private var _cycN as Number = 0;

    // Signals of the last minute and at the wake-up moment
    private var _lastComps as Array<Float>;
    private var _wakeComps as Array<Float> or Null = null;

    // Wake decision
    private var _armed as Boolean = false;
    private var _pendingKind as Number = -1;
    private var _pendingText as String = "";

    function initialize(model as SleepModel) {
        _hHr = zeros(101);
        _hRm = zeros(101);
        _hSt = zeros(101);
        _hLight = zeros(101);
        _logLight = new Array<Number>[MAX_EPOCHS];
        _logStage = new Array<Number>[MAX_EPOCHS];
        _logHr = new Array<Number>[MAX_EPOCHS];
        _logMove = new Array<Number>[MAX_EPOCHS];
        _logRm = new Array<Number>[MAX_EPOCHS];
        _logSt = new Array<Number>[MAX_EPOCHS];
        _logRr = new Array<Number>[MAX_EPOCHS];
        _weights = new Array<Float>[COMP_COUNT];
        for (var k = 0; k < COMP_COUNT; k++) {
            _weights[k] = model.weights[k];
        }
        _priorHr = model.minHr;
        _priorRm = model.rmssd;
        _priorSt = model.stress;
        _priorRr = model.resp;
        _lightHr = model.lightHr;
        _cycle = model.cycleMin;
        _shift = model.shift;
        _lastComps = missingComps();
    }

    // Set up the night without touching the sensors (also used by the tests).
    function setup(now as Number, windowStart as Number, deadline as Number, sensitivity as Number) as Void {
        _start = now;
        _windowStart = windowStart;
        _deadline = deadline;
        _sens = sensitivity;
        _epochStart = now;
    }

    function start(now as Number, windowStart as Number, deadline as Number, sensitivity as Number) as Void {
        setup(now, windowStart, deadline, sensitivity);
        _bbStart = readBodyBattery();
        enableSensors();
    }

    function stop() as Void {
        try {
            Sensor.unregisterSensorDataListener();
        } catch (e) {
        }
        try {
            Sensor.enableSensorEvents(null);
        } catch (e) {
        }
        try {
            Sensor.setEnabledSensors([] as Array<Sensor.SensorType>);
        } catch (e) {
        }
    }

    // Called every few seconds by the night session.
    function tick(now as Number) as Void {
        _ticks += 1;
        if (_ticks % 3 == 0) {
            sampleMonitor();
        }
        _armed = smartAllowed(now);
        // If the watch did not call us for a while, the missed minutes are closed too.
        // They have no measurements and are marked "no data" (not "calm" or "deep"),
        // so the minutes stay in step with the clock.
        var guard = 0;
        while (now - _epochStart >= EPOCH && guard < 5) {
            _epochStart += EPOCH;
            closeEpoch(_epochStart);
            guard += 1;
        }
        if (now - _epochStart >= EPOCH) {
            _epochStart = now; // long gap: start fresh
        }
    }

    function pendingKind() as Number {
        return _pendingKind;
    }

    function pendingText() as String {
        return _pendingText;
    }

    function stageLabel() as String {
        if (stageNow < 0) {
            return "Messung läuft";
        }
        return ["Tiefschlaf", "Leichtschlaf", "Wach", "Kein Puls"][stageNow];
    }

    // ---------------------------------------------------------------- sensors

    private function enableSensors() as Void {
        try {
            Sensor.setEnabledSensors([Sensor.SENSOR_ONBOARD_HEARTRATE] as Array<Sensor.SensorType>);
        } catch (e) {
        }
        try {
            Sensor.enableSensorEvents(method(:onSensorInfo));
        } catch (e) {
        }
        _rate = 10;
        try {
            var maxRate = Sensor.getMaxSampleRate();
            if (maxRate > 0 && maxRate < _rate) {
                _rate = maxRate;
            }
        } catch (e) {
        }
        if (!listen(true)) {
            listen(false);
        }
    }

    private function listen(withBeats as Boolean) as Boolean {
        try {
            if (withBeats) {
                Sensor.registerSensorDataListener(method(:onSensorData), {
                    :period => 4,
                    :accelerometer => {:enabled => true, :sampleRate => _rate},
                    :heartBeatIntervals => {:enabled => true}
                });
            } else {
                Sensor.registerSensorDataListener(method(:onSensorData), {
                    :period => 4,
                    :accelerometer => {:enabled => true, :sampleRate => _rate}
                });
            }
            return true;
        } catch (e) {
            return false;
        }
    }

    // 1 Hz heart rate
    function onSensorInfo(info as Sensor.Info) as Void {
        var hr = info.heartRate;
        if (hr != null && hr >= 30 && hr <= 220) {
            _hrSum += hr;
            _hrN += 1;
            hrNow = hr;
        }
    }

    // Every 4 seconds: raw accelerometer samples and beat-to-beat intervals
    function onSensorData(data as Sensor.SensorData) as Void {
        var acc = data.accelerometerData;
        if (acc != null) {
            _accN += 1;
            addAccel(acc.x, acc.y, acc.z);
        }
        var hrd = data.heartRateData;
        if (hrd != null) {
            var beats = hrd.heartBeatIntervals;
            if (beats != null) {
                addBeats(beats);
            }
        }
    }

    private function addAccel(xs as Array<Number>, ys as Array<Number>, zs as Array<Number>) as Void {
        var n = xs.size();
        if (ys.size() < n) {
            n = ys.size();
        }
        if (zs.size() < n) {
            n = zs.size();
        }
        var scale = 10.0 / _rate;
        var chunk = 0.0;
        for (var i = 0; i < n; i++) {
            var x = xs[i];
            var y = ys[i];
            var z = zs[i];
            if (_hasPrev) {
                // Change between two samples, so the watch position does not matter.
                var act = (absn(x - _px) + absn(y - _py) + absn(z - _pz)).toFloat();
                // Track the sensor noise level (running median) and ignore everything below it.
                if (act > _noise) {
                    _noise += 0.05;
                } else {
                    _noise -= 0.05;
                }
                var band = _noise * 3.0;
                if (band < 15.0) {
                    band = 15.0;
                }
                if (act > band) {
                    chunk += (act - band) * scale;
                }
            }
            _px = x;
            _py = y;
            _pz = z;
            _hasPrev = true;
        }
        if (_noise < 2.0) {
            _noise = 2.0;
        } else if (_noise > 80.0) {
            _noise = 80.0;
        }
        _act += chunk;
        // A clear movement inside the wake window wakes you right away.
        if (_armed && _pendingKind < 0 && chunk >= chunkLimit()) {
            var c = copyComps(_lastComps);
            c[COMP_MOVE] = 1.0;
            setPending(REASON_MOVEMENT, "Bewegung im Weckfenster", c);
        }
    }

    private function addBeats(beats as Array<Number>) as Void {
        for (var i = 0; i < beats.size(); i++) {
            var v = beats[i];
            if (v == null || v < 300 || v > 2000) {
                _ibiPrev = 0;
                continue;
            }
            if (_ibiPrev > 0) {
                var d = v - _ibiPrev;
                // Skip jumps over 25 %: usually measurement errors.
                if (d * 4 <= _ibiPrev && d * 4 >= -_ibiPrev) {
                    _ibiSq += (d * d).toFloat();
                    _ibiN += 1;
                }
            }
            _ibiPrev = v;
        }
    }

    // Garmin's live stress score and breathing rate
    private function sampleMonitor() as Void {
        var ai = ActivityMonitor.getInfo();
        if (ai has :stressScore) {
            var s = ai.stressScore;
            if (s != null && s >= 0 && s <= 100) {
                _stSum += s;
                _stN += 1;
            }
        }
        if (ai has :respirationRate) {
            var r = ai.respirationRate;
            if (r != null && r >= 4 && r <= 40) {
                _rrSum += r;
                _rrN += 1;
            }
        }
    }

    private function readBodyBattery() as Number or Null {
        try {
            if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
                var it = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
                if (it != null) {
                    var s = it.next();
                    if (s != null) {
                        var v = s.data;
                        if (v != null) {
                            return v.toNumber();
                        }
                    }
                }
            }
        } catch (e) {
        }
        return null;
    }

    // --------------------------------------------------------------- analysis

    private function smartAllowed(t as Number) as Boolean {
        return t >= _windowStart && t < _deadline && t - _start >= MIN_SLEEP;
    }

    private function closeEpoch(endSec as Number) as Void {
        var idx = epochs;
        // No accelerometer data at all in this minute: movement is unknown, not "none".
        var moveKnown = _accN > 0;
        var m = moveKnown ? motionScore(_act) : 0.0;
        var hr = (_hrN > 0) ? _hrSum.toFloat() / _hrN : -1.0;
        var rm = (_ibiN >= 15) ? Math.sqrt(_ibiSq / _ibiN).toFloat() : -1.0;
        var st = (_stN > 0) ? _stSum.toFloat() / _stN : -1.0;
        var rr = (_rrN > 0) ? _rrSum.toFloat() / _rrN : -1.0;

        _mHist = [m, _mHist[0], _mHist[1]];
        _hrHist = [hr, _hrHist[0], _hrHist[1], _hrHist[2], _hrHist[3], _hrHist[4], _hrHist[5], _hrHist[6]];
        _rrHist = [rr, _rrHist[0], _rrHist[1], _rrHist[2], _rrHist[3]];
        _moveRun = (m >= 0.45) ? _moveRun + 1 : 0;

        // This night's normal values come from calm minutes only.
        if (m < 0.45) {
            if (hr > 0.0) {
                _nHr += addBin(_hHr, (hr + 0.5).toNumber() - 30);
            }
            if (rm > 0.0) {
                _nRm += addBin(_hRm, (rm / 2.0).toNumber());
            }
            if (st >= 0.0) {
                _nSt += addBin(_hSt, (st + 0.5).toNumber());
            }
        }
        if (rm > 0.0) {
            _sumRm += rm;
            _cntRm += 1;
        }
        if (st >= 0.0) {
            _sumSt += st;
            _cntSt += 1;
        }
        if (rr > 0.0) {
            _sumRr += rr;
            _cntRr += 1;
        }

        // Every signal gives 0..1 (1 = looks like light sleep), -1 = not available.
        var c = missingComps();
        if (moveKnown) {
            c[COMP_MOVE] = maxf(m, maxf(0.6 * _mHist[1], 0.35 * _mHist[2]));
        }

        var hrElev = 0.0;
        var hrBase = blend((_nHr >= 10) ? percentile(_hHr, _nHr, 10) + 30.0 : -1.0, _priorHr, _nHr);
        if (hr > 0.0 && hrBase > 0.0) {
            hrElev = hr - hrBase;
            // centred on the user's typical heart rate rise in light sleep
            c[COMP_HR] = sigmoid((hrElev - _lightHr) * 0.8);
        }

        var hrDelta = meanAbsDelta(_hrHist, 4, 2);
        if (hrDelta >= 0.0) {
            c[COMP_UNREST] = clamp01((hrDelta - 0.6) / 3.0);
        }

        var rmBase = blend((_nRm >= 10) ? percentile(_hRm, _nRm, 50) * 2.0 + 1.0 : -1.0, _priorRm, _nRm);
        if (rm > 0.0 && rmBase > 0.0) {
            c[COMP_HRV] = clamp01((rmBase / maxf(rm, 5.0) - 1.0) / 0.8);
        }

        var stBase = blend((_nSt >= 10) ? percentile(_hSt, _nSt, 50).toFloat() : -1.0, _priorSt, _nSt);
        if (st >= 0.0 && stBase >= 0.0) {
            c[COMP_STRESS] = clamp01((st - stBase - 3.0) / 20.0);
        }

        var rrVar = stdDev(_rrHist);
        var resp = -1.0;
        if (rrVar >= 0.0) {
            resp = clamp01((rrVar - 0.4) / 2.0);
        }
        if (rr > 0.0 && _priorRr > 0.0) {
            resp = maxf(resp, clamp01((rr - _priorRr - 0.5) / 2.0));
        }
        c[COMP_RESP] = resp;

        // Where are we in the personal sleep cycle? 1 = a cycle change is due.
        if (_onset >= 0 && _lastBoundary >= 0) {
            var phase = (idx - _lastBoundary).toFloat() / _cycle;
            c[COMP_CYCLE] = (0.5 * (1.0 + Math.cos(2.0 * Math.PI * phase))).toFloat();
        }

        // How light does the sleep look? 0 = very deep, 100 = awake.
        // "light" uses all signals, "body" only the body signals (without the cycle clock).
        var light = score(c, -1);
        var body = score(c, COMP_CYCLE);

        var stage = classify(endSec, m, hr, hrElev, c);
        if (endSec - _start >= 1800 && stage != STAGE_WAKE && stage != STAGE_NODATA) {
            _nLight += addBin(_hLight, light);
        }

        if (idx < MAX_EPOCHS) {
            _logLight[idx] = light;
            _logStage[idx] = stage;
            _logHr[idx] = (hr > 0.0) ? (hr + 0.5).toNumber() : 0;
            _logMove[idx] = (m * 100.0).toNumber();
            _logRm[idx] = (rm > 0.0) ? (rm + 0.5).toNumber() : 0;
            _logSt[idx] = (st >= 0.0) ? (st + 0.5).toNumber() : -1;
            _logRr[idx] = (rr > 0.0) ? (rr * 10.0 + 0.5).toNumber() : 0;
            epochs += 1;
        }
        trackCycles(idx, m, hrElev, stage);
        stageNow = stage;
        _lastComps = c;
        _lastLight = light;
        _lastBody = body;

        if (_pendingKind < 0 && smartAllowed(endSec)) {
            decide(endSec, light, body, m, stage, c);
        }
        _prevLight = light;

        _act = 0.0;
        _accN = 0;
        _hrSum = 0;
        _hrN = 0;
        _ibiSq = 0.0;
        _ibiN = 0;
        _stSum = 0;
        _stN = 0;
        _rrSum = 0;
        _rrN = 0;
    }

    // Sleep stage of one minute, from the body signals. Checked against Garmin's stages
    // of a real night: there, deep sleep came with a very even pulse, while short still
    // phases between movements were light sleep, and single turns were not waking up.
    private function classify(endSec as Number, m as Float, hr as Float, hrElev as Float, c as Array<Float>) as Number {
        // Awake: clear movement for 2 minutes with a strong pulse rise, or restless for 4 minutes.
        if ((_moveRun >= 2 && hrElev >= 10.0) || _moveRun >= 4) {
            return STAGE_WAKE;
        }
        // No pulse: lying still can mean anything (also: the watch is off the wrist).
        if (hr < 0.0) {
            return (m >= 0.05) ? STAGE_LIGHT : STAGE_NODATA;
        }
        // Deep: no movement for about 3 minutes and the pulse hardly changed over the
        // last 8 minutes. Not in the first 20 minutes: lying still then may mean being awake.
        // A pulse far above the night's resting level is not deep sleep either (lying awake).
        var still = c[COMP_MOVE] >= 0.0 && c[COMP_MOVE] < 0.05;
        var even = meanAbsDelta(_hrHist, 8, 5);
        if (endSec - _start >= MIN_SLEEP && still && even >= 0.0 && even <= 0.8 && hrElev < 8.0) {
            return STAGE_DEEP;
        }
        return STAGE_LIGHT;
    }

    // Finds the moment of falling asleep and the changes between sleep cycles.
    // A cycle change shows as movement plus a heart rate rise, 70-115 minutes
    // after the last one. If none shows up, it is assumed where it was expected,
    // so the cycle clock stays in step instead of drifting.
    private function trackCycles(idx as Number, m as Float, hrElev as Float, stage as Number) as Void {
        if (_onset < 0) {
            // A minute without data neither counts as calm nor breaks a calm run.
            if (stage == STAGE_NODATA) {
                return;
            }
            if (stage != STAGE_WAKE && m < 0.2) {
                _calmRun += 1;
            } else {
                _calmRun = 0;
            }
            if (_calmRun >= 10) {
                _onset = idx - 9;
                _lastBoundary = _onset;
            }
            return;
        }
        var since = idx - _lastBoundary;
        if (since >= 70 && ((m >= 0.45 && hrElev >= 3.0) || stage == STAGE_WAKE)) {
            if (since <= 115) {
                _cycSum += since;
                _cycN += 1;
            }
            _lastBoundary = idx;
            _bounds.add(idx);
        } else if (since >= 115) {
            _lastBoundary += (_cycle + 0.5).toNumber();
            _bounds.add(-_lastBoundary);
        }
    }

    // Is now a good moment to wake up?
    private function decide(t as Number, light as Number, body as Number, m as Float, stage as Number, c as Array<Float>) as Void {
        if (stage == STAGE_WAKE) {
            setPending(REASON_AWAKE, "Du warst schon wach", c);
            return;
        }
        if (m >= moveLimit()) {
            setPending(REASON_MOVEMENT, "Bewegung im Leichtschlaf", c);
            return;
        }
        // Without a pulse there is nothing to judge: wait, the wake time still rings.
        if (stage == STAGE_NODATA) {
            return;
        }
        // Compare with this night's own values. Towards the wake time it gets easier,
        // slowly at first and faster at the end.
        var limit = lightLimit();
        var span = _deadline - _windowStart;
        var progress = (span > 0) ? clamp01((t - _windowStart).toFloat() / span) : 1.0;
        limit = limit * (1.0 - 0.35 * Math.pow(progress, 1.5).toFloat());
        _lastLimit = (limit + 0.5).toNumber();
        // Lying completely still while the pulse is up was REM sleep (dreaming) when compared
        // with Garmin's stages. So the body signals only wake you together with at least a
        // small movement in the last minutes; otherwise the next movement or the wake time will.
        // The cycle clock may tip the balance, but the body has to show something too.
        var moved = c[COMP_MOVE] >= 0.05;
        if (moved && light >= limit && _prevLight >= limit * 0.85 && body >= 15) {
            setPending(REASON_LIGHT, "Leichtschlaf: " + signals(c), c);
            return;
        }
        if (_deadline - t <= 300 && stage != STAGE_DEEP && light >= limit * 0.6) {
            setPending(REASON_LATE, "Kein Tiefschlaf kurz vor der Weckzeit", c);
        }
    }

    // The two signals that contributed most, for the wake-up reason.
    private function signals(c as Array<Float>) as String {
        var names = ["Bewegung", "Puls höher", "Puls unruhig", "HRV niedriger", "Stress höher", "Atmung unruhig", "Zyklus-Ende"];
        var vals = new Array<Float>[COMP_COUNT];
        for (var k = 0; k < COMP_COUNT; k++) {
            vals[k] = (c[k] >= 0.3) ? c[k] * _weights[k] : 0.0;
        }
        var out = "";
        for (var n = 0; n < 2; n++) {
            var best = -1;
            var bestVal = 0.0;
            for (var k = 0; k < COMP_COUNT; k++) {
                if (vals[k] > bestVal) {
                    best = k;
                    bestVal = vals[k];
                }
            }
            if (best >= 0) {
                if (out.length() > 0) {
                    out += ", ";
                }
                out += names[best];
                vals[best] = 0.0;
            }
        }
        return (out.length() > 0) ? out : "viele kleine Signale";
    }

    // Limits depend on the sensitivity setting (1 = careful ... 5 = early)
    // plus the learned shift from the morning feedback.
    private function lightLimit() as Float {
        var pct = [85, 78, 70, 62, 55][_sens - 1] + _shift;
        if (pct < 45.0) {
            pct = 45.0;
        } else if (pct > 92.0) {
            pct = 92.0;
        }
        var base = 40.0 - 4.0 * (_sens - 3) + _shift * 0.5;
        if (_nLight >= 30) {
            base = percentile(_hLight, _nLight, (pct + 0.5).toNumber()).toFloat();
        }
        if (base < 12.0) {
            base = 12.0;
        } else if (base > 70.0) {
            base = 70.0;
        }
        return base;
    }

    // The learned strictness also applies to movement: after tired mornings
    // a movement has to be clearer to wake you.
    private function moveLimit() as Float {
        return [0.6, 0.52, 0.45, 0.38, 0.32][_sens - 1] * strictness();
    }

    private function chunkLimit() as Float {
        return 2500.0 * [2.0, 1.4, 1.0, 0.7, 0.5][_sens - 1] * strictness();
    }

    // 1.0 = neutral, up to 1.3 = stricter (shift +12), down to 0.7 = wakes more readily (shift -12)
    private function strictness() as Float {
        return 1.0 + _shift * 0.025;
    }

    private function setPending(kind as Number, text as String, c as Array<Float>) as Void {
        _pendingKind = kind;
        _pendingText = text;
        _wakeComps = copyComps(c);
        _wakeInfo = "kind=" + kind + " min=" + epochs + " light=" + _lastLight + " body=" + _lastBody + " limit=" + _lastLimit;
    }

    // ---------------------------------------------------------- night protocol

    // Writes the whole night into the protocol (see NightLog). One line per hour,
    // seven characters per minute: movement, pulse, HRV, stress, breathing, score, stage.
    function writeLog() as Void {
        if (!NightLog.ENABLED) {
            return;
        }
        var b = "";
        for (var i = 0; i < _bounds.size(); i++) {
            b += ((i > 0) ? "," : "") + _bounds[i];
        }
        NightLog.write("CYC onset=" + _onset + " n=" + _cycN + " sum=" + _cycSum + " b=" + b);
        var i = 0;
        while (i < epochs) {
            var end = (i + 60 < epochs) ? i + 60 : epochs;
            var line = "D" + i + ":";
            for (var j = i; j < end; j++) {
                line += NightLog.enc(_logMove[j] * 63 / 100);
                line += (_logHr[j] > 0) ? NightLog.enc(_logHr[j] - 30) : ".";
                line += (_logRm[j] > 0) ? NightLog.enc(_logRm[j] / 3) : ".";
                line += (_logSt[j] >= 0) ? NightLog.enc(_logSt[j] / 2) : ".";
                line += (_logRr[j] > 0) ? NightLog.enc((_logRr[j] - 40) * 4 / 10) : ".";
                line += NightLog.enc(_logLight[j] * 63 / 100);
                line += NightLog.enc(_logStage[j]);
            }
            NightLog.write(line);
            i = end;
        }
        var wc = _wakeComps;
        var c = (wc != null) ? wc : _lastComps;
        var cs = "";
        for (var k = 0; k < COMP_COUNT; k++) {
            cs += ((k > 0) ? "," : "") + (c[k] * 100.0).toNumber();
        }
        NightLog.write("WAKE " + _wakeInfo + " c=" + cs + " noise=" + _noise.toNumber() + " rate=" + _rate);
    }

    // ----------------------------------------------------------------- report

    // Compact summary of the night for learning (see NS_* in SleepModel.mc).
    function learningSummary(wakeSec as Number, kind as Number) as Array<Numeric> {
        var s = new Array<Numeric>[NS_SIZE];
        s[NS_TIME] = wakeSec;
        s[NS_CYCLE] = (_cycN > 0) ? _cycSum.toFloat() / _cycN : -1;
        var low = lowMeanHr();
        var hrMinutes = 0;
        for (var i = 0; i < epochs; i++) {
            if (_logHr[i] > 0) {
                hrMinutes += 1;
            }
        }
        // Enough heart rate data? At least half of the minutes.
        s[NS_MINHR] = (epochs > 0 && hrMinutes * 2 >= epochs) ? low : -1;
        s[NS_RMSSD] = (_cntRm > 0) ? _sumRm / _cntRm : -1;
        s[NS_STRESS] = (_cntSt > 0) ? _sumSt / _cntSt : -1;
        s[NS_RESP] = (_cntRr > 0) ? _sumRr / _cntRr : -1;
        s[NS_LIGHTHR] = lightHrRise(low);
        var early = (kind == REASON_MOVEMENT || kind == REASON_LIGHT || kind == REASON_AWAKE || kind == REASON_LATE);
        s[NS_EARLY] = early ? 1 : 0;
        var earlyMin = (_deadline - wakeSec) / 60;
        s[NS_EARLYMIN] = (earlyMin > 0) ? earlyMin : 0;
        s[NS_FEEL] = -1;
        s[NS_SLEEPMIN] = sleepMinutes();
        var wc = _wakeComps;
        var c = (wc != null) ? wc : _lastComps;
        for (var k = 0; k < COMP_COUNT; k++) {
            s[NS_COMPS + k] = c[k];
        }
        return s;
    }

    // Summary of the night for the morning screen. Stored on the watch.
    function report(wakeSec as Number, kind as Number, text as String) as Dictionary<String, Object> {
        var n = epochs;
        var onset = (_onset >= 0) ? _onset : 0;
        var cnt = [0, 0, 0, 0];
        var hrSum = 0;
        var hrN = 0;
        var hrMin = 999;
        var moves = 0;
        for (var i = onset; i < n; i++) {
            cnt[_logStage[i]] += 1;
            var h = _logHr[i];
            if (h > 0) {
                hrSum += h;
                hrN += 1;
                if (h < hrMin) {
                    hrMin = h;
                }
            }
            if (_logMove[i] >= 45) {
                moves += 1;
            }
        }
        // Shares of deep, light and awake. Minutes without data are left out.
        var total = cnt[0] + cnt[1] + cnt[2];
        var pc = [0, 0, 0];
        if (total > 0) {
            for (var k = 0; k < 3; k++) {
                pc[k] = (cnt[k] * 100 + total / 2) / total;
            }
        }
        var onsetSec = _start + onset * EPOCH;
        var r = {
            "v" => 1,
            "st" => _start,
            "on" => onsetSec,
            "wu" => wakeSec,
            "dl" => _deadline,
            "ws" => _windowStart,
            "rk" => kind,
            "rs" => text,
            "sl" => (cnt[STAGE_DEEP] + cnt[STAGE_LIGHT]) * EPOCH,
            "pc" => pc,
            "mv" => moves,
            "S" => _logStage.slice(0, n)
        } as Dictionary<String, Object>;
        if (cnt[STAGE_NODATA] > 0) {
            r.put("nd", cnt[STAGE_NODATA]);
        }
        if (hrN > 0) {
            r.put("hrA", (hrSum + hrN / 2) / hrN);
            r.put("hrM", hrMin);
        }
        if (_cntRm > 0) {
            r.put("rm", (_sumRm / _cntRm + 0.5).toNumber());
        }
        if (_cntSt > 0) {
            r.put("sa", (_sumSt / _cntSt + 0.5).toNumber());
        }
        if (_cntRr > 0) {
            r.put("rr", (_sumRr / _cntRr * 10.0 + 0.5).toNumber());
        }
        if (_cycN > 0) {
            r.put("cy", (_cycSum.toFloat() / _cycN + 0.5).toNumber());
        }
        var bb0 = _bbStart;
        var bb1 = readBodyBattery();
        if (bb0 != null && bb1 != null) {
            r.put("bb", bb1 - bb0);
        }
        return r;
    }

    // Minutes asleep after falling asleep (awake minutes and minutes without data not counted)
    private function sleepMinutes() as Number {
        if (_onset < 0) {
            return 0;
        }
        var n = 0;
        for (var i = _onset; i < epochs; i++) {
            var s = _logStage[i];
            if (s == STAGE_DEEP || s == STAGE_LIGHT) {
                n += 1;
            }
        }
        return n;
    }

    // Average of the lowest 10 % of calm-minute heart rates, -1 if too few
    private function lowMeanHr() as Float {
        if (_nHr < 30) {
            return -1.0;
        }
        var target = _nHr / 10;
        var cnt = 0;
        var sum = 0;
        for (var i = 0; i < 101 && cnt < target; i++) {
            var take = _hHr[i];
            if (cnt + take > target) {
                take = target - cnt;
            }
            cnt += take;
            sum += take * (i + 30);
        }
        return (cnt > 0) ? sum.toFloat() / cnt : -1.0;
    }

    // Typical heart rate rise in minutes with light movement, -1 if too few
    private function lightHrRise(low as Float) as Float {
        if (low <= 0.0) {
            return -1.0;
        }
        var sum = 0.0;
        var n = 0;
        for (var i = (_onset >= 0) ? _onset : 0; i < epochs; i++) {
            if (_logHr[i] > 0 && _logMove[i] >= 20 && _logMove[i] <= 80) {
                sum += _logHr[i] - low;
                n += 1;
            }
        }
        return (n >= 5) ? sum / n : -1.0;
    }

    // ------------------------------------------------------------------ tests

    // Feeds one prepared minute into the analysis (unit tests and night replay, debug builds only).
    // hr, st < 0 and rm, rr <= 0 mean "no value".
    (:debug)
    function injectEpoch(endSec as Number, motion as Float, hr as Number, rm as Float, st as Number, rr as Float) as Void {
        _act = (motion <= 0.0) ? 0.0 : (50.0 * (Math.pow(10.0, 2.5 * motion) - 1.0)).toFloat();
        _accN = 15;
        if (hr > 0) {
            _hrSum = hr * 60;
            _hrN = 60;
        }
        if (rm > 0.0) {
            _ibiSq = rm * rm * 30.0;
            _ibiN = 30;
        }
        if (st >= 0) {
            _stSum = st * 4;
            _stN = 4;
        }
        if (rr > 0.0) {
            _rrSum = (rr * 4.0 + 0.5).toNumber();
            _rrN = 4;
        }
        closeEpoch(endSec);
    }

    (:debug)
    function cycleEstimate() as Float {
        return (_cycN > 0) ? _cycSum.toFloat() / _cycN : -1.0;
    }

    (:debug)
    function lightNow() as Number {
        return _lastLight;
    }

    // ---------------------------------------------------------------- helpers

    // Weighted average of the available signals as 0..100, optionally without one signal.
    private function score(c as Array<Float>, skip as Number) as Number {
        var w = 0.0;
        var sum = 0.0;
        for (var k = 0; k < COMP_COUNT; k++) {
            if (k != skip && c[k] >= 0.0) {
                w += _weights[k];
                sum += _weights[k] * c[k];
            }
        }
        return (w > 0.0) ? (100.0 * sum / w + 0.5).toNumber() : 0;
    }

    private function missingComps() as Array<Float> {
        var c = new Array<Float>[COMP_COUNT];
        for (var k = 0; k < COMP_COUNT; k++) {
            c[k] = -1.0;
        }
        return c;
    }

    private function copyComps(src as Array<Float>) as Array<Float> {
        var c = new Array<Float>[COMP_COUNT];
        for (var k = 0; k < COMP_COUNT; k++) {
            c[k] = src[k];
        }
        return c;
    }

    // Learned normal value and tonight's value: tonight counts more the more minutes it has.
    private function blend(tonight as Float, learned as Float, count as Number) as Float {
        if (tonight >= 0.0 && learned >= 0.0) {
            var wN = count / 60.0;
            if (wN > 1.0) {
                wN = 1.0;
            }
            return wN * tonight + (1.0 - wN) * learned;
        }
        return (tonight >= 0.0) ? tonight : learned;
    }

    private function motionScore(a as Float) as Float {
        if (a <= 0.0) {
            return 0.0;
        }
        return clamp01(Math.log(1.0 + a / 50.0, 10).toFloat() / 2.5);
    }

    private function sigmoid(x as Float) as Float {
        if (x > 10.0) {
            x = 10.0;
        } else if (x < -10.0) {
            x = -10.0;
        }
        return (1.0 / (1.0 + Math.pow(Math.E, -x))).toFloat();
    }

    private function zeros(n as Number) as Array<Number> {
        var a = new Array<Number>[n];
        for (var i = 0; i < n; i++) {
            a[i] = 0;
        }
        return a;
    }

    private function addBin(h as Array<Number>, idx as Number) as Number {
        if (idx < 0) {
            idx = 0;
        } else if (idx > 100) {
            idx = 100;
        }
        h[idx] += 1;
        return 1;
    }

    // Value below which p percent of the counted values lie.
    private function percentile(h as Array<Number>, total as Number, p as Number) as Number {
        var target = total * p / 100;
        var acc = 0;
        for (var i = 0; i < 101; i++) {
            acc += h[i];
            if (acc > target) {
                return i;
            }
        }
        return 100;
    }

    // Average change from minute to minute over the newest count values,
    // -1 if fewer than minN changes can be measured.
    private function meanAbsDelta(a as Array<Float>, count as Number, minN as Number) as Float {
        var sum = 0.0;
        var n = 0;
        for (var i = 0; i + 1 < count && i + 1 < a.size(); i++) {
            if (a[i] >= 0.0 && a[i + 1] >= 0.0) {
                sum += absf(a[i] - a[i + 1]);
                n += 1;
            }
        }
        return (n >= minN) ? sum / n : -1.0;
    }

    private function stdDev(a as Array<Float>) as Float {
        var sum = 0.0;
        var n = 0;
        for (var i = 0; i < a.size(); i++) {
            if (a[i] >= 0.0) {
                sum += a[i];
                n += 1;
            }
        }
        if (n < 3) {
            return -1.0;
        }
        var mean = sum / n;
        var v = 0.0;
        for (var i = 0; i < a.size(); i++) {
            if (a[i] >= 0.0) {
                var d = a[i] - mean;
                v += d * d;
            }
        }
        return Math.sqrt(v / n).toFloat();
    }

    private function clamp01(v as Float) as Float {
        if (v < 0.0) {
            return 0.0;
        }
        return (v > 1.0) ? 1.0 : v;
    }

    private function maxf(a as Float, b as Float) as Float {
        return (a > b) ? a : b;
    }

    private function absf(v as Float) as Float {
        return (v < 0.0) ? -v : v;
    }

    private function absn(v as Number) as Number {
        return (v < 0) ? -v : v;
    }
}
