# Insulink Redesign – Design-Spezifikation (Übersicht)

Ziel: Neues visuelles Design für die Flutter-App. **Funktionalität bleibt unverändert** – nur Darstellung, Layout und Theme ändern sich. Referenz-Mockup: `main.dc.html` (HTML-Prototyp, alle Maße/Farben dort sind maßgeblich) plus Screenshots `overview-*.png`.

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
- Fortschritt (z. B. Schritte): Fläche von links in accentSoft mit 2-px-Kante in accent am Ende.
- Reihenfolge: Schritte, Gewicht, Herzfrequenz, Schlaf, Bolus, Trinken.

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
