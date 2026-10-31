import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Unit tests. Only built with "monkeyc --unit-test" and run with "monkeydo ... /t".

// ------------------------------------------------------------------ helpers

(:debug)
function makeNight(time as Number, minHr as Number, sleepMin as Number, early as Boolean, comps as Array<Float>) as Array<Numeric> {
    var s = new Array<Numeric>[NS_SIZE];
    s[NS_TIME] = time;
    s[NS_CYCLE] = 90.0;
    s[NS_MINHR] = minHr;
    s[NS_RMSSD] = 50.0;
    s[NS_STRESS] = 15.0;
    s[NS_RESP] = 14.0;
    s[NS_LIGHTHR] = 5.0;
    s[NS_EARLY] = early ? 1 : 0;
    s[NS_EARLYMIN] = early ? 12 : 0;
    s[NS_FEEL] = -1;
    s[NS_SLEEPMIN] = sleepMin;
    for (var k = 0; k < COMP_COUNT; k++) {
        s[NS_COMPS + k] = comps[k];
    }
    return s;
}

(:debug)
function freshModel() as SleepModel {
    var m = new SleepModel();
    m.persist = false;
    return m;
}

(:debug)
function flatComps() as Array<Float> {
    return [0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3] as Array<Float>;
}

(:debug)
function near(a as Float, b as Float, tol as Float) as Boolean {
    var d = a - b;
    return d < tol && d > -tol;
}

// Feeds minutes from..to-1 with the same movement and pulse (-1 = no pulse).
(:debug)
function feed(e as SleepEngine, t0 as Number, from as Number, to as Number, m as Float, hr as Number) as Void {
    for (var i = from; i < to; i++) {
        e.injectEpoch(t0 + (i + 1) * 60, m, hr, 50.0, 10, 14.0);
    }
}

// --------------------------------------------------------------- wake time

(:test)
function testNextOccurrenceLaterToday(logger as Test.Logger) as Boolean {
    var now = TimeUtil.nowSec();
    var m = TimeUtil.minuteOfDay(now);
    if (m > 1380) {
        logger.debug("Too close to midnight, skipped");
        return true;
    }
    var diff = TimeUtil.nextOccurrence(m + 30, now) - now;
    logger.debug("diff=" + diff);
    // the bug from the first test run: this used to be about 24 hours
    Test.assertMessage(diff > 28 * 60 && diff <= 30 * 60, "Uhrzeit heute muss heute sein");
    return true;
}

(:test)
function testNextOccurrencePassedIsTomorrow(logger as Test.Logger) as Boolean {
    var now = TimeUtil.nowSec();
    var m = TimeUtil.minuteOfDay(now);
    if (m < 60) {
        logger.debug("Too close to midnight, skipped");
        return true;
    }
    var diff = TimeUtil.nextOccurrence(m - 30, now) - now;
    logger.debug("diff=" + diff);
    Test.assertMessage(diff > 22 * 3600 && diff < 25 * 3600, "vergangene Uhrzeit muss morgen sein");
    return true;
}

// Second opinion: "Friday 08:00, Friday alarm 07:00, Saturday alarm 09:00" gave Friday 09:00.
(:test)
function testPlanTargetKeepsPlanDay(logger as Test.Logger) as Boolean {
    var now = TimeUtil.nowSec();
    var m = TimeUtil.minuteOfDay(now);
    if (m < 70 || m > 1300) {
        logger.debug("Too close to midnight, skipped");
        return true;
    }
    var day = TimeUtil.weekdayIndex(now);
    var plan = [420, 420, 420, 420, 420, 420, 420];
    plan[day] = m - 60;               // today's alarm was an hour ago
    plan[(day + 1) % 7] = m + 60;     // tomorrow's alarm is later in the day than now
    var t = TimeUtil.planTarget(plan, 0, now);
    logger.debug("hours ahead: " + (t[0] - now) / 3600.0);
    Test.assertMessage(t[0] - now > 23 * 3600, "Termin bleibt auf dem Tag aus dem Wochenplan");
    Test.assertEqual(t[1], (day + 1) % 7);
    // a change for tonight only moves the time on that same day
    var t2 = TimeUtil.planTarget(plan, -30, now);
    Test.assertEqual(t2[0], t[0] - 30 * 60);
    return true;
}

