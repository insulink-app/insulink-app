# Screenshots

Every push to `main` photographs the browser demo and publishes the pictures next
to it on GitHub Pages, so they always show the current app with the demo's dummy
data. Nothing is committed anywhere.

## Where they are

`https://insulink-app.github.io/insulink-app/screenshots/<language>-<theme>/<name>.png`

- `<language>-<theme>`: `de-dark`, `de-light`, `en-dark`, `en-light`
- `<name>`: the four tabs (`overview`, `sport`, `nutrition`, `analysis`), the six
  analyses (`analysis-ranges` … `analysis-forecast`), every screen in
  `integration_test/screenshot_scenes.dart` and the settings topics
  (`settings-glucose` …), about fifty in all.

Each picture is 824 x 1830 (a 412 x 915 phone at 2x). A deploy replaces the whole
set, so a fixed URL always serves the newest picture. The website's "Screens"
strip loads them straight from there.

## How they are made

`integration_test/screenshots_test.dart` starts the demo through `DemoApp` (the
same start as `lib/main_demo.dart`, `docs/WEB_DEMO.md`), photographs the tabs and
analyses, then opens each scene of `screenshot_scenes.dart` the way the app opens
it (a page pushed with its real arguments, a sheet through its `show…` function),
so no step taps on localized text. The settings topics are the exception: the
profile page builds them from a private list, so the test taps their row by its
resolved title. `test_driver/integration_test.dart` writes the pictures to
`build/screenshots/`.

In CI the `screenshots` job runs once per language and theme as a 2 x 2 matrix,
in parallel, and uploads its folder; the `web-demo` job downloads the four into
`build/screenshots` and copies them into the Pages build. A screen that throws
fails its job, and the demo is not deployed with half the pictures.

To add a picture, add a scene (`name` plus how to open it) to
`screenshot_scenes.dart`, and on the website a `<figure>` with that `data-shot`.

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
- **Home is remembered, not looked up again.** Once a page covers it, `AppPage`
  is offstage and `find.byType` skips it, so the test keeps its context and its
  route from the start and pops back to that route after every scene.
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
