import 'package:flutter/material.dart';

class SettingsProvider extends ChangeNotifier {
  int _decimalPlaces = -1;
  ThemeMode _themeMode = ThemeMode.light;

  int get decimalPlaces => _decimalPlaces;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  String get decimalPlacesLabel {
    if (_decimalPlaces == -1) {
      return '자동';
    }

    return '$_decimalPlaces';
  }

  void changeDecimalPlaces(int value) {
    if (_decimalPlaces == value) {
      return;
    }

    _decimalPlaces = value;
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;

    notifyListeners();
  }
}