// Clock changes: 29 March and 25 October 2026. A time is never set earlier than asked
// (02:30 on the spring night does not exist and becomes 03:30, not 01:30).
// The simulator uses one fixed UTC offset all year, then this test only checks normal days.
(:test)
function testDaylightSavingDays(logger as Test.Logger) as Boolean {
    var days = [
        Gregorian.moment({:year => 2026, :month => 3, :day => 29, :hour => 12}).value(),
        Gregorian.moment({:year => 2026, :month => 10, :day => 25, :hour => 12}).value()
    ];
    var summer = Gregorian.info(Gregorian.moment({:year => 2026, :month => 7, :day => 1, :hour => 12}), Time.FORMAT_SHORT);
    var winter = Gregorian.info(Gregorian.moment({:year => 2026, :month => 1, :day => 1, :hour => 12}), Time.FORMAT_SHORT);
    if (summer.hour == winter.hour) {
        logger.debug("No daylight saving time here: only normal days are checked");
    }
    for (var d = 0; d < days.size(); d++) {
        var mid = TimeUtil.midnightOf(days[d]);
        for (var m = 0; m < 1440; m += 10) {
            var got = TimeUtil.minuteOfDay(TimeUtil.atMinuteOfDay(mid, m));
            Test.assertMessage(got == m || (got > m && got - m <= 60), "Tag " + d + ": " + m + " -> " + got);
        }
    }
    return true;
}

// ------------------------------------------------------------------ model

(:test)
function testModelLearnsFirstNight(logger as Test.Logger) as Boolean {
    var m = freshModel();
    Test.assertEqual(m.learnNight(makeNight(1000, 50, 400, true, flatComps())), LEARN_OK);
    Test.assertEqual(m.storedNights(), 1);
    Test.assertMessage(near(m.minHr, 50.0, 0.01), "erste Nacht setzt den Ruhepuls");
    Test.assertMessage(near(m.rmssd, 50.0, 0.01), "erste Nacht setzt die HRV");
    return true;
}

(:test)
function testModelSkipsShortNight(logger as Test.Logger) as Boolean {
    var m = freshModel();
    Test.assertEqual(m.learnNight(makeNight(1000, 50, 90, true, flatComps())), LEARN_SHORT);
    Test.assertEqual(m.storedNights(), 0);
    return true;
}

(:test)
function testModelSkipsOutlier(logger as Test.Logger) as Boolean {
    var m = freshModel();
    for (var i = 0; i < 6; i++) {
        m.learnNight(makeNight(1000 + i, 50 + (i % 2), 420, true, flatComps()));
    }
    var before = m.minHr;
    Test.assertEqual(m.learnNight(makeNight(2000, 62, 420, true, flatComps())), LEARN_OUTLIER);
    Test.assertMessage(near(m.minHr, before, 0.001), "Ausreisser darf nichts veraendern");
    Test.assertEqual(m.storedNights(), 6);
    return true;
}

(:test)
function testModelKeeps21Nights(logger as Test.Logger) as Boolean {
    var m = freshModel();
    for (var i = 0; i < 25; i++) {
        m.learnNight(makeNight(1000 + i, 50, 420, true, flatComps()));
    }
    Test.assertEqual(m.storedNights(), 21);
    Test.assertEqual(m.nights, 25);
    return true;
}

(:test)
function testModelBaselineFollowsRecentNights(logger as Test.Logger) as Boolean {
    var m = freshModel();
    for (var i = 0; i < 10; i++) {
        m.learnNight(makeNight(1000 + i, 52, 420, true, flatComps()));
    }
    for (var i = 0; i < 10; i++) {
        m.learnNight(makeNight(2000 + i, 48, 420, true, flatComps()));
    }
    logger.debug("minHr=" + m.minHr);
    // fitter after training: the baseline moves towards the recent 48 bpm
    Test.assertMessage(m.minHr < 49.0, "Ruhepuls folgt den letzten Naechten");
    return true;
}

