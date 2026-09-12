# Localization

User-facing strings live in `assets/locales/{de,en}.json`. German is the base
locale; English is the fallback shape. No hard-coded display strings in code.

## Never load a locale file with `rootBundle.loadString`

`AssetBundle.loadString` hands anything from **50 KiB up** to `compute`, i.e. a
real isolate. Under `testWidgets`' fake clock that isolate never completes, so
the `Locales` delegate's future stays pending and **every widget test renders a
blank screen** — `find.text(...)` simply finds nothing, with no error pointing
at localization. The day `en.json` crossed 50 KiB, one unrelated sport test
started failing; `de.json` had been over the line for a while without symptoms
only because those tests resolve to `en`.

So both loaders (`Locales.load`, `ServiceStrings.get`) call `rootBundle.load`
and `utf8.decode` the bytes themselves. Keep it that way, and don't reach for
`loadString` in a new one. The decode costs microseconds; the isolate cost was
also real in the service isolate, which resolved strings per notification.

## House style for the strings themselves

**No dash as punctuation.** Not an em dash, not an en dash, not a spaced hyphen.
A dash reads as an afterthought bolted onto a sentence, and the em dash in
particular reads as machine-written; every one of them can be a comma, a colon or
a full stop, and the sentence is better for it:

| Instead of | Write |
|------------|-------|
| `NFC scan failed — try again.` | `NFC scan failed. Try again.` |
| `Glucose low — alarm` | `Low glucose alarm` |
| `Pod alarm — delivery stopped` | `Pod alarm: delivery stopped` |
| `Temporary: # U/h — end it` | `End temporary # U/h` |

A hyphen INSIDE a word is fine and often required, because German compounds carry
one: `Glukose-Alarme`, `App-Reset`, `Pod-Alarm`. The rule is about a dash standing
on its own between words.

`test/localization/locale_punctuation_test.dart` enforces this over both locale
files, so a new string with a dash fails the suite rather than shipping. If you
find yourself wanting one, the sentence usually wants splitting in two.

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
    "channel": { "low_urgent": { "name": "Low glucose alarm" } }
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

> ⚠️ **Common slip — reference the self-value by its PARENT path, not `parent._`.**
> To read a section's own label in code, look up `'sport.summary'`, **not**
> `'sport.summary._'`. The flattener maps `_` onto the parent path, so a
> `parent._` key does not exist in the flat map and the UI would render the raw
> `$sport.summary._` placeholder. `Locales.get` now self-heals a trailing `._`
> back to the parent (a `parent._` lookup can only ever be this mistake), so both
> forms resolve — but write the parent path directly. `ServiceStrings` walks the
> path literally and already resolves either form.

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

## The 50 KB asset threshold (widget tests)

Flutter decodes an asset larger than 50 KB in a **background isolate**, and
`assets/locales/de.json` crossed that line as the app grew. `pumpAndSettle` waits
for frames, not for real asynchronous work, so from that moment every widget test
that renders a `LocaleText` settled with no strings loaded and asserted against
`$key` placeholders instead. It looks exactly like a broken locale file and is
not one.

`test/support/locale_pump.dart` is the fix: pump the frame first, so the load is
under way, then `settleLocalized(tester)` gives it real time and settles. Any new
widget test that renders localized text needs it.
