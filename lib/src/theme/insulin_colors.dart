import 'package:flutter/material.dart';

/// The two kinds of insulin, as colours.
///
/// A role of its own rather than borrowed from anywhere else. [GlucoseColors] is
/// the language of glucose and must not move when insulin does, and the accent
/// already means "this is a control you can press". Insulin is neither: it is
/// data, and it has exactly two kinds that must be told apart at a glance.
///
/// Both are drawn from the brand indigo the app already speaks, because insulin
/// is not a warning. [bolus] is the stronger of the two: a dose someone chose,
/// arriving all at once. [basal] is the quieter one: a background drip that is
/// always there, and is meant to read as the floor the boluses stand on.
///
/// Read with `Theme.of(context).extension<InsulinColors>()!`.
@immutable
class InsulinColors extends ThemeExtension<InsulinColors> {
  const InsulinColors({required this.basal, required this.bolus});

  /// The continuous background rate, including whatever the automation runs
  /// in its place.
  final Color basal;

  /// A dose given at a moment.
  final Color bolus;

  @override
  InsulinColors copyWith({Color? basal, Color? bolus}) {
    return InsulinColors(basal: basal ?? this.basal, bolus: bolus ?? this.bolus);
  }

  @override
  InsulinColors lerp(ThemeExtension<InsulinColors>? other, double t) {
    if (other is! InsulinColors) {
      return this;
    }
    return InsulinColors(
      basal: Color.lerp(basal, other.basal, t)!,
      bolus: Color.lerp(bolus, other.bolus, t)!,
    );
  }
}

/// Terse access at the call sites that draw with them.
extension InsulinColorsContext on BuildContext {
  InsulinColors get insulin => Theme.of(this).extension<InsulinColors>()!;
}