(:test)
function testFeedbackFitStrengthensSignal(logger as Test.Logger) as Boolean {
    var m = freshModel();
    var comps = [0.9, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2] as Array<Float>;
    m.learnNight(makeNight(1000, 50, 420, true, comps));
    var before = m.weights[COMP_MOVE];
    m.applyFeedback(1000, FEEL_FIT, false);
    logger.debug("move weight " + before + " -> " + m.weights[COMP_MOVE]);
    Test.assertMessage(m.weights[COMP_MOVE] > before, "gutes Wecken staerkt das ausschlaggebende Signal");
    var sum = 0.0;
    for (var k = 0; k < COMP_COUNT; k++) {
        sum += m.weights[k];
    }
    Test.assertMessage(near(sum, 1.0, 0.001), "Gewichte ergeben zusammen 100 %");
    Test.assertEqual(m.feelCounts()[FEEL_FIT], 1);
    return true;
}

(:test)
function testFeedbackTiredWeakensSignal(logger as Test.Logger) as Boolean {
    var m = freshModel();
    var comps = [0.9, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2] as Array<Float>;
    m.learnNight(makeNight(1000, 50, 420, true, comps));
    var before = m.weights[COMP_MOVE];
    m.applyFeedback(1000, FEEL_TIRED, false);
    Test.assertMessage(m.weights[COMP_MOVE] < before, "schlechtes Wecken schwaecht das Signal");
    Test.assertMessage(near(m.shift, 3.0, 0.001), "frueh geweckt und muede: strenger");
    return true;
}

(:test)
function testFeedbackDeadlineTiredLoosens(logger as Test.Logger) as Boolean {
    var m = freshModel();
    m.learnNight(makeNight(1000, 50, 420, false, flatComps()));
    var before = m.weights[COMP_MOVE];
    m.applyFeedback(1000, FEEL_TIRED, false);
    Test.assertMessage(near(m.shift, -3.0, 0.001), "zur Weckzeit geweckt und muede: lockerer");
    Test.assertMessage(near(m.weights[COMP_MOVE], before, 0.0001), "Gewichte nur bei Frueh-Wecken");
    return true;
}

(:test)
function testFeedbackShiftIsLimited(logger as Test.Logger) as Boolean {
    var m = freshModel();
    for (var i = 0; i < 10; i++) {
        m.learnNight(makeNight(1000 + i, 50, 420, true, flatComps()));
        m.applyFeedback(1000 + i, FEEL_TIRED, false);
    }
    Test.assertMessage(near(m.shift, 12.0, 0.001), "Anpassung ist begrenzt");
    return true;
}

// Second opinion: every "fit" made the wake decision looser, also when it was right.
(:test)
function testFeedbackFitDoesNotLoosen(logger as Test.Logger) as Boolean {
    var m = freshModel();
    for (var i = 0; i < 10; i++) {
        m.learnNight(makeNight(1000 + i, 50, 420, true, flatComps()));
        m.applyFeedback(1000 + i, FEEL_FIT, false);
    }
    Test.assertMessage(near(m.shift, 0.0, 0.001), "gute Morgen machen das Wecken nicht immer lockerer");
    // after a tired morning, good mornings slowly take the extra strictness back
    m.learnNight(makeNight(2000, 50, 420, true, flatComps()));
    m.applyFeedback(2000, FEEL_TIRED, false);
    m.learnNight(makeNight(2001, 50, 420, true, flatComps()));
    m.applyFeedback(2001, FEEL_FIT, false);
    Test.assertMessage(near(m.shift, 2.5, 0.001), "Strenge baut sich langsam ab");
    return true;
}

(:test)
function testFeedbackUnknownNightIgnored(logger as Test.Logger) as Boolean {
    var m = freshModel();
    Test.assertMessage(!m.applyFeedback(12345, FEEL_FIT, false), "unbekannte Nacht wird ignoriert");
    return true;
}

// ----------------------------------------------------------- night protocol

