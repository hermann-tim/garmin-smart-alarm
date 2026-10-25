# SmartWake

Smarter Wecker für die **Garmin Forerunner 265**. SmartWake weckt dich in einem Zeitfenster vor deiner Weckzeit, sobald du leicht schläfst, und spätestens zur Weckzeit.

Gebaut mit Connect IQ (Monkey C).

## So funktioniert's

1. Abends die App öffnen und **START** drücken. Die Uhr bleibt am Handgelenk.
2. Die App misst die ganze Nacht mit, was die Uhr Apps zur Verfügung stellt:
   - **Bewegung** (Beschleunigungssensor, 10 Messungen pro Sekunde)
   - **Puls** im Vergleich zu deinem Ruhepuls dieser Nacht
   - **Pulsruhe** (wie stark der Puls von Minute zu Minute schwankt)
   - **HRV** (Abstände zwischen einzelnen Herzschlägen)
   - **Garmins Stress-Wert** (live, ebenfalls aus der HRV berechnet)
   - **Atemfrequenz** und wie gleichmäßig sie ist
   - **dein Schlafzyklus:** wann der nächste Wechsel zwischen zwei Zyklen fällig ist
3. Jede Minute bewertet sie daraus, wie leicht du gerade schläfst. Alle Werte werden mit **deinen eigenen Normalwerten** verglichen, nicht mit festen Grenzen.
4. Im **Weckfenster** (z. B. 30 Minuten vor der Weckzeit) weckt sie dich, sobald es nach leichtem Schlaf aussieht. Gegen Ende des Fensters reicht ein schwächeres Signal. Spätestens zur Weckzeit klingelt es immer.
5. Der Alarm startet sanft und wird stärker: längere Vibrationen, kürzere Pausen und auf Wunsch Töne.
6. Nach dem Ausschalten fragt die App: **Wie fühlst du dich?** (fit / okay / müde).
7. Morgens zeigt ein Bericht, wann und warum du geweckt wurdest, deinen Schlafverlauf, Messwerte und den Ablauf der Nacht.

## Lernt mit jeder Nacht

SmartWake merkt sich die **letzten 21 Nächte** als kurze Zusammenfassungen (keine Rohdaten, zusammen nur wenige Kilobyte):

- **Deine Normalwerte:** Ruhepuls, HRV, Stress, Atmung, typischer Pulsanstieg im leichten Schlaf und deine persönliche Zykluslänge. Neue Nächte zählen am meisten, die ersten Nächte besonders stark. So ist das Profil nach etwa 5 Nächten persönlich.
- **Gewichtung der Signale:** Warst du nach einem frühen Wecken fit, zählen die Signale, die den Ausschlag gaben, künftig mehr. Warst du müde, zählen sie weniger.
- **Strenge:** Früh geweckt und müde: SmartWake wird vorsichtiger. Zur Weckzeit geweckt und müde: SmartWake weckt eher früher. Ohne Antwort zählt häufiges Schlummern als Hinweis.
- **Schutz vor Ausreißern:** Nächte mit stark erhöhtem Ruhepuls (Alkohol, Krankheit, spätes Training) werden nicht gelernt. Ebenso Nächte unter 3 Stunden (Mittagsschlaf, Tests).

Was gelernt wurde, zeigt **Menü → Schlafprofil**. Mit **Lernen zurücksetzen** fängt das Profil von vorne an.

Garmins eigene Schlafphasen sind für Apps nicht zugänglich. SmartWake schätzt die Phasen deshalb selbst. Das ist eine Schätzung, keine medizinische Messung.

## Bedienung

| Bildschirm | Tasten |
|---|---|
| Start | START = Nacht starten, UP/DOWN = Weckzeit nur für heute ±5 min, UP halten = Menü |
| Nacht | BACK = beenden (mit Rückfrage), alles andere wird ignoriert |
| Alarm | START = aus, jede andere Taste = schlummern. Tippen auf das Display wird ignoriert. |
| Bericht | UP/DOWN = Seiten blättern, BACK = zurück |

## Einstellungen

- **Wochenplan:** Weckzeit pro Wochentag, Mo-Fr oder Sa-So auf einmal
- **Weckfenster:** 10 bis 60 Minuten in 5-Minuten-Schritten
- **Schlummern:** an/aus, Dauer (1-20 min), maximale Anzahl
- **Vibration:** Sanft / Normal / Intensiv (Start des Alarms)
- **Ton:** zusätzlich piepen, ab 30 Sekunden Alarm
- **Empfindlichkeit:** 1 (nur klare Signale) bis 5 (weckt am frühesten)
- **Wecker testen:** spielt den Alarm im Schnelldurchlauf ab

## Auf die Uhr bringen

1. Projekt in VS Code öffnen (Connect IQ SDK und Monkey-C-Erweiterung installiert).
2. `Strg+Shift+P` → **Monkey C: Build for Device** → `fr265`.
3. Uhr per USB anschließen und die erzeugte `.prg`-Datei in den Ordner `GARMIN/APPS` kopieren.
4. Uhr abstecken. SmartWake erscheint in der App-Liste.

## Wichtig in der Testphase

- Stell dir zusätzlich den **normalen Garmin-Wecker** ein paar Minuten nach deiner Weckzeit, bis du der App vertraust.
- Prüfe morgens in Garmin Connect, ob Garmins Schlafdaten trotzdem vollständig sind. SmartWake zeichnet keine Aktivität auf, damit das Schlaftracking normal weiterläuft.
- Teste **Wecker testen** einmal mit eingeschaltetem Schlafmodus der Uhr, um sicherzugehen, dass Vibration und Ton durchkommen.

## Projektaufbau

```
source/
  SmartWakeApp.mc     Einstieg, setzt eine laufende Nacht nach einem Neustart fort
  SleepEngine.mc      Sensoren auslesen, Schlaf bewerten, Zyklen erkennen, Weckzeitpunkt finden
  SleepModel.mc       Lern-Gedächtnis über 21 Nächte: Normalwerte, Gewichte, Strenge
  NightSession.mc     Ablauf einer Nacht: Messen, Alarm, Schlummern, Bericht
  AlarmPlayer.mc      Ansteigender Alarm aus Vibration, Licht und Ton
  AppSettings.mc      Einstellungen und Wochenplan
  FeedbackView.mc     Morgenfrage "Wie fühlst du dich?" und Lernschritt
  ProfileView.mc      Schlafprofil: was gelernt wurde
  *View.mc            weitere Bildschirme (Start, Nacht, Alarm, Schlummern, Bericht, Regler ...)
  SettingsMenu.mc     Einstellungsmenü
  Ui.mc, TimeUtil.mc  Farben, Zeichen-Helfer, Zeitfunktionen
  DebugTools.mc       Demo-Nacht, Demo-Bericht, Demo-Lernen (nur in Debug-Builds)
  Tests.mc            Unit-Tests für Zeitlogik, Lernen und Schlaf-Engine
```

## Tests ausführen

```
monkeyc -f monkey.jungle -d fr265 -o bin/SmartWake-test.prg -y <developer_key> --unit-test
monkeydo bin/SmartWake-test.prg fr265 /t
```

Der Simulator muss dafür laufen.
