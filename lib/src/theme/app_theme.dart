import 'package:flutter/material.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

/// The app's light and dark Material 3 themes. Kept out of `main.dart` so the
/// shell there stays a thin wiring layer.
class AppTheme {
  const AppTheme._();

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    primaryColor: Colors.black,
    colorScheme: const ColorScheme.light(
      primary: Colors.indigo,
      // ponytail: default secondary is teal — align it to the indigo brand so
      // chips/date-pickers stop tinting turquoise.
      secondary: Colors.indigo,
      surface: Color(0xFFE8E8E8),
    ),
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
      secondary: Colors.indigoAccent,
      surface: Color(0xFF1E1E1E),
      surfaceContainerHighest: Color(0xFF2A2A2A),
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
