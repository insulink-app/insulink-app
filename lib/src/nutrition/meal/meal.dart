/// One logged meal: primarily its total [carbs], plus the glucose and bolus it
/// was dosed with and when. [entries] holds the picked products when the bolus
/// was made over the food database (empty for a manual carb entry).
class Meal {
  const Meal({
    required this.time,
    required this.carbs,
    required this.glucoseMgdl,
    required this.bolus,
    required this.entries,
    this.deliveredByPump = false,
  });

  final DateTime time;
  final double carbs;
  final int glucoseMgdl;
  final double bolus;
  final List<MealEntry> entries;

  /// Whether a pump delivered this [bolus] rather than the user injecting it.
  ///
  /// Worth keeping apart: if a pod later turns out to have stopped mid-delivery,
  /// the pump-given doses are the ones whose recorded amount is worth doubting.
  /// Defaults to false, so every meal logged before pump support reads correctly.
  final bool deliveredByPump;

  /// Total protein across the logged products (0 for a manual carb entry, which
  /// carries no product breakdown).
  double get protein => entries.fold(0, (sum, entry) => sum + entry.protein);

  /// Total fat and energy across the entries, or null when no entry knows its
  /// own (a manual carb entry, or entries logged before they were kept).
  double? get fat => _knownTotal((entry) => entry.fat);
  double? get kcal => _knownTotal((entry) => entry.kcal);

  double? _knownTotal(double? Function(MealEntry entry) nutrient) {
    final known = entries.map(nutrient).whereType<double>();
    return known.isEmpty
        ? null
        : known.fold<double>(0, (sum, value) => sum + value);
  }

  /// The photo this meal was estimated from, when one was: every entry of a
  /// photo estimate carries the same id.
  String? get photoId => entries
      .map((entry) => entry.photoId)
      .firstWhere((photoId) => photoId != null, orElse: () => null);

  /// Stable identity of this logged meal: the millisecond it was logged at.
  ///
  /// Object identity cannot serve as one. A sync pull rebuilds the entire log
  /// from storage ([MealState.reload]), and every instance a caller is still
  /// holding is a stranger to the new list from that moment on. Milliseconds
  /// rather than the [DateTime] itself, because the JSON round trip drops the
  /// microseconds [DateTime.now] carries — so the reloaded meal would not even
  /// equal the one that was written.
  int get logKey => time.millisecondsSinceEpoch;

  /// A copy with individual fields replaced — the basis for editing a logged
  /// meal after the fact (see [MealState.updateMeal]).
  Meal copyWith({
    DateTime? time,
    double? carbs,
    int? glucoseMgdl,
    double? bolus,
  }) => Meal(
    time: time ?? this.time,
    carbs: carbs ?? this.carbs,
    glucoseMgdl: glucoseMgdl ?? this.glucoseMgdl,
    bolus: bolus ?? this.bolus,
    entries: entries,
    deliveredByPump: deliveredByPump,
  );

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    time: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
    carbs: (json['carbs'] as num).toDouble(),
    glucoseMgdl: json['glucose'] as int,
    bolus: (json['bolus'] as num).toDouble(),
    entries: (json['entries'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(MealEntry.fromJson)
        .toList(),
    deliveredByPump: json['delivered_by_pump'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'time': time.millisecondsSinceEpoch,
    'carbs': carbs,
    'glucose': glucoseMgdl,
    'bolus': bolus,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    if (deliveredByPump) 'delivered_by_pump': true,
  };
}

/// One product portion inside a [Meal]: the product [name], the [amount] in its
/// [unit] (g/ml), and the [carbs] that portion contributed.
class MealEntry {
  const MealEntry({
    required this.name,
    required this.unit,
    required this.amount,
    required this.carbs,
    required this.protein,
    this.fat,
    this.kcal,
    this.barcode = '',
    this.servingSize,
    this.photoId,
  });

  /// The source product's barcode, so a logged entry can reopen its product.
  /// Empty for older entries logged before this was stored.
  final String barcode;
  final String name;
  final String unit;
  final double amount;
  final double carbs;
  final double protein;

  /// Fat in grams and energy in kcal of this portion. Null for entries logged
  /// before they were kept.
  final double? fat;
  final double? kcal;

  /// The product's serving size in [unit] (absent when the product declares no
  /// serving). Lets the detail view show how many servings this portion is.
  final double? servingSize;

  /// The server's id of the meal photo this entry was estimated from, so the
  /// meal log can show the photo again. Null for every other entry.
  final String? photoId;

  /// Number of servings this portion represents, or null when the product has
  /// no declared serving size.
  double? get servings => (servingSize ?? 0) > 0 ? amount / servingSize! : null;

  factory MealEntry.fromJson(Map<String, dynamic> json) => MealEntry(
    barcode: json['barcode'] as String? ?? '',
    name: json['name'] as String,
    unit: json['unit'] as String? ?? 'g',
    amount: (json['amount'] as num).toDouble(),
    carbs: (json['carbs'] as num).toDouble(),
    protein: (json['protein'] as num?)?.toDouble() ?? 0,
    fat: (json['fat'] as num?)?.toDouble(),
    kcal: (json['kcal'] as num?)?.toDouble(),
    servingSize: (json['serving'] as num?)?.toDouble(),
    photoId: json['photo_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'unit': unit,
    'amount': amount,
    'carbs': carbs,
    'protein': protein,
    'fat': ?fat,
    'kcal': ?kcal,
    'serving': servingSize,
    'photo_id': ?photoId,
  };
}
