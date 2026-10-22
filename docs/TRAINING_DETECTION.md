# Training detection

How a walk or bike ride turns into a pending training without the user starting
one, and the two traps that used to make it miss everyday rides.

## Pipeline

1. `ActivityRecognitionSampler` logs every OS activity change (still, walk, run,
   bike, vehicle).
2. `BackgroundLocationSampler.tick()` (every 10 s in the service isolate) decides
   which GPS stream is open: none at rest, `detect`/`activeDetect` while moving,
   `recording` during a manual training. At rest it does a sparse one-shot poll.
3. `CardioDetectionRunner` cuts the location log into segments
   (`CardioDetector`: ≥ 8 min, ≥ 500 m, pauses ≤ 3 min bridged) and types each one
   with `CardioActivityClassifier`.

## Trap 1: the at-rest poll never sees movement

The one-shot poll asks for `LocationAccuracy.medium`, which is Android's
balanced-power provider (Wi-Fi/cell). Those fixes carry **no speed**: geolocator
reports `0`. "Moving" used to come only from `fix.speed`, so the dense stream
opened only when another app kept the GNSS radio warm. Everything else was logged
at one coarse point per minute, fixes over 50 m were dropped, and the gaps broke
each ride before it reached 8 minutes.

Now the activity recognition opens the stream: while it reports walk, run, bike
or vehicle (`_movingActivities` in the sampler), every tick marks the user as
moving. The same mark keeps the stream open across a long red light, where GNSS
speed is 0.

Cost: a car, bus or train ride opens the stream too. `VehicleStandDown` keeps
that short: three GNSS fixes at 50 km/h or more under a vehicle label confirm
the ride is motorised (no commuter bike gets there, and the classifier would
discard it anyway), the stream lingers out and stays closed until the label
changes. Stepping off the bus reopens it at once. A slow city ride that never
reaches 50 keeps streaming; that is the price of not losing bike rides the
recognition calls a vehicle. The battery saver still turns all of it off
(`docs/BATTERY.md`).

Not worth changing: the recognition plugin asks Android for an update every
second (hard-coded in `flutter_activity_recognition`), but the service holds a
partial wake lock for the CGM anyway, so the CPU never sleeps deeply and those
updates add little. GNSS-on time is what costs.

## Trap 2: a bike ride reported as a vehicle

The activity recognition often calls cycling `IN_VEHICLE`. A vehicle label used
to discard the segment outright. Now it only does when the segment also
reaches vehicle speed: the 90th-percentile speed between fixes above 35 km/h. A
bus or car averages bike speed between stops but hits 45–50 on the way, while a
bike or pedelec doesn't sustain 35. A vehicle-labelled segment below that is a
bike ride. A car crawling through a jam slips through; the user rejects the
pending training.

Unchanged: an average above 30 km/h is never human-powered, whatever the label
(a train misread as walking).

## The heart rate settles what speed cannot

`CardioDetectionRunner` hands the stored pulse curve (`IntradayPulseStore`, fed
by the band and Health Connect) to the classifier as `HeartRateEvidence`. Each
segment gets a `HeartEffort`: the median pulse during it against the 10th
percentile of the 24 h before it. That baseline includes sleep, so it sits below
an awake resting pulse; the cut-offs are set with that in mind.

| Lift over baseline | Effort | Effect |
|---|---|---|
| < 20 bpm | resting | a bike-speed segment is discarded as a passive ride (bus, tram, the car in a jam from trap 2), unless the recognition saw cycling |
| 20 to 59 bpm | light | nothing changes |
| ≥ 60 bpm | hard | a walk-speed segment averaging ≥ 7 km/h becomes a jog |

Fewer samples than half the segment's minutes, or fewer than 60 for the
baseline, read `unknown` and leave the rules above exactly as they were. So a
user without a band sees no change. A pedelec rider whose pulse stays near rest
and whose phone calls it a vehicle is discarded; the recognition saying `bike`
protects the ordinary case.

## Checking it on the device

The log pane prints `training detection: N gps points (M new) → K detected`
after each scan, plus `location: detect stream started` when a ride begins. No
stream line during a ride means the activity recognition never reported
movement (check the ACTIVITY_RECOGNITION permission).
