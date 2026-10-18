/// One food on the photographed plate: how many pieces the model counted (0
/// for food without pieces, such as rice or a drink), its edible weight, the
/// carbohydrates, protein and fat of that weight in grams, and its energy in
/// kcal.
class PhotoEstimateItem {
  const PhotoEstimateItem({
    required this.name,
    required this.grams,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.kcal,
    this.count = 0,
  });

  final String name;
  final int count;
  final double grams;
  final double carbs;
  final double protein;
  final double fat;
  final double kcal;

  /// Several foods as one, their weights and nutrients summed. Without a count:
  /// mixed foods have no pieces to correct.
  factory PhotoEstimateItem.combined(
    String name,
    List<PhotoEstimateItem> parts,
  ) => PhotoEstimateItem(
    name: name,
    grams: parts.fold(0, (sum, part) => sum + part.grams),
    carbs: parts.fold(0, (sum, part) => sum + part.carbs),
    protein: parts.fold(0, (sum, part) => sum + part.protein),
    fat: parts.fold(0, (sum, part) => sum + part.fat),
    kcal: parts.fold(0, (sum, part) => sum + part.kcal),
  );

  /// A reply from before the server counted pieces reads as count 0.
  factory PhotoEstimateItem.fromJson(Map<String, dynamic> json) =>
      PhotoEstimateItem(
        name: json['name'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        grams: (json['grams'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
        protein: (json['protein'] as num?)?.toDouble() ?? 0,
        fat: (json['fat'] as num?)?.toDouble() ?? 0,
        kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
      );

  /// Whether the user can correct the count: only food the model counted.
  bool get countable => count > 0;

  /// The same food with [newCount] pieces, weight and nutrients scaled by the
  /// ratio, so every piece keeps the weight the model gave it.
  PhotoEstimateItem recounted(int newCount) {
    final ratio = newCount / count;
    return PhotoEstimateItem(
      name: name,
      count: newCount,
      grams: grams * ratio,
      carbs: carbs * ratio,
      protein: protein * ratio,
      fat: fat * ratio,
      kcal: kcal * ratio,
    );
  }
}