(:test)
function testNightLogEncoding(logger as Test.Logger) as Boolean {
    Test.assertEqual(NightLog.enc(0), "0");
    Test.assertEqual(NightLog.enc(10), "A");
    Test.assertEqual(NightLog.enc(36), "a");
    Test.assertEqual(NightLog.enc(63), "_");
    Test.assertEqual(NightLog.enc(99), "_");
    Test.assertEqual(NightLog.enc(-1), ".");
    return true;
}

// Writes a full 8-hour made-up night into the protocol (must not crash or be too slow).
(:test)
function testNightLogWritesFullNight(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 450 * 60, t0 + 480 * 60, 3);
    for (var i = 0; i < 480; i++) {
        var inCycle = (i - 15) % 90;
        var light = (i >= 15 && inCycle < 8);
        var m = 0.0;
        if (i < 12) {
            m = 0.6;
        } else if (light) {
            m = (inCycle == 0) ? 0.6 : 0.25;
        }
        e.injectEpoch(t0 + (i + 1) * 60, m, light ? 57 : 50, light ? 35.0 : 55.0, light ? 25 : 10, 14.0);
    }
    e.writeLog();
    return true;
}

// ----------------------------------------------------------------- engine

// A made-up night: awake for 12 minutes, then sleep with a short light phase
// at the start of every 90-minute cycle (more movement, higher pulse, lower HRV).
// The wake window covers the last 30 minutes and contains such a light phase.
(:test)
function testEngineWakesInLightPhase(logger as Test.Logger) as Boolean {
    var model = freshModel();
    var e = new SleepEngine(model);
    var t0 = 1700000000;
    e.setup(t0, t0 + 370 * 60, t0 + 400 * 60, 3);
    var wokeAt = -1;
    for (var i = 0; i < 400 && wokeAt < 0; i++) {
        var inCycle = (i - 15) % 90;
        var light = (i >= 15 && inCycle < 8);
        var m = 0.0;
        if (i < 12) {
            m = 0.6;
        } else if (light) {
            m = (inCycle == 0) ? 0.6 : 0.25;
        }
        e.injectEpoch(t0 + (i + 1) * 60, m, light ? 57 : 50, light ? 35.0 : 55.0, light ? 25 : 10, 14.0);
        if (e.pendingKind() >= 0) {
            wokeAt = i;
        }
    }
    logger.debug("woke at minute " + wokeAt + " (" + e.pendingText() + "), cycle " + e.cycleEstimate());
    Test.assertMessage(wokeAt >= 370, "nie vor dem Weckfenster wecken");
    Test.assertMessage(wokeAt >= 374 && wokeAt <= 380, "in der leichten Phase wecken");
    Test.assertMessage(e.cycleEstimate() > 80.0 && e.cycleEstimate() < 95.0, "Zykluslaenge erkannt");

    // the night can be learned
    var s = e.learningSummary(t0 + (wokeAt + 1) * 60, e.pendingKind());
    logger.debug("minHr " + s[NS_MINHR] + ", sleep " + s[NS_SLEEPMIN] + " min, early " + s[NS_EARLY]);
    Test.assertEqual(s[NS_EARLY], 1);
    Test.assertMessage(s[NS_SLEEPMIN] >= 300, "Schlafdauer erkannt");
    Test.assertEqual(model.learnNight(s), LEARN_OK);
    Test.assertMessage(near(model.minHr, 50.0, 0.6), "Ruhepuls gelernt");
    return true;
}

// Deep, calm sleep through the whole window: SmartWake waits for the wake time
// (or wakes at most a few minutes early in the last 5 minutes).
(:test)
function testEngineWaitsInDeepSleep(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 370 * 60, t0 + 400 * 60, 3);
    var wokeAt = -1;
    for (var i = 0; i < 400 && wokeAt < 0; i++) {
        var inCycle = (i - 15) % 90;
        var light = (i >= 15 && i < 300 && inCycle < 8);
        var m = 0.0;
        if (i < 12) {
            m = 0.6;
        } else if (light) {
            m = (inCycle == 0) ? 0.6 : 0.25;
        }
        e.injectEpoch(t0 + (i + 1) * 60, m, light ? 57 : 50, light ? 35.0 : 55.0, light ? 25 : 10, 14.0);
        if (e.pendingKind() >= 0) {
            wokeAt = i;
        }
    }
    logger.debug("woke at minute " + wokeAt);
    Test.assertMessage(wokeAt < 0 || wokeAt >= 395, "im Tiefschlaf nicht frueh wecken");
    return true;
}

