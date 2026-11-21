import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/exchange_rate_response.dart';

Map<String, dynamic> _json({Object? source}) => <String, dynamic>{
  'baseCurrency': 'KRW',
  'rates': <String, dynamic>{'USD': 0.0007},
  'rateDate': '2026-11-20',
  'fetchedAt': '2026-11-21T09:00:00',
  'stale': false,
  'source': ?source,
};

void main() {
  test('source가 CURRENCY_API면 대체 출처 값으로 읽는다', () {
    expect(
      ExchangeRateResponse.fromJson(
        _json(source: 'CURRENCY_API'),
      ).fromFallbackSource,
      isTrue,
    );
  });

  test('source가 FRANKFURTER이거나 없거나 모르는 값이면 평소 출처로 읽는다', () {
    for (final source in ['FRANKFURTER', null, 'OTHER', 1]) {
      expect(
        ExchangeRateResponse.fromJson(_json(source: source)).fromFallbackSource,
        isFalse,
        reason: '$source',
      );
    }
  });
}
