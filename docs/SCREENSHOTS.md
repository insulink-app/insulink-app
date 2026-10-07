# Screenshots

Every push to `main` photographs the browser demo and publishes the pictures next
to it on GitHub Pages, so they always show the current app with the demo's dummy
data. Nothing is committed anywhere.

## Where they are

`https://insulink-app.github.io/insulink-app/screenshots/<language>-<theme>/<name>.png`

- `<language>-<theme>`: `de-dark`, `de-light`, `en-dark`, `en-light`
- `<name>`: `overview`, `sport`, `nutrition`, `analysis`, `glucose`

Each picture is 824 x 1830 (a 412 x 915 phone at 2x). A deploy replaces the whole
set, so a fixed URL always serves the newest picture.

## How they are made

`integration_test/screenshots_test.dart` starts the demo through `DemoApp` (the
same start as `lib/main_demo.dart`, `docs/WEB_DEMO.md`), visits the four tabs and
opens the glucose page from the overview, and takes a picture of each.
`test_driver/integration_test.dart` writes them to `build/screenshots/`. The
`web-demo` job in `.github/workflows/build.yml` runs it once per language and
theme in the runner's Chrome, then copies the folder into the Pages build. It runs
before `flutter build web`, because `flutter drive` builds into `build/web` too.

Run it locally (a chromedriver matching your Chrome on port 4444):

```bash
chromedriver --port=4444 &
flutter drive --release -d web-server --browser-name=chrome \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  --browser-dimension=412x915@2 --dart-define=DEMO=true \
  --dart-define=LANGUAGE=de --dart-define=THEME=dark
```

With the Chromium snap, use `chromium.chromedriver` and pass
`--chrome-binary=/snap/chromium/current/usr/lib/chromium-browser/chrome`.

To add a picture, navigate to the screen in the test and call `shoot('<name>')`.

## What the test binding changes (learned the hard way)

- **The app starts in the test body.** The binding replaces whatever is mounted
  when the test begins with its "Test starting" placeholder, so a tree started in
  `main` is gone before the first picture.
- **The binding is created inside the demo's request zone**, like the website's.
  Created outside it, the requests widgets start from frame callbacks go past
  `DemoBackend` to the real network.
- **The test pumps frame by frame** (`settle`). The binding only draws the frames
  it is asked for, so after a single long pump the tab transition has not played
  and each picture shows the previous tab. `fullyLive` is not the fix: with it the
  test is reported finished before it has taken its pictures.
- **Any uncaught error at start ends the test** with an empty failure message
  (release builds strip it). The demo must therefore start without errors in the
  browser: plugins with no web implementation are skipped on web
  (`ServicePresence`, the step counter in `SportActivityState`, the decision file
  in `SportStore.applyTrainingDecisions`). To find the next one, set
  `binding.reportData` from `FlutterError.onError` in the test: the data reaches
  the `result` line `flutter drive` prints, the failure details do not.
