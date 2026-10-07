# Insulink Redesign – Design-Spezifikation (Übersicht)

Ziel: Neues visuelles Design für die Flutter-App. **Funktionalität bleibt unverändert** – nur Darstellung, Layout und Theme ändern sich. Referenz-Mockup: `design/reference/Main.dc.html` (HTML-Prototyp, alle Maße/Farben dort sind maßgeblich) plus Screenshots in `design/screens/`.

## Prinzipien

- Ruhig, modern, clean. Farbe nur, wenn sie etwas bedeutet (Zielbereich, hoch, niedrig).
- Glukosebereich (Wert, Graph, Zeit im Zielbereich) steht offen ohne Karte. Geräte und Tageswerte sitzen in ruhigen Panels.
- Keine bunten Rahmen, keine Verläufe als Deko, keine Schatten auf Karten (nur Navigationsleiste).
- Touch-Targets mindestens 44 × 44 px. Jede Icon-Schaltfläche hat ein `Semantics`-Label.

## Farben (Design-Tokens)

| Token | Dark | Light | Verwendung |
|---|---|---|---|
| ground | `#0F1B26` | `#EDF2F6` | Seitenhintergrund |
| panel | `#152432` | `#FFFFFF` | Panels, Kacheln, Header-Buttons |
| line | `#26394B` | `#D3DEE7` | Trennlinien, leere Segmente |
| border | `rgba(234,241,246,.07)` | `rgba(15,27,38,.06)` | feiner 1-px-Rand an Kacheln/Buttons |
| text | `#EAF1F6` | `#0F1B26` | Primärtext, Glukosewert, Trendpfeil |
| muted | `#97A9BA` | `#4D6175` | Labels, Einheiten, Achsen |
| accent | `#9DAEFF` | `#3346C8` | Bolus-Button, Icons, Fortschritt |
| onAccent | `#0F1B26` | `#FFFFFF` | Inhalt auf accent |
| accentSoft | `rgba(157,174,255,.16)` | `rgba(51,70,200,.10)` | aktiver Tab, Profil-Button, Fortschrittsfläche |
| accentText | `#C4CEFF` | `#2A3AA8` | Text auf accentSoft |
| range | `#7CCB8F` | `#3B8A4F` | Zielbereich 70–180 |
| high | `#F4B740` | `#A86A00` | > 180 |
| low | `#FF6B7F` | `#C8293F` | < 70 |
| lowSoft | `rgba(255,107,127,.14)` | `rgba(200,41,63,.10)` | Warnbanner |
| dock | `#1B2B3B` | `#FFFFFF` | Navigationskapsel |

Umsetzung: als `ThemeExtension<InsulinkColors>` mit `dark`/`light`-Instanz, nicht als verstreute `Color(...)`-Literale.

## Typografie

- Schrift: **Atkinson Hyperlegible Next** (Google Fonts, Gewichte 400/600/700/800), über `google_fonts` oder als Asset gebündelt.
- Zahlen immer tabellarisch: `FontFeature.tabularFigures()`.

| Rolle | Größe | Gewicht | Sonstiges |
|---|---|---|---|
| Glukosewert | 124 | 800 | letterSpacing −0.055em, height 0.8 |
| Abschnittstitel (Glukose, Geräte, Heute) | 18 | 700 | |
| Kachelwert | 30 | 800 | letterSpacing −0.03em |
| Zeit im Zielbereich (87 %) | 30 | 800 | |
| Body / Zeilen | 15 | 600–700 | |
| Labels | 13–14 | 400 | Farbe muted |
| Achsen, Skala | 11–13 | 400 | Farbe muted |

Zahlen deutsch formatieren: `4.208`, `74,4`, `0,40 E/h`, `87 %` (mit Leerzeichen).

## Layout (Phone, Breite 390)

