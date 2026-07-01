import 'package:flutter/material.dart';

import 'cardio_models.dart';

/// Icon + Lokalisierungs-Key je [CardioType] — geteilt von Section, Recording-
/// und Detail-Seite, damit das Mapping an einer Stelle liegt.
extension CardioTypeUi on CardioType {
  IconData get icon => switch (this) {
    CardioType.walk => Icons.directions_walk,
    CardioType.jog => Icons.directions_run,
    CardioType.bike => Icons.directions_bike,
  };

  String get labelKey => 'sport.trainings.$name';
}

/// Strecke als km mit zwei Nachkommastellen.
String formatDistanceKm(double meters) => '${(meters / 1000).toStringAsFixed(2)} km';

/// Dauer als H:MM:SS bzw. MM:SS.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Geschwindigkeit als km/h mit einer Nachkommastelle.
String formatSpeed(double kmh) => '${kmh.toStringAsFixed(1)} km/h';
