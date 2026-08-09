/// One laboratory HbA1c result: the percentage (DCCT) and when it was measured.
///
/// Percent is the unit German and US labs quote to patients ("mein HbA1c ist
/// 6,8"); the IFCC mmol/mol figure is a pure function of it, so it is derived for
/// display rather than stored.
class Hba1cEntry {
  final int atEpochMs;
  final double percent;

  const Hba1cEntry({required this.atEpochMs, required this.percent});

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(atEpochMs);

  /// The same result in IFCC mmol/mol, the second unit German lab reports print.
  double get mmolPerMol => (percent - 2.15) * 10.929;

  /// Estimated average glucose in mg/dL for this HbA1c (ADAG regression, the
  /// formula the ADA publishes alongside every result).
  double get averageGlucoseMgDl => 28.7 * percent - 46.7;

  Map<String, dynamic> toJson() => {'ts': atEpochMs, 'pct': percent};

  factory Hba1cEntry.fromJson(Map<String, dynamic> json) => Hba1cEntry(
    atEpochMs: json['ts'] as int,
    percent: (json['pct'] as num).toDouble(),
  );
}