- Seitenrand 20 px. Panels 12 px Rand und 16 px Innenabstand.
- Radien: Panels 20, Kacheln 22, Header-Buttons/Pills 22 (rund), Navigationskapsel 31.
- Reihenfolge von oben: Header → Glukosewert → Skala → Graph → Zeit im Zielbereich → Geräte → Heute. Darüber schwebt die Navigation.

## Komponenten

### Header
- Links: Pille (Höhe 44, panel + border): Fortschrittsring 26 px (accent auf line) + Zeit „2:35“ (15/600, muted).
- Rechts: drei **eigenständige** runde Buttons, 44 px, Abstand 8 px:
  1. Pod-Status (Box-Icon), 2. Verbindung (Stecker-Icon): panel + border, Icon 20 px in text. Statuspunkt 10 px oben rechts (range = verbunden), mit 2,5-px-Ring in ground.
  3. Profil: accentSoft-Hintergrund, Initiale 17/800 in accentText.

### Glukosewert
- Zeile: Wert (124/800) + Trendpfeil direkt daneben, **gleiche Farbe wie der Wert** (text, bei < 70 low). Pfeil ca. 84 px, Strich ca. 3/20 der Box, runde Enden. Rotation nach Trend: 0° stabil, ±45° steigend/fallend, ±90° stark.
- Darunter eine Zeile: links „mg/dL“, rechts „Stabil +0,3 pro Min.“ (Trendwort fett in Wertfarbe, Rest muted).

### Bereichsskala
- Durchgehender Balken (5 px, Radius 3), drei Segmente mit 4 px Abstand: low (40–70), range (70–180), high (180–250), proportional.
- Marker: Knopf 22 px in text mit 4-px-Ring in ground, darin 10-px-Kern in range (bzw. low). Position = (Wert − 40) / 210.
- Beschriftung „70“ und „180“ darunter (11, muted).

### Glukose-Graph (24 h)
- Kopfzeile als tappbare Zeile: „Glukose“ links, „24 Std. ›“ rechts (muted).
- Linie 2,5 px, eingefärbt nach Bereich (range/high/low). Grenzen 70 und 180 als gestrichelte 1-px-Linien in low/high (Opazität 0,7). Kein Flächenfüller, keine Grundlinie.
- Endpunkt: Punkt 6 px mit 3-px-Ring in ground. X-Achse: 4:00, 10:00, 16:00, „jetzt“.

### Zeit im Zielbereich
- Zeile: „87 %“ (30/800) + „im Zielbereich, 24 Std.“ (14, muted). Rechts: zwei kleine Werte mit Farbpunkt 8 px (low 9 %, high 4 %).
- Darunter: Balken 6 px, drei Segmente (low/range/high), 3 px Abstand.

### Geräte (Panel)
- Titel „Geräte“ über dem Panel.
- Sensor: Zeile „Sensor“ / „noch 6 Tage“, darunter 10 Segmente (6 px hoch, 4 px Abstand), accent = verbleibend, line = verbraucht.
- Zweispaltig darunter: Pumpe („noch 3 Tage“, 3 Segmente) | Reservoir („47,6 E“, Füllbalken).
- Trennlinie, dann tappbare Zeile: Statuspunkt 8 px (range) · „Automatische Abgabe aktiv“ · „0,40 E/h“ · Chevron.

### Heute (Kacheln)
- Kopfzeile „Heute“ + zwei Icon-Buttons rechts (Ansicht wechseln, Kacheln anpassen) – bestehende Funktionen.
- Raster 2 Spalten, 10 px Abstand. Kachel: Höhe min. 92, Radius 22, panel + 1-px-border.
- Inhalt: Icon 26 px (accent) links, rechts Label (13, muted) über Wert (30/800) + Einheit (14/600, muted).
- Fortschritt (z. B. Schritte): Fläche von links in `rgba(157,174,255,.13)`, **ohne Kante/Linie** (eine Linie läuft sonst durch den Text). Icon und Text liegen über der Fläche.
- Reihenfolge: Schritte, Gewicht, Herzfrequenz, Schlaf, Bolus, Trinken.