// ------------------------------------------------------ stages (phase fix)

// Both opinions: minutes without a pulse used to count as deep sleep.
(:test)
function testEngineNoPulseIsNotDeep(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 60 * 60, t0 + 95 * 60, 3);
    feed(e, t0, 0, 60, 0.0, 52);          // an hour of calm sleep with an even pulse
    Test.assertEqual(e.stageNow, STAGE_DEEP);
    feed(e, t0, 60, 90, 0.0, -1);         // in the wake window the pulse is lost, nothing moves
    Test.assertEqual(e.stageNow, STAGE_NODATA);
    Test.assertMessage(e.pendingKind() < 0, "ohne Messwerte nicht frueh wecken");
    var r = e.report(t0 + 90 * 60, REASON_CANCEL, "Test");
    Test.assertEqual(r.get("nd"), 30);
    Test.assertEqual(r.get("sl"), 60 * 60);
    return true;
}

// Single turns in bed used to count as awake (far more awake time than Garmin showed).
(:test)
function testEngineAwakeNeedsLongerMovement(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 600 * 60, t0 + 630 * 60, 3);
    feed(e, t0, 0, 60, 0.0, 52);
    e.injectEpoch(t0 + 61 * 60, 1.0, 62, 40.0, 20, 15.0);     // one turn with a pulse rise
    Test.assertEqual(e.stageNow, STAGE_LIGHT);
    feed(e, t0, 61, 70, 0.0, 52);
    e.injectEpoch(t0 + 71 * 60, 1.0, 66, 40.0, 20, 15.0);     // moving for 2 minutes, pulse +14
    e.injectEpoch(t0 + 72 * 60, 1.0, 66, 40.0, 20, 15.0);
    Test.assertEqual(e.stageNow, STAGE_WAKE);
    feed(e, t0, 72, 90, 0.0, 52);
    for (var i = 90; i < 94; i++) {                             // restless for 4 minutes
        e.injectEpoch(t0 + (i + 1) * 60, 0.8, 54, 40.0, 20, 15.0);
    }
    Test.assertEqual(e.stageNow, STAGE_WAKE);
    return true;
}

// Compared with Garmin's stages: deep sleep came with a very even pulse, still minutes
// with a jumping pulse were light sleep or REM.
(:test)
function testEngineDeepNeedsEvenPulse(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 600 * 60, t0 + 630 * 60, 3);
    for (var i = 0; i < 60; i++) {
        e.injectEpoch(t0 + (i + 1) * 60, 0.0, (i % 2 == 0) ? 52 : 55, 50.0, 10, 14.0);
    }
    Test.assertEqual(e.stageNow, STAGE_LIGHT);
    feed(e, t0, 60, 75, 0.0, 53);           // the pulse settles: deep after a few minutes
    Test.assertEqual(e.stageNow, STAGE_DEEP);
    return true;
}

// Second opinion (REM trap): lying completely still with an active pulse is dreaming,
// body signals alone must not wake. A small movement with the same signals may.
(:test)
function testEngineStillRaisedPulseDoesNotWake(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 120 * 60, t0 + 150 * 60, 3);
    for (var i = 0; i < 120; i++) {
        e.injectEpoch(t0 + (i + 1) * 60, (i % 15 == 0) ? 0.3 : 0.0, (i % 15 < 3) ? 55 : 52, 50.0, 10, 14.0);
    }
    for (var i = 120; i < 140; i++) {
        e.injectEpoch(t0 + (i + 1) * 60, 0.0, 62 + (i % 3), 25.0, 35, (i % 2 == 0) ? 12.0 : 18.0);
    }
    logger.debug("score while dreaming: " + e.lightNow());
    Test.assertMessage(e.lightNow() >= 40, "Testdaten muessen nach Leichtschlaf aussehen");
    Test.assertMessage(e.pendingKind() < 0, "still liegen mit hohem Puls (REM) weckt nicht");
    e.injectEpoch(t0 + 141 * 60, 0.3, 64, 25.0, 35, 15.0);
    Test.assertEqual(e.pendingKind(), REASON_LIGHT);
    return true;
}

