# Route maps (app + panel)

The training route is drawn on raster tiles by `flutter_map`
(`lib/src/sport/training/cardio_map.dart`), and by Leaflet in the panel
(`insulink-panel/src/components/route-map.tsx`). Both pull the same tiles and
are kept deliberately in step, so a route looks the same wherever it is opened.

## Esri Gray Canvas, and why not the obvious alternatives

`https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_{Light,Dark}_Gray_{Base,Reference}/MapServer/tile/{z}/{y}/{x}`
— note the **`{z}/{y}/{x}` order**, row before column, unlike every OSM-style
template.

A quiet grey map with a genuine dark counterpart, no API key. A route line is
the content; the map is the background and should look like one.

Two rejected predecessors, both instructive:

- **CartoDB Positron / Dark Matter** (`{s}.basemaps.cartocdn.com`) was the
  original and is exactly the look wanted here, but CARTO now requires a key
  for it. It does not fail loudly: the tiles still arrive, with **"API KEY
  REQUIRED" stamped diagonally across every one of them**.
- **Plain OpenStreetMap** is keyless and was the first replacement, but its one
  style is a busy, colourful general-purpose map, and a dark mode had to be
  faked from it by inverting the tiles — which reads as a photo negative, not as
  a dark map.

Any keyed provider (CARTO, Stadia, MapTiler, Thunderforest) means a secret in a
client binary that self-hosters rebuild themselves. Vector styles
(OpenFreeMap, Versatiles) mean another renderer dependency. Neither is worth it
for a line on a background.

**If the map ever looks wrong, fetch one tile with `curl` and LOOK at it**
before suspecting the app. Both failures so far were served as HTTP 200 with a
perfectly valid image carrying a message.

## A style is two layers

Esri splits base map and place names (`..._Base` + `..._Reference`), so both
clients stack two tile layers, in that order, UNDER the route line. Swapping the
theme swaps both.

## `maxNativeZoom` is load-bearing

Esri draws to **zoom 16**. Past it the service answers 200 with a placeholder
tile reading *"Map data not yet available"* — the same failure mode as the CARTO
watermark, one zoom step away. Both clients therefore cap the requested zoom at
16 (`TileLayer.maxNativeZoom` / Leaflet's `maxNativeZoom`) and let the z16 tile
be scaled up. Check this whenever the tile source changes.

## The dark map is dimmed, and only its base layer

Esri's dark canvas is a mid grey (land ≈ `#4D4D4F`) — much lighter than this
app's dark page (`#15181D`), so the map glowed out of the screen. The base layer
is scaled to `_darkDim` (0.55), putting its land around `#2A2A2B`: just above
the app's dark surface, so the map still reads as a panel rather than a hole.

**Only the base layer.** Dimming the whole map would take the place names down
with it, and this is the reason the two-layer split is worth its second request.
The app does it with a `ColorFilter.matrix` on the base `TileLayer`, the panel
with `filter: brightness(0.55)` on that layer's container. Change one, change
the other.

## Attribution

Both tile sources ask for a visible credit, and there is currently **none on the
map**: the corner label was removed on request because it was in the way. If
this project is ever published beyond personal use, put `© Esri,
OpenStreetMap` somewhere the user can reach (an about/licences screen is the
usual place) — that is a licensing obligation, not a design preference.

Keep the `userAgentPackageName` on the app's `TileLayer`: a tile service that
sees no User-Agent may block it, and OSM's policy requires a real one if the map
ever falls back there.
