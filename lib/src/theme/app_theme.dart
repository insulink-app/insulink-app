import 'package:flutter/material.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

/// The app's light and dark Material 3 themes. Kept out of `main.dart` so the
/// shell there stays a thin wiring layer.
class AppTheme {
  const AppTheme._();

  /// Shared corner radius for every button, so the whole app matches.
  static const double buttonRadius = 14;

  /// Foreground (text/icon) on primary-coloured (indigo) buttons. White in both
  /// themes; change here to retint every filled/elevated button at once.
  static const Color onPrimary = Colors.white;

  static final RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(buttonRadius),
  );

  static final FilledButtonThemeData _filledButtons = FilledButtonThemeData(
    style: FilledButton.styleFrom(shape: _buttonShape),
  );
  static final ElevatedButtonThemeData _elevatedButtons =
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: _buttonShape),
      );
  static final OutlinedButtonThemeData _outlinedButtons =
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: _buttonShape),
      );
  static final TextButtonThemeData _textButtons = TextButtonThemeData(
    style: TextButton.styleFrom(shape: _buttonShape),
  );

  /// Modern, filled, borderless text fields with a soft rounded shape — the
  /// focused state gets a thin primary ring. One place styles every [TextField]
  /// in the app (auth, sport editors, …).
  static InputDecorationTheme _inputTheme(Color fill, Color primary) {
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
      focusedBorder: ring(primary, 1.6),
    );
  }

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    primaryColor: Colors.black,
    colorScheme: const ColorScheme.light(
      primary: Colors.indigo,
      onPrimary: onPrimary,
      // ponytail: default secondary is teal — align it to the indigo brand so
      // chips/date-pickers stop tinting turquoise.
      secondary: Colors.indigo,
      surface: Color(0xFFE8E8E8),
    ),
    filledButtonTheme: _filledButtons,
    elevatedButtonTheme: _elevatedButtons,
    outlinedButtonTheme: _outlinedButtons,
    textButtonTheme: _textButtons,
    inputDecorationTheme: _inputTheme(const Color(0xFFECECEC), Colors.indigo),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFFAFAFA)),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFFFAFAFA),
    dividerColor: Colors.black12,
    extensions: const [GlucoseColors.standard],
  );

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    primaryColor: Colors.white,
    colorScheme: const ColorScheme.dark(
      primary: Colors.indigoAccent,
      onPrimary: onPrimary,
      secondary: Colors.indigoAccent,
      surface: Color(0xFF1E1E1E),
      surfaceContainerHighest: Color(0xFF2A2A2A),
    ),
    filledButtonTheme: _filledButtons,
    elevatedButtonTheme: _elevatedButtons,
    outlinedButtonTheme: _outlinedButtons,
    textButtonTheme: _textButtons,
    inputDecorationTheme: _inputTheme(
      const Color(0xFF2A2A2A),
      Colors.indigoAccent,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1B1B1B)),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF2A2A2A),
    ),
    scaffoldBackgroundColor: const Color(0xFF1B1B1B),
    dividerColor: const Color(0xFF3B3B3B),
    extensions: const [GlucoseColors.standard],
  );
}
