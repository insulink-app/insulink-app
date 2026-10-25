# Daylight saving

On the last Sunday of October the hour from 2 to 3 happens twice, in March it
does not happen at all. Code that walks through time hour by hour has to
survive both nights, because a loop that stops advancing freezes the whole app:
the service's pod tick runs on the Android main thread (Flutter merged the UI
and platform threads), so Android reports "Insulink is not responding".

## What happened

`PodBasalDelivery._nextHourBoundary` rebuilt the hour with
`DateTime(year, month, day, hour)` and added an hour. For the repeated 2 o'clock
that constructor picks the FIRST occurrence, so from inside the second one the
"next boundary" lay behind the cursor and `unitsBetween` never finished. Every
pod tick that booked basal across the night of 25 October 2026 froze the app.

## The rules

- **Step through time with absolute durations** (`moment.add(...)`), or measure
  what is left to the next boundary from the moment itself, as
  `_nextHourBoundary` now does. Never rebuild a wall-clock time inside a loop
  and expect it to lie ahead.
- **Every time loop must provably advance.** Where a step comes from a
  calculation, check that it is after the cursor and stop otherwise
  (`unitsBetween` does), or cap the iterations
  (`GlucoseHistorySeries._spanStarts`).
- `DateTime(year, month, day + 1)` for "next calendar day" is safe: it always
  moves forward.

## How it is held

- `test/pump/pod_basal_dst_test.dart` walks every quarter hour of every
  changeover night from 2026 to 2030, with a timeout so a regression fails
  instead of hanging.
- CI runs `flutter test` with `TZ=Europe/Berlin`. On the runner's default UTC
  there is no changeover night and such a test passes without testing anything.
  Run it locally the same way: `TZ=Europe/Berlin flutter test`.
