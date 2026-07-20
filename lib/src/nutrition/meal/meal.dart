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
  });

  final DateTime time;
  final double carbs;
  final int glucoseMgdl;
  final double bolus;
  final List<MealEntry> entries;

  /// Total protein across the logged products (0 for a manual carb entry, which
  /// carries no product breakdown).
  double get protein => entries.fold(0, (sum, entry) => sum + entry.protein);

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
  );

  Map<String, dynamic> toJson() => {
    'time': time.millisecondsSinceEpoch,
    'carbs': carbs,
    'glucose': glucoseMgdl,
    'bolus': bolus,
    'entries': entries.map((entry) => entry.toJson()).toList(),
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
    this.barcode = '',
    this.servingSize,
  });

  /// The source product's barcode, so a logged entry can reopen its product.
  /// Empty for older entries logged before this was stored.
  final String barcode;
  final String name;
  final String unit;
  final double amount;
  final double carbs;
  final double protein;

  /// The product's serving size in [unit] (absent when the product declares no
  /// serving). Lets the detail view show how many servings this portion is.
  final double? servingSize;

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
    servingSize: (json['serving'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'unit': unit,
    'amount': amount,
    'carbs': carbs,
    'protein': protein,
    'serving': servingSize,
  };
}
