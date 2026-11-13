import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/settings_provider.dart';

void main() {
  group('settingsProvider.decimalPlacesFor', () {
    test('자동이면 국가 통화 2자리, 암호화폐 5자리', () {
      final c = ProviderContainer.test();
      final settings = c.read(settingsProvider);

      expect(settings.decimalPlaces, -1);
      expect(settings.decimalPlacesFor(isCrypto: false), 2);
      expect(settings.decimalPlacesFor(isCrypto: true), 5);
      expect(settings.decimalPlacesLabel, '자동 (통화 2자리 · 코인 5자리)');
    });

    test('직접 고른 자릿수는 통화 종류와 상관없이 그대로 쓴다', () {
      final c = ProviderContainer.test();
      final notifier = c.read(settingsProvider.notifier)
        ..changeDecimalPlaces(3);

      expect(c.read(settingsProvider).decimalPlacesFor(isCrypto: false), 3);
      expect(c.read(settingsProvider).decimalPlacesFor(isCrypto: true), 3);
      expect(c.read(settingsProvider).decimalPlacesLabel, '3');

      notifier.changeDecimalPlaces(0);
      expect(c.read(settingsProvider).decimalPlacesFor(isCrypto: true), 0);
    });

    test('같은 자릿수로 바꾸면 알리지 않는다', () {
      final c = ProviderContainer.test();
      var count = 0;
      c.listen(settingsProvider, (_, _) => count++);

      c.read(settingsProvider.notifier).changeDecimalPlaces(-1);

      expect(count, 0);
    });

    test('테마를 라이트와 다크로 번갈아 바꾼다', () {
      final c = ProviderContainer.test();
      final notifier = c.read(settingsProvider.notifier);

      notifier.toggleTheme();
      expect(c.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(c.read(settingsProvider).isDarkMode, isTrue);

      notifier.toggleTheme();
      expect(c.read(settingsProvider).themeMode, ThemeMode.light);
    });
  });
}
