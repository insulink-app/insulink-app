import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_colors.dart';

export 'package:insulink/src/theme/insulink_colors.dart';

/// Spacing of the redesign (`docs/redesign/DESIGN.md`, "Layout"). Widgets take
/// their gaps from here instead of repeating the numbers.
abstract final class InkSpace {
  /// Side margin of a page.
  static const double page = 20;

  /// Side margin of a panel, which sits a little wider than the page text.
  static const double panelMargin = 12;

  /// Inner padding of a panel.
  static const double panelPadding = 16;

  /// Space above a section header.
  static const double sectionGap = 28;

  /// Gap between tiles in a grid and between stand-alone cards.
  static const double tileGap = 10;

  /// Smallest touch target.
  static const double minTouch = 44;
}

/// Corner radii of the redesign.
abstract final class InkRadius {
  static const double panel = 20;
  static const double tile = 22;
  static const double field = 16;
  static const double sheet = 28;

  /// Half the 54 px button height: every button is a pill.
  static const double button = 27;

  /// Half the 62 px navigation capsule.
  static const double dock = 31;
}

/// The redesign's type roles. Numbers are always tabular, so values that tick
/// do not jitter sideways.
///
/// Kept apart from the [TextTheme] on purpose: Material draws its own widgets
/// from those roles (`headlineSmall` is every dialog title, `bodyLarge` every
/// text field), so remapping them to these sizes would blow up dialogs and
/// inputs. Colours are left to the call site.
abstract final class InkText {
  /// The bundled typeface (`assets/fonts/`, declared in `pubspec.yaml`).
  static const String fontFamily = 'AtkinsonHyperlegibleNext';

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// The current glucose value.
  static const TextStyle glucoseHero = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 124,
    fontWeight: FontWeight.w800,
    letterSpacing: -6.8,
    height: 0.8,
  );

  /// A tile's value and the time-in-range percentage.
  static const TextStyle bigValue = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.9,
    height: 1,
  );

  /// The name of a device on its detail page.
  static const TextStyle deviceTitle = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.24,
  );

  /// The title of a pushed page, beside its back arrow.
  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );

  /// Section titles: Glucose, Devices, Today.
  static const TextStyle section = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );

  /// The title of a list row.
  static const TextStyle rowTitle = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  /// Rows of a panel and the value of a key/value row.
  static const TextStyle row = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// Body lines.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Labels, subtitles and the unit beside a value.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 14,
  );

  /// A unit set beside a big value.
  static const TextStyle unit = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// Tile labels, dates and column heads.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 13,
  );

  /// Axis and scale labels.
  static const TextStyle axis = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 11,
  );

  /// Button labels.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontFeatures: _tabular,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );
}

/// Terse access to the tokens at the call sites.
extension InsulinkThemeContext on BuildContext {
  InsulinkColors get ink => Theme.of(this).extension<InsulinkColors>()!;
}
