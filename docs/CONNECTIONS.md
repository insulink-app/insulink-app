# Reception page

Reached by tapping the "next reading" clock in the overview header
(`lib/src/connections/status/`). Sensor, pump and Fitbit band side by side: when
each was last heard from, and where the link was down over the past day.

The clock is the entry point because it is already what the user looks at when
they wonder whether anything is still arriving. "When did it last say anything"
is the same question one level deeper.

## There is no connection log, so the data IS the log

None of the three devices reports its own outages, and none of them can be asked
afterwards. What each one leaves behind is data with a time on it, and the
absence of that over a stretch of the window is the outage:

| Device | Source | A covered minute means |
|--------|--------|------------------------|
| Sensor | the long-term glucose archive (`CgmController.archiveSince`) | a reading arrived |
| Band   | the intraday pulse archive (`IntradayPulseStore.rangeCurve`) | the band delivered a heartbeat |
| Pod    | `PodContactLog` | the app got a status out of the pod |

The pod is the exception that needed new storage. `PodStore.lastSeenAt` answers
"is contact stale right now", which is what the pod warnings need, and it cannot
answer "when did contact break". So `markSeen` now also appends the minute to a
capped list — in `markSeen` itself, so no path that reaches the pod can record
one without the other. It fills from the moment it ships; the page draws an empty
day until then.

## Buckets, not spans

The three cadences are wildly different: a band delivers about once a second, a
sensor every five minutes, a pod is polled every fifteen. `ConnectionTimeline`
therefore asks all three the same question at half-hour granularity — did
anything at all arrive in this slice — which is the pod's cadence doubled, so a
single skipped poll is not drawn as an outage.

`outages` counts STRETCHES of silence rather than silent buckets: a three-hour
gap is one thing that happened, and calling it six would say more about the
bucket size than about the link.

Pointing at a slice names its half hour on the line under the strip. That is what
makes the strip readable at all: the bar shows THAT there was a gap, the label
says when.

**Deliberately not a `Tooltip`.** A tooltip only opens on a long press on a
touchscreen, and a slice is about seven pixels wide, so the gesture that would
reveal what a gap was is one nobody can land. It was built that way first and did
not work. A tap anywhere along the strip picks the slice under the finger
instead, dragging sweeps through them, and a mouse does the same on hover. The
label line is always present, empty or not, so the rows do not jump as the finger
moves.

## What the page is careful not to claim

- A gap means **no data arrived**, not that the device failed. Those are
  different claims and only the first is something the app knows, so nothing on
  the page states the second.
- A device that was never set up draws a flat grey bar labelled as such, rather
  than a full-width outage it never had (`DeviceConnection.isKnown`).
- "Never contacted" and "silent for three hours" are worded differently, and only
  the second is coloured as a warning.
