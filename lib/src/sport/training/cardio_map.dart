import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:latlong2/latlong.dart';

/// OpenStreetMap-Karte mit der Trainings-Route als Polyline. [live] hält den
/// Kartenausschnitt vom Aufrufer gesteuert (recentern beim Aufzeichnen); sonst
/// wird auf die gesamte Route gezoomt. Geteilt von Recording- und Detail-Seite.
class CardioMap extends StatelessWidget {
  const CardioMap({
    super.key,
    required this.points,
    this.controller,
    this.live = false,
  });

  final List<TrackPoint> points;
  final MapController? controller;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final route = [for (final point in points) LatLng(point.lat, point.lng)];
    final center = route.isNotEmpty ? route.last : const LatLng(52.52, 13.405);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        initialCameraFit: !live && route.length >= 2
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(route),
                padding: const EdgeInsets.all(40),
              )
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'de.insulink.app',
        ),
        if (route.length >= 2)
          PolylineLayer(
            polylines: [Polyline(points: route, strokeWidth: 5, color: primary)],
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
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}
