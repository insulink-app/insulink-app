import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:latlong2/latlong.dart';

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
  });

  final List<TrackPoint> points;
  final MapController? controller;
  final bool live;

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
    return FlutterMap(
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
                padding: const EdgeInsets.all(40),
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
        if (route.isNotEmpty)
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
      ],
    );
  }

  /// Brightens + adds a little contrast to the very dark CartoDB dark tiles so
  /// streets and details are legible, without abandoning the dark look. The 5×4
  /// matrix scales each RGB channel by 1.45 and lifts it by +22 (0–255).
  Widget _brightenDarkTiles(BuildContext context, Widget tile, TileImage image) {
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
