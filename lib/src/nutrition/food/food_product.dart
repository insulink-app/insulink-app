/// A scanned food product with its nutrition per 100 g/ml, keyed by [barcode].
///
/// [unit] is 'g' for solids or 'ml' for drinks, so the portion picker asks for
/// the right measure. [servingSize] is the size of ONE natural serving (one
/// biscuit, one slice, one bar…) in that unit, with [servingLabel] the human
/// text Open Food Facts reported for it (e.g. "1 biscuit (12.5 g)"); both are
/// absent when the product doesn't declare a serving.
class FoodProduct {
  const FoodProduct({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.unit,
    required this.servingSize,
    required this.servingLabel,
    required this.carbs100g,
    required this.fat100g,
    required this.protein100g,
    required this.kcal100g,
  });

  final String barcode;
  final String name;
  final String brand;
  final String unit;
  final double? servingSize;
  final String servingLabel;
  final double carbs100g;
  final double fat100g;
  final double protein100g;
  final double kcal100g;

  /// An empty product for the manual editor. [barcode] carries the scanned code
  /// when a lookup found nothing; a manual entry gets a synthetic id on save.
  factory FoodProduct.blank({String barcode = ''}) => FoodProduct(
    barcode: barcode,
    name: '',
    brand: '',
    unit: 'g',
    servingSize: null,
    servingLabel: '',
    carbs100g: 0,
    fat100g: 0,
    protein100g: 0,
    kcal100g: 0,
  );

  factory FoodProduct.fromJson(Map<String, dynamic> json) => FoodProduct(
    barcode: json['barcode'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String? ?? '',
    unit: json['unit'] as String? ?? 'g',
    servingSize: (json['serving'] as num?)?.toDouble(),
    servingLabel: json['serving_label'] as String? ?? '',
    carbs100g: (json['carbs'] as num).toDouble(),
    fat100g: (json['fat'] as num).toDouble(),
    protein100g: (json['protein'] as num).toDouble(),
    kcal100g: (json['kcal'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'brand': brand,
    'unit': unit,
    'serving': servingSize,
    'serving_label': servingLabel,
    'carbs': carbs100g,
    'fat': fat100g,
    'protein': protein100g,
    'kcal': kcal100g,
  };
}