// Second opinion: the learned strictness did not apply to the movement trigger.
(:test)
function testMovementLimitFollowsLearning(logger as Test.Logger) as Boolean {
    var t0 = 1700000000;
    var kinds = [0, 0];
    for (var k = 0; k < 2; k++) {
        var model = freshModel();
        model.shift = (k == 0) ? 0.0 : 12.0;
        var e = new SleepEngine(model);
        e.setup(t0, t0 + 40 * 60, t0 + 70 * 60, 3);
        feed(e, t0, 0, 45, 0.0, 52);
        e.injectEpoch(t0 + 46 * 60, 0.5, 52, 50.0, 10, 14.0);   // a medium movement in the window
        kinds[k] = e.pendingKind();
    }
    Test.assertEqual(kinds[0], REASON_MOVEMENT);
    Test.assertMessage(kinds[1] < 0, "nach muede-Antworten braucht es deutlichere Bewegung");
    return true;
}

// Second opinion: the per-minute light scores and pulses were stored but never shown.
(:test)
function testEngineReportKeepsOnlyStages(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 600 * 60, t0 + 630 * 60, 3);
    feed(e, t0, 0, 100, 0.0, 52);
    var r = e.report(t0 + 100 * 60, REASON_CANCEL, "Test");
    Test.assertMessage(r.get("L") == null && r.get("H") == null, "keine ungenutzten Minutenlisten");
    var s = r.get("S");
    Test.assertMessage(s instanceof Array && s.size() == 100, "Schlafphasen bleiben im Bericht");
    return true;
}

// ---------------------------------------------------------------- session

// The watch may close the app during the night (e.g. Garmin's morning report). Closing
// must keep the measured minutes in the protocol and must not crash.
(:test)
function testShutdownKeepsNightData(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    var t0 = 1700000000;
    e.setup(t0, t0 + 600 * 60, t0 + 630 * 60, 3);
    feed(e, t0, 0, 90, 0.0, 52);
    var s = new NightSession(new AppSettings());
    s.engine = e;
    s.shutdown();
    Test.assertEqual(e.epochs, 90);
    return true;
}

// The faster protocol lines (character array) must be exactly the same as before,
// including missing values, and a 15-hour night gives 15 lines.
(:test)
function testLogLineSameAsBefore(logger as Test.Logger) as Boolean {
    var e = new SleepEngine(freshModel());
    e.setup(1700000000, 1700000000 + 600 * 60, 1700000000 + 630 * 60, 3);
    e.fillDemoLog(130);
    Test.assertEqual(e.logLineCount(), 3);
    for (var k = 0; k < 3; k++) {
        Test.assertEqual(e.logLine(k), e.logLineOld(k));
    }
    Test.assertEqual(e.logLine(2).length(), "D120:".length() + 10 * 7);
    e.fillDemoLog(900);
    Test.assertEqual(e.logLineCount(), 15);
    Test.assertEqual(e.logLine(14), e.logLineOld(14));
    return true;
}

// First opinion: an alarm that rings again after snoozing was thrown away after a restart.
(:test)
function testRestoreAlarmAfterSnooze(logger as Test.Logger) as Boolean {
    var now = TimeUtil.nowSec();
    var d = {
        "ph" => PHASE_ALARM, "st" => now - 8 * 3600, "ws" => now - 71 * 60, "dl" => now - 41 * 60,
        "aa" => now - 41 * 60, "ra" => now - 60, "su" => now - 60, "sc" => 2,
        "rk" => REASON_DEADLINE, "rs" => "Weckzeit erreicht"
    };
    Test.assertMessage(new NightSession(new AppSettings()).restore(d, now), "Alarm nach Schlummern bleibt erhalten");
    // an alarm that started 41 minutes ago and was never snoozed is over
    d.put("ra", now - 41 * 60);
    Test.assertMessage(!new NightSession(new AppSettings()).restore(d, now), "alter Alarm wird verworfen");
    return true;
}
