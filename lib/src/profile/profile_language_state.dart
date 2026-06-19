import 'package:flutter/material.dart';

class ProfileLanguageState extends ChangeNotifier {
  String language;

  ProfileLanguageState(this.language);

  get getLanguage => language;

  void setLanguage(language) {
    this.language = language;
    notifyListeners();
  }
}