## Gemeinsame Muster für alle weiteren Screens

Referenz: `design/reference/*.dc.html` (Bolus, Sport, Ernaehrung, Sensor, Pumpe, Health) und `insulink-kit.css` (alle Klassen und Werte).

- **Abschnittskopf:** Titel 18/700 links, optionale Icon-Buttons rechts (44 px, ohne Hintergrund, Icon muted). Abstand 28 px nach oben. Keine Großbuchstaben-Überschriften (statt „STATUS“ → „Status“).
- **Listen:** Einträge stehen **in einem gemeinsamen Panel** (Radius 20) und sind durch 1-px-Linien in line getrennt, nicht als einzelne Karten. Zeile min. 68 px: Icon-Kreis 40 px (accent auf 12 % accent) · Titel 16/700 + Untertitel 14 muted · rechts Meta (Datum 13 muted über Uhrzeit 15/700). Daten relativ: „Heute“, „Gestern“, sonst „So., 4. Okt.“.
- **„Mehr anzeigen“:** Textbutton zentriert, 15/700 in accent.
- **Schlüssel/Wert-Tabellen:** Panel mit Zeilen 14 px Innenabstand, Schlüssel muted links, Wert 700 rechts, Trennlinien dazwischen.
- **Detailseiten (Sensor, Pumpe, Google Health):** Kopfzeile mit Zurück-Pfeil, Titel 22/700, Aktions-Icons rechts. Darunter Gerätekopf **ohne Karte**: Icon-Kreis 56 px, Name 24/800, Statuszeile mit 8-px-Punkt (range = ok, high = Hinweis). Danach Fortschrittsbalken mit Label links und Wert rechts.
- **Gefährliche Aktionen** (Sensor stoppen, Pod deaktivieren, Pod vergessen, Trennen) stehen **unten** in einem eigenen Panel als Listenzeilen mit rotem Icon-Kreis und rotem Text, nicht als umrandete Buttons oben.
- **Buttons:** Höhe 54, Radius 27, 16/700. Primär = accent mit onAccent. Gefahr = `rgba(255,107,127,.14)` mit Text in low (z. B. „Abgabe stoppen“). Keine Outline-Buttons.
- **Hinweis-Banner** (z. B. temporäre Basalrate): Fläche `rgba(244,183,64,.12)`, Icon + Text in high, rechts kleiner Pill-Button („Beenden“).
- **Segment-Schalter** (Automatische Abgabe Aus/Aktiv): Track in ground, aktive Option accent mit onAccent, Höhe 42.
- **Eingabefelder:** Hintergrund ground innerhalb eines panel-Sheets, Radius 16–18, Einheit rechts in muted, Platzhalter `#4F6377`.

## Screens (aktueller Stand)

Für jeden Screen gibt es einen Screenshot in `design/screens/` und den Quelltext in `design/reference/`. **Bei Abweichungen zwischen Text und Screenshot gilt der Screenshot.**

| Screenshot | Referenz | Screen |
|---|---|---|
| 01–03 | Main.dc.html | Übersicht (Dark, Light, Niedrig) |
| 04 | Glukose.dc.html | Glukose-Detail |
| 05 | Bolus.dc.html | Bolusrechner (Sheet) |
| 06 | Produkte.dc.html | Produkt wählen (Sheet) |
| 07 | BolusConfirm.dc.html | Bolus bestätigen |
| 08 | Sport.dc.html | Sport |
| 09 | Ernaehrung.dc.html | Ernährung |
| 10 | Sensor.dc.html | Sensor-Detail |
| 11 | Pumpe.dc.html | Pumpen-Detail |
| 12 | Health.dc.html | Google Health |
| 13 | Schlaf.dc.html | Schlaf-Detail |
| 14 | Herz.dc.html | Herzfrequenz |
| 15 | Gewicht.dc.html | Gewicht |
| 16–21 | Analyse*.dc.html | Analyse-Tab: Bereiche, Muster, Kennwerte, Verlauf, Ereignisse, Prognose |
| 22 | Inventar.dc.html | Inventar (Liste) |
| 23 | InventarEdit.dc.html | Inventar-Artikel bearbeiten |
| 24 | Verbindungen.dc.html | Verbindungen |
| 25 | Willkommen.dc.html | Onboarding: Willkommen + Bedingungen |
| 26 | Berechtigungen.dc.html | Onboarding: Berechtigungen (seitenweise wie bisher, Beispiel Bluetooth) |
| 27 | Login.dc.html | Anmelden |

