import 'package:flutter/material.dart';

import '../sport_format.dart';
import 'cardio_models.dart';

/// Icon + localization key per [CardioType] — shared by the section, recording
/// and detail pages so the mapping lives in one place.
extension CardioTypeUi on CardioType {
  IconData get icon => switch (this) {
    CardioType.walk => Icons.directions_walk,
    CardioType.jog => Icons.directions_run,
    CardioType.bike => Icons.directions_bike,
  };

  String get labelKey => 'sport.trainings.$name';
}

/// Distance as km with two decimals.
String formatDistanceKm(double meters) =>
    '${sportDecimal(meters / 1000, 2)} km';

/// Duration as H:MM:SS or MM:SS.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Speed as km/h with one decimal.
String formatSpeed(double kmh) => '${sportDecimal(kmh, 1)} km/h';

/// Pace as M:SS per km (from seconds per km).
String formatPace(double secPerKm) {
  final total = secPerKm.round();
  final seconds = (total % 60).toString().padLeft(2, '0');
  return '${total ~/ 60}:$seconds /km';
}
