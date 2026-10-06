import 'package:flutter/material.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/theme/insulin_colors.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// The app's light and dark Material 3 themes, both built from the
/// [InsulinkColors] tokens by one builder. Because one builder sets every role
/// for both, a role can no longer be set in one theme and forgotten in the
/// other (`docs/DESIGN.md`, "the one rule").
class AppTheme {
  const AppTheme._();

  /// Shared corner radius for every button, so the whole app matches.
  static const double buttonRadius = 14;

  /// The bundled typeface (`assets/fonts/`, declared in `pubspec.yaml`).
  static const String fontFamily = 'AtkinsonHyperlegibleNext';

  static final RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(buttonRadius),
  );

  static final ThemeData light = _build(InsulinkColors.light, Brightness.light);
  static final ThemeData dark = _build(InsulinkColors.dark, Brightness.dark);

  /// Every slot pulls the same token in both themes. The surface ladder is
  /// mixed from `panel` toward `line`, which steps DOWN from the white panel on
  /// light and UP from the dark panel on dark, as the badges inside a box need.
  static ThemeData _build(InsulinkColors tokens, Brightness brightness) {
    final raised = Color.lerp(tokens.panel, tokens.line, 0.7)!;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      textTheme: _tabularFigures,
      primaryColor: tokens.text,
      colorScheme: _scheme(tokens, brightness),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: _buttonShape),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: _buttonShape),
      ),
      outlinedButtonTheme: _outlinedButtons(tokens),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: _buttonShape,
          foregroundColor: tokens.text,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: tokens.text),
      ),
      inputDecorationTheme: _inputTheme(raised, tokens),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(backgroundColor: tokens.ground),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: tokens.dock,
      ),
      scaffoldBackgroundColor: tokens.ground,
      dividerColor: tokens.line,
      extensions: _extensions(tokens),
    );
  }

  /// `primary` is the accent and `onPrimary` the token drawn on it, as the
  /// redesign asks: on dark that is a light indigo fill with dark content.
  /// `outline` and `onSurfaceVariant` must be set, or they alias to pure
  /// white/black and to full-strength text.
  static ColorScheme _scheme(InsulinkColors tokens, Brightness brightness) {
    final constructor = brightness == Brightness.dark
        ? ColorScheme.dark
        : ColorScheme.light;
    return constructor(
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      secondary: tokens.accent,
      surface: tokens.panel,
      onSurface: tokens.text,
      surfaceContainerHigh: Color.lerp(tokens.panel, tokens.line, 0.35),
      surfaceContainerHighest: Color.lerp(tokens.panel, tokens.line, 0.7),
      outline: Color.lerp(tokens.line, tokens.muted, 0.4),
      outlineVariant: tokens.line,
      onSurfaceVariant: tokens.muted,
      error: tokens.low,
      onError: tokens.onAccent,
    );
  }

  /// Numbers are always tabular, so values that tick (timer, glucose, steps)
  /// don't jitter sideways. Merged into Material's defaults by [ThemeData], so
  /// every role keeps its size and only gains the feature; inline styles
  /// inherit it through the default text style.
  static const TextStyle _tabular = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextTheme _tabularFigures = TextTheme(
    displayLarge: _tabular,
    displayMedium: _tabular,
    displaySmall: _tabular,
    headlineLarge: _tabular,
    headlineMedium: _tabular,
    headlineSmall: _tabular,
    titleLarge: _tabular,
    titleMedium: _tabular,
    titleSmall: _tabular,
    bodyLarge: _tabular,
    bodyMedium: _tabular,
    bodySmall: _tabular,
    labelLarge: _tabular,
    labelMedium: _tabular,
    labelSmall: _tabular,
  );

  /// [OutlinedButton] would otherwise take `primary` as its label and an
  /// aliased `outline` as its rim; both are stated here.
  static OutlinedButtonThemeData _outlinedButtons(InsulinkColors tokens) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _buttonShape,
        foregroundColor: tokens.accent,
        side: BorderSide(color: tokens.accent.withValues(alpha: 0.55)),
      ),
    );
  }

  /// Filled, borderless text fields with a soft rounded shape; focus draws a
  /// thin accent ring and the floating label stays muted instead of becoming a
  /// second accent in the field's corner.
  static InputDecorationTheme _inputTheme(Color fill, InsulinkColors tokens) {
    OutlineInputBorder ring(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(buttonRadius),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: ring(Colors.transparent, 0),
      enabledBorder: ring(Colors.transparent, 0),
      focusedBorder: ring(tokens.accent, 1.6),
      floatingLabelStyle: TextStyle(color: tokens.muted),
    );
  }

  /// The older extensions, now fed from the tokens. Basal is the accent drained
  /// halfway into the panel: the same hue as bolus, but quieter.
  static List<ThemeExtension<dynamic>> _extensions(InsulinkColors tokens) {
    return [
      tokens,
      GlucoseColors(inRange: tokens.range, low: tokens.low, high: tokens.high),
      AccentColors(onSurface: tokens.accent),
      StatusColors(
        danger: tokens.low,
        warning: tokens.high,
        positive: tokens.range,
      ),
      InsulinColors(
        basal: Color.lerp(tokens.accent, tokens.panel, 0.5)!,
        bolus: tokens.accent,
      ),
    ];
  }
}
