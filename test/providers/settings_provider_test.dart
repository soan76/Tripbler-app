import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/settings_provider.dart';

void main() {
  group('SettingsProvider.decimalPlacesFor', () {
    test('자동이면 국가 통화 2자리, 암호화폐 5자리', () {
      final settings = SettingsProvider();

      expect(settings.decimalPlaces, -1);
      expect(settings.decimalPlacesFor(isCrypto: false), 2);
      expect(settings.decimalPlacesFor(isCrypto: true), 5);
      expect(settings.decimalPlacesLabel, '자동 (통화 2자리 · 코인 5자리)');
    });

    test('직접 고른 자릿수는 통화 종류와 상관없이 그대로 쓴다', () {
      final settings = SettingsProvider()..changeDecimalPlaces(3);

      expect(settings.decimalPlacesFor(isCrypto: false), 3);
      expect(settings.decimalPlacesFor(isCrypto: true), 3);
      expect(settings.decimalPlacesLabel, '3');

      settings.changeDecimalPlaces(0);
      expect(settings.decimalPlacesFor(isCrypto: true), 0);
    });
  });
}
