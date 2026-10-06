import 'package:flutter/material.dart';

/// The redesign's type roles that Material's [TextTheme] has no slot for.
///
/// Kept apart from the [TextTheme] on purpose: Material draws its own widgets
/// from those roles (`headlineSmall` is every dialog title, `bodyLarge` every
/// text field), so remapping them to these sizes would blow up dialogs and
/// inputs. Colours are left to the call site; family and tabular figures come
/// from the theme.
class InsulinkTextStyles {
  const InsulinkTextStyles._();

  /// The current glucose value.
  static const TextStyle glucoseValue = TextStyle(
    fontSize: 124,
    fontWeight: FontWeight.w800,
    letterSpacing: -6.8,
    height: 0.8,
  );

  /// Section titles: Glucose, Devices, Today.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );

  /// A tile's value and the time-in-range percentage.
  static const TextStyle statValue = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.9,
    height: 1,
  );

  /// Rows and body lines.
  static const TextStyle row = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// Labels and units beside a value.
  static const TextStyle label = TextStyle(fontSize: 14);

  /// Axis and scale labels.
  static const TextStyle axis = TextStyle(fontSize: 11);
}
