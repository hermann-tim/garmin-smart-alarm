# SmartWake – notes for Claude

Smart alarm watch app (Connect IQ, Monkey C) for the **Garmin Forerunner 265** (`fr265`, API level 5.2.0, 416x416 AMOLED, touch + 5 buttons). Wakes the user in light sleep inside a wake window, at the latest at the wake time. Personal notes (status, results, preferences) are in `CLAUDE.local.md` (git-ignored) – read it first if it exists.

## Build, test, run

SDK path: first line of `%APPDATA%\Garmin\ConnectIQ\current-sdk.cfg` (SDK 9.3.0). Developer key: see `CLAUDE.local.md` (never in the repo).

```
monkeyc -f monkey.jungle -d fr265 -o bin/SmartWake.prg -y <key> -w                   # debug (simulator)
monkeyc -f monkey.jungle -d fr265 -o bin/SmartWake-release.prg -y <key> -w -r        # release (watch)
monkeyc -f monkey.jungle -d fr265 -o bin/SmartWake-test.prg -y <key> -w --unit-test  # unit tests
monkeydo bin/SmartWake-test.prg fr265 /t                                              # run tests (simulator must run)
```

- Start the simulator with `simulator.exe` from the SDK `bin` folder, then `monkeydo <prg> fr265`. One test only: `monkeydo <prg> fr265 /t <testName>`.
- Replay a real night through the current engine (simulator must be able to start): `tools/replay-night.ps1 -Files <BAK>,<TXT> [-Garmin <stages.txt>] -Key <key> [-Model "<MODEL line>"] [-DeadlineMinute n] [-Sweep]`. It writes the night into `logs/replay` (git-ignored) and builds with its own jungle. Garmin's stages per minute: text file `from to stage` (tief/leicht/rem/wach), minutes counted from the SmartWake start like the D lines.
- `tools/sim-screenshot.ps1 -Out x.png` captures the simulator window; `tools/sim-click.ps1 -Button enter|up|down|esc|menu|tap -X -Y` presses buttons/taps without moving the mouse (device image is drawn 1:1). Holding UP does not work via the tool; tap the lower screen area on the start screen to open the menu instead.
- Debug builds have extra menu items: Demo-Nacht (alarm in 2 min), Demo-Bericht, Demo-Lernen (`DebugTools.mc`).
- Type-check warnings at `-l 2/3` about Dictionary/Storage types are known formalities; the default level must stay warning-free.

## Code map (`source/`)

- `SmartWakeApp.mc` – entry, holds `settings`, `model`, `session`; resumes a stored night.
- `SleepEngine.mc` – sensors (accel 10 Hz, HR 1 Hz, beat intervals, live stress, respiration), 1-minute scoring of 7 signals (`COMP_*`), stage per minute (`classify`: deep = still + pulse even over 8 min, awake = longer movement, `STAGE_NODATA` = no pulse while still; REM counts as light), sleep onset + cycle tracking, wake decision (`decide`, body signals alone do not wake while lying completely still = REM), report, learning summary, night protocol (`writeLog`).
- `SleepModel.mc` – learning memory over 21 nights (EWMA baselines, outlier/short-night gate, feedback-learned weights and threshold shift).
- `NightSession.mc` – one night: tracking, alarm, snooze, dismiss, persistence.
- `AlarmPlayer.mc` – escalating alarm (Forerunner cannot change vibration strength, only length; tones are muted by the watch in sleep mode).
- Views: Home, Night (goes black after 20 s), Confirm, Alarm, Snooze, Feedback (fit/okay/tired), Summary (4 pages), Profile, Slider, TimePicker, SettingsMenu. `Ui.mc` = colors/drawing helpers, `TimeUtil.mc` = time helpers (`planTarget` = tonight's alarm from the weekly plan), `NightLog.mc` = temporary protocol, `DebugTools.mc` = demo items + night replay helpers, `Tests.mc` = unit tests.

## Gotchas (learned the hard way)

- **Input order on the watch:** behavior callbacks (`onSelect`, `onBack`, `onNextPage` ...) fire **before** `onKey`/`onTap`, and a screen tap also arrives as `onSelect`. Where a tap must not act like START, return `false` from the behavior and decide in `onKey(KEY_ENTER)` / `onTap`.
- Never record an activity at night – Garmin's own sleep tracking must keep working.
- Radial text: clockwise text grows outward from its radius, counter-clockwise inward (see `Ui.buttonHint`).
- `fitTextToArea` needs about `fontHeight * lines + 20` px height, otherwise it cuts to one line.
- `(:test)` is only for test functions (`function x(logger as Test.Logger) as Boolean`); test helpers are `(:debug)`.
- Modules cannot use `private`.
- `monkey.jungle` must keep `base.sourcePath = source`: the default builds every `.mc` file in the project, including the generated replay with private night data in `logs/replay`.
- In `ring()` the alarm starts first; report, learning and storage come after. Storage writes are wrapped in try/catch (a full storage throws), so they can never stop the alarm.
- Garmin's morning report (shown when the watch detects waking up) most likely closes the running app, so it should be off. `NightSession.shutdown()` (onStop) writes `STOP t=...` and the minutes measured so far into the night protocol; reopening after the wake time writes `LATE`. Relaunching via `monkeydo` kills the simulator app without onStop, so test the shutdown path with the unit test.
- The simulator uses one fixed UTC offset all year (no daylight saving time), so DST logic cannot be tested there.
- Windows PowerShell 5.1: no double quotes inside here-string commit messages; do not rewrite source files with `Set-Content` (adds a BOM) – use the edit tools.

## Watch transfer (USB, MTP device without drive letter)

Use `Shell.Application` COM: `NameSpace(17)` → "Forerunner 265" → Internal Storage → GARMIN → Apps. Copy `bin/SmartWake-release.prg` into `Apps` (keep this file name). Night protocol: `Apps/LOGS/SmartWake-release.TXT` (+ `.BAK`), only written if the file exists; Garmin caps it at about 5 KB. Decode with `tools/decode-nightlog.ps1 -Files <BAK>,<TXT> -CsvOut <csv>`.

## Privacy

Public repository. Never commit the developer key, `bin/`, or sleep data. Logs and personal notes live in the git-ignored `logs/` folder and `CLAUDE.local.md`. Push only when the user asks.
