import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:latlong2/latlong.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Fit padding for framing the whole route — matches the initial camera fit.
const _routeFitPadding = EdgeInsets.all(40);

/// Esri's Gray Canvas basemaps: a quiet grey map with a real dark counterpart,
/// which is what a route line wants behind it. No API key.
///
/// They replaced CartoDB's Positron/Dark Matter, which CARTO now stamps "API
/// KEY REQUIRED" across, and plain OpenStreetMap, whose single busy style had
/// to be inverted into a dark mode that looked like a photo negative. Esri
/// splits a style in two: the [_lightBase] map and the [_lightLabels] place
/// names over it, both drawn UNDER the route.
const _esri = 'https://services.arcgisonline.com/ArcGIS/rest/services/Canvas';
const _lightBase = '$_esri/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
const _lightLabels =
    '$_esri/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}';
const _darkBase = '$_esri/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
const _darkLabels =
    '$_esri/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}';

/// The deepest zoom Esri actually draws. Past it the service answers with a
/// placeholder tile reading "Map data not yet available" — so without this the
/// map fills with that text the moment the user zooms in one step too far.
/// [TileLayer.maxNativeZoom] scales the z16 tile up instead.
const _maxNativeZoom = 16;

/// The brightness of a road on Esri's dark canvas (0..1). The tint maps it to
/// the app's line colour; everything darker (land, water) falls between that
/// and the page colour.
const _roadLuminance = 0.45;

/// Basemap with the training route as a polyline. [live] keeps the map
/// viewport controlled by the caller (recenter while recording); otherwise it
/// zooms to the whole route. Shared by the recording and detail pages.
class CardioMap extends StatelessWidget {
  const CardioMap({
    super.key,
    required this.points,
    this.controller,
    this.live = false,
    this.fallbackCenter,
    this.highlight,
  });

  final List<TrackPoint> points;
  final MapController? controller;
  final bool live;

  /// A position to spotlight on the route (the chart-hover marker) — drawn on
  /// top of the route in a contrasting color.
  final LatLng? highlight;