### Bolusrechner (Sheet)
- Sheet in panel, Radius 28 oben, Griff 40 × 5. Kopf: Titel 24/800 links, runder Schließen-Button rechts.
- Drei Karten (Radius 22, `#1A2C3D`, 1-px-border), jeweils Icon-Quadrat 32 px (accent auf 14 %) + Titel 16/700, darunter Eingabefeld (Höhe 58, ground, Radius 16; aktives Feld mit 1,5-px-Rand in accent).
  1. Kohlenhydrate: Feld in g, darunter Zeile „Produkte“ (muted) mit Pill-Button „+ Hinzufügen“ (accentSoft, accentText).
  2. Aktueller Glukosewert: Feld in mg/dL, vorbelegt.
  3. Bolus: Karte leicht accent-getönt, Icon-Quadrat gefüllt in accent. Feld Höhe 84, Wert 52/800. Darunter Info-Zeile mit Info-Icon: „Aktives Insulin 1,1 E bereits abgezogen“.
- „Weiter“ als Primärbutton unten.

### Produkt wählen (Sheet)
- Kopf: Zurück, Titel 20/800, rechts „+“ (Produkt anlegen) und Barcode-Scan. Das Lupen-Icon entfällt, weil das Suchfeld direkt darunter steht.
- Suchfeld Höhe 52, ground, Radius 16, Fokus-Rand accent.
- Spaltenkopf: links „Gespeicherte Produkte“, rechts „KH pro 100 g“ (13, muted).
- Liste in einem Panel: Name 15/700, Marke 13 muted, rechts KH-Wert 17/800. Keine Icons, keine Chevrons; die ganze Zeile ist antippbar.

### Bolus bestätigen
- Vollbild mit Zurück + Titel.
- Karte zentriert: Label „Bolus“ mit Icon (accentText), Wert 76/800 in text, Einheit E. Darunter kleines Etikett „● an Omnipod DASH“.
- Zusammenfassung als Schlüssel/Wert-Panel mit Icons: Kohlenhydrate, Glukosewert (Tropfen-Icon!), Aktives Insulin.
- Unten Primärbutton Höhe 58: „✓ Bolus an Pumpe senden“.

### Glukose-Detail
- Kopf: Zurück, Titel, Mahlzeiten-Icon.
- Steuerzeile: Segment-Schalter 24 h / 12 h / 6 h (aktiv accent), rechts ‹ Jetzt ›.
- **Ein gemeinsames Diagramm**: oben Glukose, direkt darunter (ohne Abstand) Insulin. Gemeinsame Trennlinie = Grundlinie des Glukose-Teils.
  - Glukose: keine Gitterlinien, Zielbereich 70–180 leicht hinterlegt (range 5 %), Grenzen gestrichelt. Linie nach Bereich eingefärbt. Y-Labels rechts (70, 180, 250).
  - Mahlzeiten: Etikett oben („30 g“, Pill in `#1E3042`), gestrichelte Linie **durch beide Diagramme** bis unten, Punkt auf der Kurve (weiß mit ground-Ring). Überlappende Etiketten zweite Zeile.
  - Vorhersage: gestrichelte Linie in muted, Unsicherheitsbereich text 8 %.
  - Insulin: Balken hängen **nach unten**. Basal breit (accent 32 %), Bolus schmal 7 px (accent voll). Skala 0–2 E rechts.
  - X-Achse unten: 8 Uhr, 11 Uhr …
