import 'package:flutter/material.dart';
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

/// How far the DARK base map is dimmed. Esri's dark canvas is a mid grey
/// (its land is ~#4D4D4F); at this scale the land comes out around #2A2A2B,
/// just above the app's dark surface (#1F232A) instead of glowing against it.
const _darkDim = 0.55;

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
        _tiles(isDark ? _darkBase : _lightBase, dim: isDark),
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
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        if (!live && route.length >= 2)
          MarkerLayer(
            markers: [
              _badgeMarker(route.first, PhosphorIconsFill.play),
              _badgeMarker(route.last, PhosphorIconsBold.flagCheckered),
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
          child: _MapButton(
            icon: PhosphorIconsBold.arrowsOut,
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

  /// A neutral round start/finish badge — same muted color for both, told apart
  /// by the icon (▶ = start, checkered flag = finish) so the ends read clearly
  /// without a loud red/green.
  Marker _badgeMarker(LatLng point, IconData icon) {
    return Marker(
      point: point,
      width: 30,
      height: 30,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF37474F),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }

  /// One tile layer of the basemap. Two of them are stacked (map, then place
  /// names), so the settings that matter live in one place.
  ///
  /// [dim] darkens the tile, and is what the two-layer split buys us: Esri's
  /// dark canvas is a mid grey that glows against this app's much darker page,
  /// but dimming the whole map would take the place names down with it. Only
  /// the BASE layer is dimmed; the labels stay as bright as they were.
  Widget _tiles(String urlTemplate, {bool dim = false}) {
    return TileLayer(
      urlTemplate: urlTemplate,
      maxNativeZoom: _maxNativeZoom,
      userAgentPackageName: 'de.insulink.app',
      tileBuilder: dim ? _dimTiles : null,
      // Degrade quietly without network (e.g. in the emulator) instead of
      // logging every missing tile as an exception.
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
      errorTileCallback: (tile, error, stackTrace) {},
    );
  }

  /// Scales the base map's brightness to [_darkDim] so its land lands just
  /// above the app's own dark surface: a shade lighter, so the map still reads
  /// as a panel on the page rather than a hole in it.
  Widget _dimTiles(BuildContext context, Widget tile, TileImage image) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        _darkDim, 0, 0, 0, 0, //
        0, _darkDim, 0, 0, 0, //
        0, 0, _darkDim, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: tile,
    );
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
        _MapButton(
          icon: PhosphorIconsBold.plus,
          tooltipKey: 'sport.trainings.zoom_in',
          onTap: () => _zoomBy(1),
        ),
        const SizedBox(height: 8),
        _MapButton(
          icon: PhosphorIconsBold.minus,
          tooltipKey: 'sport.trainings.zoom_out',
          onTap: () => _zoomBy(-1),
        ),
      ],
    );
  }
}

/// One themed, elevated map-overlay button: surface fill so it stays legible on
/// the tiles, icon in the foreground tone.
class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltipKey,
    required this.onTap,
  });

  final IconData icon;
  final String tooltipKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: Locales.string(context, tooltipKey),
      child: Material(
        color: scheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 18, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}
