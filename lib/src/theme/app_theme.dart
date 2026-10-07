import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/theme/insulin_colors.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// The app's light and dark Material 3 themes, both built from the
/// [InsulinkColors] tokens by one builder. Because one builder sets every role
/// for both, a role can no longer be set in one theme and forgotten in the
/// other (`docs/DESIGN.md`, "the one rule").
class AppTheme {
  const AppTheme._();

  /// Every button is a pill (`docs/redesign/DESIGN.md`, "Buttons").
  static const StadiumBorder _buttonShape = StadiumBorder();

  /// The redesign's button height. The width stays the call site's: a minimum
  /// of [double.infinity] would break every button that sits in a [Row].
  static const Size _buttonSize = Size(64, 54);

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
      fontFamily: InkText.fontFamily,
      textTheme: _tabularFigures,
      primaryColor: tokens.text,
      colorScheme: _scheme(tokens, brightness),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: _buttonShape,
          minimumSize: _buttonSize,
          textStyle: InkText.button,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: _buttonShape,
          minimumSize: _buttonSize,
          textStyle: InkText.button,
        ),
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
      inputDecorationTheme: _inputTheme(tokens),
      bottomSheetTheme: _sheetTheme(tokens),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        shape: const CircleBorder(),
        sizeConstraints: const BoxConstraints.tightFor(width: 62, height: 62),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.ground,
        titleTextStyle: InkText.pageTitle.copyWith(color: tokens.text),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: tokens.dock,
      ),
      scaffoldBackgroundColor: tokens.ground,
      pageTransitionsTheme: _pageTransitions(tokens),
      dividerColor: tokens.line,
      extensions: _extensions(tokens, brightness),
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

  /// Every pushed page fades forward over the page colour on Android (the
  /// panel colour Material would use flashes on the darker ground); iOS keeps
  /// its own swipe-back transition.
  static PageTransitionsTheme _pageTransitions(InsulinkColors tokens) {
    return PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
          backgroundColor: tokens.ground,
        ),
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
      },
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
        minimumSize: _buttonSize,
        textStyle: InkText.button,
        foregroundColor: tokens.accent,
        side: BorderSide(color: tokens.accent.withValues(alpha: 0.55)),
      ),
    );
  }

  /// Filled, borderless text fields in the page colour, sunk into the panel or
  /// sheet they sit in; focus draws a thin accent ring and the floating label
  /// stays muted instead of becoming a second accent in the field's corner. A
  /// field standing directly on the page sets the panel colour itself.
  static InputDecorationTheme _inputTheme(InsulinkColors tokens) {
    OutlineInputBorder ring(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(InkRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: tokens.ground,
      hintStyle: TextStyle(color: tokens.muted.withValues(alpha: 0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: ring(Colors.transparent, 0),
      enabledBorder: ring(Colors.transparent, 0),
      focusedBorder: ring(tokens.accent, 1.5),
      floatingLabelStyle: TextStyle(color: tokens.muted),
    );
  }

  /// Sheets in the panel colour with large top corners. Their grab handle is
  /// the shared `GrabHandle`, so Material's own handle stays off.
  static BottomSheetThemeData _sheetTheme(InsulinkColors tokens) {
    return BottomSheetThemeData(
      backgroundColor: tokens.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(InkRadius.sheet),
        ),
      ),
    );
  }

  /// The older extensions, now fed from the tokens. Basal is the accent mixed
  /// into the panel: the same hue as bolus, but quieter. The redesign asks for
  /// 32 %, which lands just under 2:1 against the panel the bars stand on; 34 %
  /// on dark and 42 % on the white light panel keep 2:1 and look the same.
  static List<ThemeExtension<dynamic>> _extensions(
    InsulinkColors tokens,
    Brightness brightness,
  ) {
    final basalShare = brightness == Brightness.dark ? 0.34 : 0.42;
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
        basal: Color.lerp(tokens.panel, tokens.accent, basalShare)!,
        bolus: tokens.accent,
      ),
    ];
  }
}
