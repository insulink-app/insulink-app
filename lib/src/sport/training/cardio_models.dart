/// Endurance trainings (GPS): walking, jogging, cycling.
library;

/// Type of endurance training.
enum CardioType { walk, jog, bike }

/// A recorded GPS point: position + timestamp (epoch ms).
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

/// A completed endurance training: type, start/end, recorded route and the
/// distance covered (meters, summed while recording).
class CardioTraining {
  final String id;
  final CardioType type;
  final int startMs;
  final int endMs;
  final List<TrackPoint> track;
  final double distanceM;

  /// True when the training was recognised automatically from the GPS log
  /// (rather than recorded manually) — shown as an "automatic" hint.
  final bool detected;

  const CardioTraining({
    required this.id,
    required this.type,
    required this.startMs,
    required this.endMs,
    required this.track,
    required this.distanceM,
    this.detected = false,
  });

  Duration get duration => Duration(milliseconds: endMs - startMs);

  /// Average speed in km/h (0 when no duration was recorded).
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
    'auto': detected,
    'track': track.map((point) => point.toJson()).toList(),
  };

  factory CardioTraining.fromJson(Map<String, dynamic> json) => CardioTraining(
    id: json['id'] as String,
    type: CardioType.values.byName(json['type'] as String),
    startMs: json['start'] as int,
    endMs: json['end'] as int,
    distanceM: (json['dist'] as num).toDouble(),
    detected: json['auto'] as bool? ?? false,
    track: (json['track'] as List)
        .cast<Map<String, dynamic>>()
        .map(TrackPoint.fromJson)
        .toList(),
  );
}
