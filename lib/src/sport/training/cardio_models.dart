/// Ausdauer-Trainings (GPS): Gehen, Joggen, Radfahren.
library;

/// Art des Ausdauer-Trainings.
enum CardioType { walk, jog, bike }

/// Ein aufgezeichneter GPS-Punkt: Position + Zeitstempel (epoch ms).
class TrackPoint {
  final double lat;
  final double lng;
  final int tMs;

  const TrackPoint({required this.lat, required this.lng, required this.tMs});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 't': tMs};

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    tMs: json['t'] as int,
  );
}

/// Ein abgeschlossenes Ausdauer-Training: Typ, Start/Ende, aufgezeichnete Route
/// und die zurückgelegte Strecke (Meter, während der Aufzeichnung summiert).
class CardioTraining {
  final String id;
  final CardioType type;
  final int startMs;
  final int endMs;
  final List<TrackPoint> track;
  final double distanceM;

  const CardioTraining({
    required this.id,
    required this.type,
    required this.startMs,
    required this.endMs,
    required this.track,
    required this.distanceM,
  });

  Duration get duration => Duration(milliseconds: endMs - startMs);

  /// Durchschnittsgeschwindigkeit in km/h (0, wenn keine Dauer erfasst).
  double get avgSpeedKmh {
    final seconds = duration.inSeconds;
    return seconds == 0 ? 0 : distanceM / seconds * 3.6;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'start': startMs,
    'end': endMs,
    'dist': distanceM,
    'track': track.map((point) => point.toJson()).toList(),
  };

  factory CardioTraining.fromJson(Map<String, dynamic> json) => CardioTraining(
    id: json['id'] as String,
    type: CardioType.values.byName(json['type'] as String),
    startMs: json['start'] as int,
    endMs: json['end'] as int,
    distanceM: (json['dist'] as num).toDouble(),
    track: (json['track'] as List)
        .cast<Map<String, dynamic>>()
        .map(TrackPoint.fromJson)
        .toList(),
  );
}
