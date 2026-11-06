import 'dart:math' as math;

import '../../domain/exchange/exchange_calculator.dart';

/// 같은 금액을 선택일 환율과 최신 환율로 환산해 비교한 결과.
class ChartRateComparison {
  const ChartRateComparison({
    required this.selectedAmount,
    required this.latestAmount,
  });

  final double selectedAmount;
  final double latestAmount;

  // 부동소수 오차로 볼 차이의 비율. 경로가 다른 계산의 오차(수 ulp, 약 1e-15)보다
  // 넉넉히 크고, 큰 환율의 실제 움직임(1억대 환율의 0.01이 약 7e-11)보다는 작다.
  static const _noiseRatio = 1e-12;

  /// 최신 환산액 − 선택일 환산액. 부동소수 오차뿐인 차이는 0이다.
  /// 허용오차가 두 금액의 크기에 비례하므로 아주 작은 금액의 실제 차이는 남는다.
  double get difference {
    final raw = latestAmount - selectedAmount;
    final scale = math.max(selectedAmount.abs(), latestAmount.abs());
    return raw.abs() <= scale * _noiseRatio ? 0 : raw;
  }

  /// 금액이나 환율로 계산할 수 없으면 null이다.
  static ChartRateComparison? of({
    required double? amount,
    required double? selectedRate,
    required double? latestRate,
  }) {
    const calculator = ExchangeCalculator();
    if (amount == null ||
        !calculator.isValidRate(selectedRate) ||
        !calculator.isValidRate(latestRate)) {
      return null;
    }
    final selected = calculator.convertFromBase(
      baseAmount: amount,
      rate: selectedRate!,
    );
    final latest = calculator.convertFromBase(
      baseAmount: amount,
      rate: latestRate!,
    );
    if (!selected.isFinite || !latest.isFinite) return null;
    return ChartRateComparison(selectedAmount: selected, latestAmount: latest);
  }
}
