import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/crypto/models/crypto_history.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_period_policy.dart';

void main() {
  test('crypto periods follow the API table for every chart period', () {
    for (final period in ChartPeriod.values) {
      final inApiTable = CryptoHistory.supportedPeriods.containsKey(
        CryptoHistory.periodCode(period),
      );
      expect(
        ChartPeriodPolicy.supports(period, crypto: true),
        inApiTable,
        reason: period.name,
      );
      expect(CryptoHistory.supports(period), inApiTable, reason: period.name);
    }
  });

  test('every API period maps to a chart period', () {
    final codes = ChartPeriod.values.map(CryptoHistory.periodCode).toSet();
    expect(codes.containsAll(CryptoHistory.supportedPeriods.keys), isTrue);
  });

  test('crypto supports up to one year, fiat supports everything', () {
    expect(
      [
        for (final period in ChartPeriod.values)
          if (ChartPeriodPolicy.supports(period, crypto: true)) period,
      ],
      [
        ChartPeriod.sevenDays,
        ChartPeriod.oneMonth,
        ChartPeriod.threeMonths,
        ChartPeriod.sixMonths,
        ChartPeriod.oneYear,
      ],
    );
    for (final period in ChartPeriod.values) {
      expect(ChartPeriodPolicy.supports(period, crypto: false), isTrue);
    }
  });
}