  /// Where to center when no route point exists yet (e.g. the last-known
  /// position while a live recording waits for its first fix).
  final LatLng? fallbackCenter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final route = [for (final point in points) LatLng(point.lat, point.lng)];
    final center = route.isNotEmpty
        ? route.last
        : (fallbackCenter ?? const LatLng(52.52, 13.405));
    final map = FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        // Larger rotation threshold so a pinch-zoom doesn't tilt the map by
        // accident; programmatic moveAndRotate (live recenter) is unaffected.
        interactionOptions: const InteractionOptions(
          enableMultiFingerGestureRace: true,
        ),
        initialCameraFit: !live && route.length >= 2
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(route),
                padding: _routeFitPadding,
              )
            : null,
      ),
      children: [
        _tiles(isDark ? _darkBase : _lightBase, tint: isDark),
        _tiles(isDark ? _darkLabels : _lightLabels),
        if (route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: route, strokeWidth: 5, color: primary),
            ],
          ),
        if (live && route.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: route.last,
                width: 44,
                height: 44,
                child: _liveMarker(context.ink),
              ),
            ],
          ),
        if (!live && route.length >= 2)
          MarkerLayer(
            markers: [
              _startMarker(context.ink, route.first),
              _finishMarker(context.ink, route.last),
            ],
          ),
        if (highlight != null)
          MarkerLayer(
            markers: [
              Marker(
                point: highlight!,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    // Neutral hover point, not a series colour: white on dark,
                    // black on light, ringed by its opposite to stay visible.
                    color: isDark ? Colors.white : Colors.black,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? Colors.black : Colors.white,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
    // Zoom + fit-route controls, mirroring the web route map. Only on the static
    // detail map (a live recording drives the camera itself) and only with a
    // route to frame; they need the caller's controller to move the camera.
    final showControls = !live && controller != null && route.length >= 2;
    if (!showControls) {
      return map;
    }
    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: 12,
          left: 12,
          child: _ZoomControls(controller: controller!),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: MapOverlayButton(
            icon: PhosphorIconsBold.cornersOut,
            tooltipKey: 'sport.trainings.reset_view',
            onTap: () => controller!.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(route),
                padding: _routeFitPadding,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Where the recording is now: an accent dot ringed in the page colour, in
  /// a soft halo so it stays findable on the tinted map.
  Widget _liveMarker(InsulinkColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.9),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: colors.accent,
          shape: BoxShape.circle,
          border: Border.all(color: colors.ground, width: 3),
        ),
      ),
    );
  }

  /// The start as a small light dot ringed in the page colour, no icon: the
  /// finish is the route's one marker. Same on every map in the app.
  Marker _startMarker(InsulinkColors colors, LatLng point) {
    return Marker(
      point: point,
      width: 17,
      height: 17,
      child: Container(
        decoration: BoxDecoration(
          color: colors.text,
          shape: BoxShape.circle,
          border: Border.all(color: colors.ground, width: 3),
        ),
      ),
    );
  }

  /// The finish: a light disc with a dark flag, no colour, so neither end of
  /// the route reads as good or bad.
  Marker _finishMarker(InsulinkColors colors, LatLng point) {
    return Marker(
      point: point,
      width: 32,
      height: 32,
      child: Container(
        decoration: BoxDecoration(
          color: colors.text,
          shape: BoxShape.circle,
          border: Border.all(color: colors.ground, width: 2),
        ),
        child: Icon(PhosphorIconsFill.flag, color: colors.ground, size: 16),
      ),
    );
  }

  /// One tile layer of the basemap. Two of them are stacked (map, then place
  /// names), so the settings that matter live in one place.
  ///
  /// [tint] recolours the tile, and is what the two-layer split buys us: Esri's
  /// dark canvas is a mid grey that glows against this app's much darker page,
  /// but tinting the whole map would take the place names down with it. Only
  /// the BASE layer is tinted; the labels stay as bright as they were.
  Widget _tiles(String urlTemplate, {bool tint = false}) {
    return TileLayer(
      urlTemplate: urlTemplate,
      maxNativeZoom: _maxNativeZoom,
      userAgentPackageName: 'de.insulink.app',
      tileBuilder: tint ? _tintTiles : null,
      // Degrade quietly without network (e.g. in the emulator) instead of
      // logging every missing tile as an exception.
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
      errorTileCallback: (tile, error, stackTrace) {},
    );
  }

  /// Turns the grey dark canvas into the app's own slate: each pixel's
  /// brightness is laid out from the page colour (black, the water) up to
  /// the line colour (a road), so the map sits in the palette of the panels
  /// around it instead of a neutral grey.
  Widget _tintTiles(BuildContext context, Widget tile, TileImage image) {
    final colors = context.ink;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_tintMatrix(colors.ground, colors.line)),
      child: tile,
    );
  }

  List<double> _tintMatrix(Color dark, Color road) {
    List<double> row(double from, double to) {
      final span = (to - from) / _roadLuminance;
      return [0.2126 * span, 0.7152 * span, 0.0722 * span, 0, from * 255];
    }

    return [
      ...row(dark.r, road.r),
      ...row(dark.g, road.g),
      ...row(dark.b, road.b),
      0, 0, 0, 1, 0, //
    ];
  }
}

/// The stacked zoom-in / zoom-out buttons overlaid on the detail map — each
/// nudges the camera one level.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.controller});

  final MapController controller;

  void _zoomBy(double delta) {
    final camera = controller.camera;
    controller.move(camera.center, camera.zoom + delta);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MapOverlayButton(
          icon: PhosphorIconsBold.plus,
          tooltipKey: 'sport.trainings.zoom_in',
          onTap: () => _zoomBy(1),
        ),
        const SizedBox(height: 8),
        MapOverlayButton(
          icon: PhosphorIconsBold.minus,
          tooltipKey: 'sport.trainings.zoom_out',
          onTap: () => _zoomBy(-1),
        ),
      ],
    );
  }
}

/// One round button floating over a map (zoom, fit, and the live training's
/// back and pause): 44 px, the page colour at 85 % so the tiles
/// show faintly through, the glyph in the text colour.
class MapOverlayButton extends StatelessWidget {
  const MapOverlayButton({
    super.key,
    required this.icon,
    required this.tooltipKey,
    required this.onTap,
  });

  final IconData icon;
  final String tooltipKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Tooltip(
      message: Locales.string(context, tooltipKey),
      child: Material(
        color: colors.ground.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: InkSpace.minTouch,
            child: Icon(icon, size: 20, color: colors.text),
          ),
        ),
      ),
    );
  }
}
