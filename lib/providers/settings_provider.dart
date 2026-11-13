import 'package:flutter/material.dart';

class SettingsProvider extends ChangeNotifier {
  /// 자동일 때 국가 통화의 최대 소수점 자릿수.
  static const int autoFiatDecimalPlaces = 2;

  /// 자동일 때 암호화폐의 최대 소수점 자릿수.
  static const int autoCryptoDecimalPlaces = 5;

  int _decimalPlaces = -1;
  ThemeMode _themeMode = ThemeMode.light;

  /// 사용자가 고른 값. -1이면 자동.
  int get decimalPlaces => _decimalPlaces;

  /// 실제로 쓸 최대 소수점 자릿수. 자동이면 국가 통화 2자리, 암호화폐 5자리.
  int decimalPlacesFor({required bool isCrypto}) {
    if (_decimalPlaces != -1) {
      return _decimalPlaces;
    }

    return isCrypto ? autoCryptoDecimalPlaces : autoFiatDecimalPlaces;
  }

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// 자동 선택지의 이름. 실제로 쓰는 자릿수를 함께 보여준다.
  static const String autoDecimalPlacesLabel =
      '자동 (통화 $autoFiatDecimalPlaces자리 · 코인 $autoCryptoDecimalPlaces자리)';

  String get decimalPlacesLabel {
    if (_decimalPlaces == -1) {
      return autoDecimalPlacesLabel;
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
