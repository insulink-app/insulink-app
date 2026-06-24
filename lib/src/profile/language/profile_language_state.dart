import 'package:flutter/material.dart';

class ProfileLanguageState extends ChangeNotifier {
  String language;

  ProfileLanguageState(this.language);

  String get getLanguage => language;

  void setLanguage(String language) {
    this.language = language;
    notifyListeners();
  }
}
