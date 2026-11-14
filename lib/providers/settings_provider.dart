import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider;

/// 설정 화면에서 고른 값.
class SettingsState {
  const SettingsState({
    this.decimalPlaces = autoDecimalPlaces,
    this.themeMode = ThemeMode.light,
  });

  /// 사용자가 자릿수를 고르지 않은 자동 상태를 나타내는 값.
  static const int autoDecimalPlaces = -1;

  /// 자동일 때 국가 통화의 최대 소수점 자릿수.
  static const int autoFiatDecimalPlaces = 2;

  /// 자동일 때 암호화폐의 최대 소수점 자릿수.
  static const int autoCryptoDecimalPlaces = 5;

  /// 자동 선택지의 이름. 실제로 쓰는 자릿수를 함께 보여준다.
  static const String autoDecimalPlacesLabel =
      '자동 (통화 $autoFiatDecimalPlaces자리 · 코인 $autoCryptoDecimalPlaces자리)';

  /// 사용자가 고른 값. -1이면 자동.
  final int decimalPlaces;
  final ThemeMode themeMode;

  /// 실제로 쓸 최대 소수점 자릿수. 자동이면 국가 통화 2자리, 암호화폐 5자리.
  int decimalPlacesFor({required bool isCrypto}) =>
      resolveDecimalPlaces(decimalPlaces, isCrypto: isCrypto);

  /// 설정값 [setting](-1이면 자동)을 통화 종류에 맞는 실제 자릿수로 바꾼다.
  static int resolveDecimalPlaces(int setting, {required bool isCrypto}) {
    if (setting != autoDecimalPlaces) {
      return setting;
    }

    return isCrypto ? autoCryptoDecimalPlaces : autoFiatDecimalPlaces;
  }

  bool get isDarkMode => themeMode == ThemeMode.dark;

  String get decimalPlacesLabel {
    if (decimalPlaces == autoDecimalPlaces) {
      return autoDecimalPlacesLabel;
    }

    return '$decimalPlaces';
  }

  SettingsState copyWith({int? decimalPlaces, ThemeMode? themeMode}) {
    return SettingsState(
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void changeDecimalPlaces(int value) {
    if (state.decimalPlaces == value) {
      return;
    }

    state = state.copyWith(decimalPlaces: value);
  }

  void toggleTheme() {
    state = state.copyWith(
      themeMode: state.isDarkMode ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
