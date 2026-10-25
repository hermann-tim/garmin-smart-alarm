import Toybox.Lang;
import Toybox.Test;

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

(:test)
function testFeedbackUnknownNightIgnored(logger as Test.Logger) as Boolean {
    var m = freshModel();
    Test.assertMessage(!m.applyFeedback(12345, FEEL_FIT, false), "unbekannte Nacht wird ignoriert");
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
        e.injectEpoch(t0 + (i + 1) * 60, m, light ? 57 : 50, light ? 35.0 : 55.0, light ? 25 : 10, 14);
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
        e.injectEpoch(t0 + (i + 1) * 60, m, light ? 57 : 50, light ? 35.0 : 55.0, light ? 25 : 10, 14);
        if (e.pendingKind() >= 0) {
            wokeAt = i;
        }
    }
    logger.debug("woke at minute " + wokeAt);
    Test.assertMessage(wokeAt < 0 || wokeAt >= 395, "im Tiefschlaf nicht frueh wecken");
    return true;
}
