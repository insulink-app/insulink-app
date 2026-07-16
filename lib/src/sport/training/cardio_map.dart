import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:latlong2/latlong.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Fit padding for framing the whole route — matches the initial camera fit.
const _routeFitPadding = EdgeInsets.all(40);

/// OpenStreetMap map with the training route as a polyline. [live] keeps the map
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
        TileLayer(
          // CartoDB light/dark matching the app theme.
          urlTemplate: isDark
              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
              : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: RetinaMode.isHighDensity(context),
          userAgentPackageName: 'de.insulink.app',
          // dark_all is very dark — lift brightness/contrast so streets and
          // details stay visible while keeping the dark look.
          tileBuilder: isDark ? _brightenDarkTiles : null,
          // Degrade quietly without network (e.g. in the emulator) instead of
          // logging every missing tile as an exception.
          evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
          errorTileCallback: (tile, error, stackTrace) {},
        ),
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

  /// Brightens + adds a little contrast to the very dark CartoDB dark tiles so
  /// streets and details are legible, without abandoning the dark look. The 5×4
  /// matrix scales each RGB channel by 1.45 and lifts it by +22 (0–255).
  Widget _brightenDarkTiles(
    BuildContext context,
    Widget tile,
    TileImage image,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        1.45, 0, 0, 0, 22, //
        0, 1.45, 0, 0, 22, //
        0, 0, 1.45, 0, 22, //
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