- Legende darunter: Basal 2,7 E, Bolus 3,9 E.

### Sport
- Reihenfolge wie im Original: Heute-Kacheln, Routinen (einzelne Karten mit Icon, Play-Button accent, Mehr-Menü), darunter zwei Buttons nebeneinander („Neue Routine“ primär, „Freies Training“ accentSoft), Trainings (3 Kacheln, accent-getönt, Icon über Label), Aktivitäten (einzelne Karten, Datum/Uhrzeit rechts), „Mehr anzeigen“.

### Ernährung
- Heute-Kacheln: Kohlenhydrate (mit Fortschritt), Eiweiß, Mahlzeiten, Bolus.
- Trinken: Panel mit Menge 34/800 „von 2,5 L“, Fortschrittsbalken, 5 Schnellwahl-Kreise 52 px (accent auf 12 %), „Frei“ gestrichelt.
- Mahlzeiten und Produkte als Listen in je einem Panel; Produkte mit Entfernen-Button (×).

### Sensor
- Gerätekopf ohne Karte (Icon 56, Name 24/800, Statuszeile mit Punkt), Haltbarkeit als 10 Segmente.
- Panels „Status“, „Gerät“ (Schlüssel/Wert), „Sitzung“ mit Zeilen „Sitzung beenden“ (neutral) und „Sensor stoppen“ (rot).

### Pumpe
- Gerätekopf wie Sensor. Darunter Pod-Laufzeit (3 Segmente = Tage) und Reservoir-Balken.
- Abschnitt „Abgabe“, drei eigenständige Elemente mit 10 px Abstand (keine Trennlinien):
  1. Karte „Automatische Abgabe“: Titel + letzter Status (13, muted) als antippbare Zeile mit Chevron, darunter großer Segment-Schalter Aus / Aktiv.
  2. Leiste temporäre Rate: Fläche high 10 %, Icon, „Temporär 0,00 E/h“ (Wert in high), Pill „Beenden“.
  3. Button „Abgabe stoppen“ (danger).
- Pod-Daten (Schlüssel/Wert, Aktualisieren-Icon mit Hinweispunkt), „Pod verwalten“ (Pod deaktivieren, Pod vergessen, rot).

### Schlaf
- Kopf mit Zurück + Titel, darunter Datums-Navigation (runde Buttons ‹ › und Datum mittig).
- Hero-Karte (Radius 26): links „Geschlafen“, Dauer groß (Zahlen 50/800, h/min klein muted), „Ø 7 h 20 min pro Nacht“; rechts Ring 96 px mit Schlafindex (range-Farbe). Darunter ein Phasen-Streifen (12 px, Phasen in zeitlicher Reihenfolge eingefärbt) mit Mond + Einschlafzeit links und Aufwachzeit + Sonne rechts.
- Schlafindex: Kopfzeile mit Hinweis „✓ alle im Zielbereich“ (range). Ein Panel mit drei Zeilen: Label links, Wert fett rechts, darunter Skala (Spur 6 px, Zielbereich als grün getönter Abschnitt, Wert als grüner Punkt 16 px mit Ring in panel). Unten kleine Legende „Zielbereich“. Keine Kacheln.
- Schlafphasen: ein Hypnogramm (Zeilen Wach/REM/Leicht/Tief, Phasen als Blöcke 16 px, dünne Verbindungslinien zwischen Wechseln, Uhrzeiten unten). Darunter, durch eine Linie getrennt, eine Liste **ohne Boxen**: je Phase eine Zeile mit Farbpunkt + Name (15), Anteilsbalken 6 px in der Phasenfarbe, Dauer fett rechts. Farben: Tief #8C7BFF, Leicht #5BC0F8, REM #2ED8B6, Wach = low.
- Entwicklung: Segment-Schalter 7 T / 30 T / 90 T / 1 J / Alle + Kalender-Button. Balkendiagramm in Stunden, gestrichelte Durchschnittslinie, letzter Balken voll accent.
- Verlauf: Liste in einem Panel mit Datum, Mini-Balken der Dauer und Dauer fett. „Mehr anzeigen“.


