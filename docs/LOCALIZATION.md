# Localization

User-facing strings live in `assets/locales/{de,en}.json`. German is the base
locale; English is the fallback shape. No hard-coded display strings in code.

## Key naming

Keys are **`snake_case`, namespaced by section, dot-separated**:

```
profile.glucose.urgent_low
alarm.channel.low_urgent.name
sensor.state.needs_calibration
```

Group by feature/page first (`profile.*`, `sensor.*`, `alarm.*`,
`statistics.*`), then by sub-area, then the leaf. Keep both locale files in the
same order so they're easy to diff.

## Placeholder convention

A single `#` in a value is the substitution point:

```json
"alarm.expiry.body": "Dein Sensor läuft in etwa # h ab. Bereite einen neuen vor.",
"sensor.life.remaining": "noch # Tage"
```

## In the widget tree

UI widgets resolve strings through the `flutter_localization` widgets
(`locales.dart`, `LocaleText`, etc.), driven by the selected `BuildContext`
locale.

## Outside the widget tree — `ServiceStrings`

The **foreground-service isolate** and `G7Controller` have no `BuildContext`,
and a freshly-spawned isolate has no initialized `Locales` state either. They use
`lib/src/localization/service_strings.dart` (`ServiceStrings`), which:

1. reads the persisted language directly from secure storage (the `language` key
   `LocalePreference` writes),
2. loads that locale's JSON from the asset bundle,
3. falls back to German, then to the key itself, on any failure.

`get(key)` returns the translation; `format(key, value)` substitutes the first
`#`. Use it for notification text (the service notification, all alarm
titles/bodies, channel names/descriptions).
