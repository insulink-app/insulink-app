# Web demo

The project website (`insulink-website`) runs the real app in its hero, built for
the browser with a month of dummy data. It is the same code as the phone app, started
from a different entry point.

## Build and deploy

The website holds no app code. The `web-demo` job in `.github/workflows/build.yml`
rebuilds the demo on every push to `main` (after `verify` passes) and publishes it
to this repo's GitHub Pages, `https://insulink-app.github.io/insulink-app/`. The
website's hero loads that URL in an iframe (`data-src` on `.demo-frame`), so the
deploy is the website update. One-time setup: Settings > Pages > Source: "GitHub
Actions".

Local preview:

```bash
flutter build web --release -t lib/main_demo.dart --dart-define=DEMO=true --base-href /
cd build/web && python3 -m http.server 8090
```

and point the website's `data-src` at `http://localhost:8090/` while testing.

`canvaskit/` is dropped from the deploy on purpose: the engine loads CanvasKit
from Google's CDN (gstatic) by default, so the 37 MB local copy is never fetched.

`web/index.html` carries a Content-Security-Policy whose `connect-src` lists only
the page itself, gstatic, the Esri map tiles and OpenFoodFacts. The browser
refuses anything else, the Insulink API included, even if a future code path
skipped `DemoBackend`.

## What the demo entry point does differently

`lib/main_demo.dart` replaces `main.dart`. The start itself lives in
`lib/src/demo/demo_app.dart` (`DemoApp`), which the screenshot run shares
(`docs/SCREENSHOTS.md`):

- **No vendor keys.** `VendorKeys.ensureLoaded` is never called, and the web build
  never bundles `vendor_keys.json` anyway (only Gradle copies it). The start-up
  warning stays silent under `DemoMode.enabled`.
- **No foreground-service port.** `FlutterForegroundTask.initCommunicationPort`
  needs isolates the browser does not have and throws there.
- **No backend.** The whole app runs inside `runWithClient` from `package:http`,
  so every `get`/`post`, including `Request`, goes to `DemoBackend`. Requests to
  the API host are answered from `DemoAccount`; anything else (map tiles, the food
  database) goes out through a client created before the zone. `DemoBackend` always
  answers 200: a 403 would sign the demo out and a 417 would try a token refresh.
  The binding is created inside the zone so frame callbacks stay in it.
- **Setup skipped.** `DemoLaunch` clears storage, marks the legal notice and the
  permission onboarding done, stores a placeholder token, turns the fingerprint
  gates off, then runs the normal `AccountSync().pullAll()` against the demo
  backend. The data reaches the stores through the app's own parsers, so the demo
  cannot drift from the real storage format.

## Dummy data (`lib/src/demo/`)

Generated on every load around `DateTime.now()` from a fixed seed, so every
visitor sees the same month:

