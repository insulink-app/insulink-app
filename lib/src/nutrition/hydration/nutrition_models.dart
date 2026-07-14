import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One logged drink: when it was drunk, how much (ml), and which preset
/// ([kind]) so the today list can render the matching icon.
class DrinkEntry {
  const DrinkEntry({
    required this.atEpochMs,
    required this.ml,
    required this.kind,
  });

  final int atEpochMs;
  final int ml;
  final String kind;

  factory DrinkEntry.fromJson(Map<String, dynamic> json) => DrinkEntry(
    atEpochMs: json['at'] as int,
    ml: json['ml'] as int,
    kind: json['kind'] as String? ?? 'free',
  );

  Map<String, dynamic> toJson() => {'at': atEpochMs, 'ml': ml, 'kind': kind};
}

/// A one-tap drink size. [drinkPresets] is ordered smallest→largest; the free
/// amount entry isn't a preset (it opens a dialog). [amountLabel] is the short
/// text shown under the icon (the drink type is conveyed by [icon]).
class DrinkPreset {
  const DrinkPreset(this.kind, this.ml, this.icon, this.amountLabel);

  final String kind;
  final int ml;
  final IconData icon;
  final String amountLabel;
}

const List<DrinkPreset> drinkPresets = [
  DrinkPreset('glass', 250, PhosphorIconsRegular.pintGlass, '250 ml'),
  DrinkPreset('small_bottle', 700, PhosphorIconsRegular.beerBottle, '0,7 L'),
  DrinkPreset('sodastream', 840, PhosphorIconsRegular.beerBottle, '840 ml'),
  DrinkPreset('large_bottle', 1000, PhosphorIconsRegular.beerBottle, '1 L'),
];

/// Icon for a stored entry's [kind]; free-input entries fall back to a drop.
IconData iconForKind(String kind) {
  for (final preset in drinkPresets) {
    if (preset.kind == kind) {
      return preset.icon;
    }
  }
  return PhosphorIconsRegular.drop;
}

/// Litres with up to two decimals, German comma, trailing zeros trimmed
/// (2.0 → "2", 1.25 → "1,25").
String formatLitres(double litres) {
  var text = litres.toStringAsFixed(2);
  while (text.contains('.') && (text.endsWith('0') || text.endsWith('.'))) {
    text = text.substring(0, text.length - 1);
  }
  return text.replaceAll('.', ',');
}
