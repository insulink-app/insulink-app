# Localization

User-facing strings live in `assets/locales/{de,en}.json`. German is the base
locale; English is the fallback shape. No hard-coded display strings in code.

## Structure & key naming

The files are **nested objects** grouped by section, with `snake_case` leaf
keys:

```json
{
  "profile": {
    "glucose": {
      "_": "Glucose",
      "urgent_low": "Urgent low",
      "target": "Target range"
    }
  },
  "alarm": {
    "channel": { "low_urgent": { "name": "Glucose low — alarm" } }
  }
}
```

The app still looks strings up by **dot-separated paths** — both loaders flatten
the nesting (see below), so call sites are unchanged:

```
profile.glucose.urgent_low
alarm.channel.low_urgent.name
sensor.state.needs_calibration
```

**`_` self-value:** a node that is BOTH a label and a prefix stores its own
value under `_`. Above, `profile.glucose._` → `profile.glucose` ("Glucose"),
sitting alongside its children `profile.glucose.target` etc. `_` always maps to
the parent path, never `parent._`.

Group by feature/page first (`profile`, `sensor`, `alarm`, `statistics`), then
by sub-area, then the leaf. Keep both locale files in the same shape/order so
they're easy to diff.

## Loading (flatten-on-load)

Neither loader looks up nested objects directly:

- `locales.dart` (UI) recursively flattens the whole map to dotted keys on load
  (`_flatten`), then serves `get(key)` from that flat map.
- `ServiceStrings` walks the path segment-by-segment per lookup (`_resolve`),
  no full flatten.

Both honour the `_` self-value rule, so `'profile.glucose'` resolves to the
node's `_` value when that node also has children.

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
2. loads that locale's JSON from the asset bundle and walks the nested path,
3. falls back to German, then to the key itself, on any failure.

`get(key)` returns the translation; `format(key, value)` substitutes the first
`#`. Use it for notification text (the service notification, all alarm
titles/bodies, channel names/descriptions).
