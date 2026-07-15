import 'dart:math';

/// A single maximum of a generated basal curve: a bump centred on [hour]
/// (0..24, wrapping at midnight) with a relative [weight].
class BasalPeak {
  BasalPeak(this.hour, this.weight);
  double hour;
  double weight;

  Map<String, dynamic> toJson() => {'h': hour, 'w': weight};

  factory BasalPeak.fromJson(Map<String, dynamic> json) =>
      BasalPeak((json['h'] as num).toDouble(), (json['w'] as num).toDouble());
}

/// A named basal-rate profile: one insulin rate (U/h) per hour of the day.
/// Rates can be edited hour-by-hour or regenerated from [dailyTotal] shaped by
/// [peaks] — both are persisted so the generator is restorable when editing
/// the profile again later.
class BasalProfile {
  BasalProfile({
    required this.name,
    required this.rates,
    required this.peaks,
    required this.dailyTotal,
  });

  String name;
  final List<double> rates; // 24 values, index = hour of day
  final List<BasalPeak> peaks;
  double dailyTotal;

  /// Omnipod delivers basal in 0.05 U/h increments; the chart snaps to this.
  static const step = 0.05;
  static const maxRate = 5.0;

  /// Gaussian half-width (hours) of each generated peak.
  static const _peakWidth = 3.0;

  /// Relative floor so a generated curve is never flat-zero between peaks.
  static const _baseline = 0.5;

  /// Total daily basal insulin (U/day) actually delivered by [rates].
  double get total => rates.fold(0, (sum, rate) => sum + rate);

  factory BasalProfile.initial(String name) => BasalProfile(
    name: name,
    rates: List<double>.filled(24, 1.0),
    peaks: [BasalPeak(5, 1.0)],
    dailyTotal: 24,
  );

  BasalProfile copy() => BasalProfile(
    name: name,
    rates: List<double>.of(rates),
    peaks: peaks.map((peak) => BasalPeak(peak.hour, peak.weight)).toList(),
    dailyTotal: dailyTotal,
  );

  void setHour(int hour, double rate) {
    rates[hour] = snap(rate);
  }

  /// Rebuilds [rates] from [peaks] scaled to [dailyTotal]. Peaks wrap around
  /// midnight so an early-morning bump also lifts the last hours. Rounding to
  /// [step] leaves a small drift from the exact total.
  void regenerate() {
    final raw = List<double>.generate(24, (hour) => _rawAt(hour + 0.5));
    final sum = raw.reduce((a, b) => a + b);
    if (sum <= 0 || dailyTotal <= 0) {
      rates.fillRange(0, 24, 0);
      return;
    }
    for (var hour = 0; hour < 24; hour++) {
      rates[hour] = snap(raw[hour] / sum * dailyTotal);
    }
  }

  double _rawAt(double hour) {
    var value = _baseline;
    for (final peak in peaks) {
      final dist = _circularDist(hour, peak.hour);
      value +=
          peak.weight * exp(-(dist * dist) / (2 * _peakWidth * _peakWidth));
    }
    return value;
  }

  double _circularDist(double a, double b) {
    final raw = (a - b).abs() % 24;
    return min(raw, 24 - raw);
  }

  double snap(double rate) {
    final snapped = (rate / step).round() * step;
    return snapped.clamp(0.0, maxRate);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'rates': rates,
    'peaks': peaks.map((peak) => peak.toJson()).toList(),
    'total': dailyTotal,
  };

  factory BasalProfile.fromJson(Map<String, dynamic> json) => BasalProfile(
    name: json['name'] as String,
    rates: (json['rates'] as List).map((v) => (v as num).toDouble()).toList(),
    peaks: (json['peaks'] as List)
        .map((p) => BasalPeak.fromJson(p as Map<String, dynamic>))
        .toList(),
    dailyTotal: (json['total'] as num).toDouble(),
  );
}