### Analyse-Tab
- Kopfzeile mit den drei Header-Buttons, darunter Seitentitel „Analyse“ (30/800).
- Unterbereiche als **horizontal scrollbare Pillen-Reihe** (Bereiche, Muster, Kennwerte, Verlauf, Ereignisse, Prognose) statt 2 × 3-Raster. Aktive Pille hell (text-Farbe) mit dunkler Schrift, inaktive panel mit muted Schrift.
- Darunter Zeitraum-Segment-Schalter 1 T / 3 T / 7 T / 30 T / 90 T + Kalender-Button (gleich wie Schlaf/Gewicht).
- **Bereiche:** ein Panel: „91 % im Zielbereich“ groß, darunter links vertikaler gestapelter Balken (28 px, Segmente mit 3-px-Lücken), rechts Liste der fünf Bereiche (Farbpunkt, Name 15/700, Bereich 12 muted, Prozent rechts), Trennlinien dazwischen.
- **Muster:** Abschnittskopf mit Untertitel. Panel mit AGP-Diagramm: Zielbereich leicht hinterlegt, Grenzen gestrichelt, Streuung als accent-Fläche 16 %, Median weiße Linie. Legende darunter.
- **Kennwerte / Prognose-Werte:** ein Panel mit 2-Spalten-Raster, Zellen durch 1-px-Linien getrennt (keine Einzelkarten). Label 13 muted, Wert 28/800, Einheit klein.
- **Verlauf:** Panel mit Tagesdurchschnitt als Linie mit Punkten und Streuungsband, Wochentage als X-Achse.
- **Ereignisse:** oben zwei Zähler (Unterzucker / Überzucker), darunter Liste in einem Panel: Icon-Kreis (low/high getönt, Pfeil), Titel, Wert in Bereichsfarbe, rechts Datum relativ + Uhrzeit.
- **Prognose:** zusätzlicher Segment-Schalter 30 min / 60 min, Kennwert-Raster, Diagramm „Gemessen“ (weiß) vs. „Prognose“ (accent) mit Legende.