| File | What |
|------|------|
| `demo_glucose.dart` | 30 days every 5 min: day rhythm, a rise after each meal, sometimes a dip after it. A meal is indexed by its calendar day so one meal keeps its size over its whole curve (indexing by "days since start" made the curve jump at the current time of day). |
| `demo_events.dart` | Alarm events from crossings into a worse zone. |
| `demo_sensor.dart` | A Dexcom G7 two days into its session, so the headline is current and the sensor card shows its remaining life. |
| `demo_pump.dart` | An Omnipod DASH 46 h into its life: pairing, a stored last status (38.5 U left), the active basal profile set to its rates (so the pump page does not offer to send it) and every past hour booked in the basal ledger, which gives the glucose chart its basal bars. |
| `demo_loop.dart` | Automated delivery switched on, with two hours of cycles decided by the real `LoopAlgorithm` and `LoopSafety` from the demo glucose (meal boluses and the automation's own insulin as IOB) and the temporary rate of the newest one running. Each cycle is a pod contact; `demo_pump.dart` adds the background poll's 15-minute contacts for the rest of the day, so the connection page has a pod line. |
| `demo_devices.dart` | The sensor and pod history (`/sensor/history/`, `/pump/history/`): a month of devices back from the running ones, one sensor discarded early, one Libre 3, one pod replaced after a day. |
| `demo_live_sensor.dart` | Keeps the sensor delivering: every five minutes a reading that continues the newest archived one along `DemoGlucose.shapeAt`, written to the store and sent to `CgmController` as the service's `reading` and `update` messages. A tab that slept catches up on what it missed. |
| `demo_nutrition.dart` | Meals at the curve's meal times with a matching bolus, drinks, inventory. |
| `demo_sport.dart`, `demo_activity.dart` | Exercises, routines, workouts; daily steps, distance, calories, weight. |
| `demo_cardio.dart` | Walks, a jog and a ride with a GPS loop around the Rheinaue in Bonn. |
| `demo_health.dart`, `demo_sleep.dart` | Sleep with a hypnogram, resting heart rate, a pulse curve that follows sleep and the trainings, HbA1c. |

Google Health counts as connected with a fresh import stamp, so the boxes show the
pulled days and the app never tries Health Connect.

`demo_layouts.dart` sets the overview, Sport "Today" and nutrition boxes to the
selection on the website's screenshots instead of the first-launch defaults.
`DemoLaunch` also turns on the meal markers in the glucose chart.

## Language and theme

The website loads the demo as `app/?lang=de|en&theme=dark|light` and changes the
`src` when the visitor switches either, which reloads the demo behind its splash.
`DemoLaunch` stores both (`language`, `theme`) before `Locales.init` runs, since
the locale is read from storage once.

## Code outside `lib/src/demo/` that knows about the demo

Kept to a handful of switches on `DemoMode.enabled` (`--dart-define=DEMO=true`):

- `VendorKeysWarning`: no warning.
- `demo_pod.dart`: `demoPodEnabled` follows it, so the pump page talks to the
  in-memory demo pod.
- `PodBlePermissions.ensure`: true, there is no radio to ask for.
- `AuthPage`: the fields come filled with `DemoAccount.signInName` /
  `signInPassword`, so a visitor who signs out can sign straight back in; the
  demo backend answers `/signin/` with a token for them.
- `CgmController.init`: starts `DemoLiveSensor`, which feeds the controller's
  service-message handler because the browser has no service isolate.

## `web/index.html`

- **Splash**: the native splash's colours and logo (`web/splash/`, downscaled from
  `assets/images/splash-*.png`), light and dark, with a loading bar. It fades out on
  `flutter-first-frame`, so it also covers the dummy data being generated.
- **Rounds itself when embedded**: with `?frame=<radius>` (the website passes
  its `--screen-radius`) the page clips its own body to that radius, with root
  and body transparent (with a transparent root the browser paints body's
  background across the whole canvas, outside the clip). This is the second
  line only. The website never clips the iframe, since browsers do not reliably
  clip a composited iframe to a rounded box (the app spilled over the mockup
  every time that was relied on). Instead it draws the inner bezel ring as an
  overlay ON TOP of the iframe, which covers the square corners whatever the app
  does; `style.css` holds the geometry rule that keeps the corner tips under the
  ring. Both sides use `color-scheme: normal`, since a mismatch makes the
  browser paint an opaque backdrop behind the iframe.
- **Wheel stays in the demo**: every wheel event has its default cancelled and the
  root has `overscroll-behavior: none`, so reaching the end of a list never scrolls
  the website around the iframe.
- **Smooth wheel**: Flutter web jumps a whole notch per wheel event. Coarse notches
  (30 px and more) are swallowed in the capture phase and replayed as an eased
  series of small synthetic wheel events, one per frame. Trackpad deltas are
  already fine-grained and pass straight through.

## Web-only differences in shared code

- `BouncyScrollBehavior` draws no scrollbars. Material only adds them on desktop
  platforms, which includes the browser.
- `Alert` has no backdrop blur on the web, only a darker barrier: CanvasKit
  re-blurs the whole screen through WebGL every frame the dialog is up, which made
  each popup stutter. Native keeps the blur.

## Known noise

Plugins without a web implementation (foreground task, permission handler, local
auth) throw `MissingPluginException` and `Directory.systemTemp` throws
`UnsupportedError` in the console. Each only aborts its own async call; none stops
the app.
