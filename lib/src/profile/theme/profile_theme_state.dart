import 'package:flutter/material.dart';

class ProfileThemeState extends ChangeNotifier {
  ThemeMode _themeMode;

  ProfileThemeState(String savedTheme)
    : _themeMode = savedTheme == "dark" ? ThemeMode.dark : ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}