### Herzfrequenz
- Kopf mit Einstellungs-Icon. Aktueller Wert groß mit Herz-Icon im getönten Kreis.
- Datums-Navigation, dann Zeile Ø Tag / Min / Max in einem Panel mit vertikalen Trennlinien.
- Segment-Schalter 24 h / 12 h / 6 h, Diagramm im Panel ohne Flächenfüllung; Linie in accent (#9DAEFF), Werte über 100 bpm in Violett (#C9A7FF), Schwelle gestrichelt in derselben Farbe. Bewusst **kein Rot/Gelb**, damit erhöhter Puls nicht als Warnung wirkt. Herz-Icon in accent auf accentSoft.

### Gewicht
- Oben ohne Karte: Wert 56/800 + kg, Änderungs-Chip rechts (grün ↓ / gelb ↑), darunter BMI-Pill.
- Min / Ø / Max wie bei Herzfrequenz. Segment-Schalter + Kalender. Liniendiagramm mit gestrichelter Durchschnittslinie.
- Verlauf als Liste in einem Panel: Gewicht fett, Datum relativ, Änderungs-Chip, Löschen-Icon. „+“ als runder FAB unten rechts.

### Inventar
- Je Artikel eine Karte: Name 17/700, rechts Stepper (− Zahl +) in ground-Pille, darunter Bestandsbalken, Zeile „x von y Stück“ + „noch n Tage“, darunter „Reicht bis …“ fett und ggf. Hinweis (z. B. Überschuss).
- Bearbeiten: Felder mit Label darüber (panel, Radius 16), Bestand/Grundbestand und Typ/Sensor-Typ jeweils zweispaltig. Lieferungen als Liste in einem Panel (LKW-Icon, Datum, „+18“-Pill, ×). Löschen-Icon rot in der Kopfzeile, „Speichern“ als Primärbutton unten.

### Verbindungen
- Oben Gesamtstatus ohne Karte: grüner Haken im getönten Kreis, „Alles verbunden“ (20/800), darunter „3 von 3 Verbindungen aktiv“. Bei Problemen entsprechend „1 Verbindung braucht Aufmerksamkeit“ mit high/low-Farbe.
- Je Verbindung eine schlichte Karte (Radius 22): Icon-Kreis 48 px mit Statuspunkt unten rechts, Name 17/700, darunter nur der Gerätename (14, muted: „Dexcom G7“, „Omnipod DASH“, „Fitbit Air“), Chevron. Der Verbindungsstatus steckt im Statuspunkt, kein „verbunden“-Text. Keine weiteren Kennzahlen.


### Onboarding: Willkommen
- Inhalt **zentriert**, vertikal mittig: Logo (Unendlich-Zeichen in accent) in einem getönten Quadrat 96 px (Radius 30), Titel „Willkommen bei Insulink“ 38/800 zweizeilig, Untertitel 17 muted.
- Unten: Zustimmung als Karte (panel, Radius 18) mit eigener Checkbox 24 px (accent, Haken in onAccent) und Links „AGB“ / „Datenschutzerklärung“ in accentText, unterstrichen.
- Primärbutton Höhe 58: „Los geht's →“; deaktiviert (accent 35 %), solange nicht akzeptiert.

### Onboarding: Berechtigungen
- **Bleibt seitenweise wie bisher** (eine Seite pro Berechtigung, Punkte-Navigation, Texte und Icons unverändert).
- Nur der Button unten wird an den neuen Primärbutton angeglichen: Höhe 58, Radius 29, Text 17/700 in onAccent, volle Breite.

### Anmelden
- Vertikal mittig, Logo (64 px, accent), „Willkommen“ (34/800) und „Melde dich mit deinem Konto an.“ **zentriert**; Felder und Button volle Breite.
- Felder mit Label darüber (panel, Radius 16, Höhe 56, Fokus-Rand accent), Passwort mit Auge-Icon.
- Primärbutton „Anmelden“ Höhe 58. Ganz unten zentriert: „Noch kein Konto? **Registrieren**“ (Link in accentText, fett).

### Google Health
- Gerätekopf „Verbunden“, Panel „Letzte Werte“ (Schlüssel/Wert), darunter rote Zeile „Verbindung trennen“.

### Navigation
- Schwebend unten (16 px Seitenrand, 28 px unten), darüber ein Verlauf von transparent zu ground, damit der Inhalt weich ausläuft.
- Kapsel (Höhe 62, dock + border + Schatten): aktiver Tab als Pille (accentSoft, Icon + Label in accentText), inaktive Tabs nur als Icon (muted, 48 × 48, mit Semantics-Label).
- Rechts daneben eigener runder **Bolus-Button** 62 px, accent, Spritzen-Icon in onAccent.
- Scroll-Inhalt braucht unten ca. 120 px Platz, damit nichts verdeckt wird.

## Umsetzungshinweise Flutter

- Tokens → `ThemeExtension`, Typo → `TextTheme` + eigene Styles. Keine hartkodierten Farben in Widgets.
- Wiederverwendbare Widgets: `GlucoseHero`, `RangeScale`, `GlucoseChart`, `TimeInRangeBar`, `SegmentBar`, `DevicePanel`, `StatTile`, `FloatingNavBar`, `HeaderIconButton`.
- Graph: bestehende Chart-Lib weiterverwenden oder `CustomPainter` (Linie mit Clip-Bereichen pro Farbe).
- Bestehende State-Management-, BLE- und Service-Logik **nicht anfassen** – nur die View-Schicht.
