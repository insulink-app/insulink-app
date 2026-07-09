/// A scanned food product with its nutrition per 100 g/ml, keyed by [barcode].
class FoodProduct {
  const FoodProduct({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.carbs100g,
    required this.fat100g,
    required this.protein100g,
    required this.kcal100g,
  });

  final String barcode;
  final String name;
  final String brand;
  final double carbs100g;
  final double fat100g;
  final double protein100g;
  final double kcal100g;

  factory FoodProduct.fromJson(Map<String, dynamic> json) => FoodProduct(
    barcode: json['barcode'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String? ?? '',
    carbs100g: (json['carbs'] as num).toDouble(),
    fat100g: (json['fat'] as num).toDouble(),
    protein100g: (json['protein'] as num).toDouble(),
    kcal100g: (json['kcal'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'brand': brand,
    'carbs': carbs100g,
    'fat': fat100g,
    'protein': protein100g,
    'kcal': kcal100g,
  };
}
