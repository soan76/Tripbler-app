/// 환율 금액 계산을 담당하는 순수 계산 클래스.
///
/// [ExchangeProvider]가 직접 수행하던 금액 환산 공식을 분리한다.
///
/// 역할:
/// - 기준 통화 금액을 대상 통화 금액으로 환산
/// - 대상 통화 입력 금액을 기준 통화 금액으로 역산
/// - 계산에 사용할 환율 값의 유효성 검증
class ExchangeCalculator {
  const ExchangeCalculator();

  /// 환율 값이 계산에 사용할 수 있는 값인지 확인한다.
  ///
  /// null, 0, 음수, NaN, Infinity는 정상적인 환율 계산에 사용할 수 없다.
  /// Provider를 포함한 호출부에서도 동일한 검증 규칙을 재사용할 수 있도록
  /// public 메서드로 제공한다.
  bool isValidRate(double? rate) {
    return rate != null && rate.isFinite && rate > 0;
  }

  /// 기준 통화 금액을 대상 통화 금액으로 환산한다.
  ///
  /// 공식:
  /// 대상 통화 금액 = 기준 통화 금액 × 환율
  double convertFromBase({required double baseAmount, required double rate}) {
    _validateRate(rate);

    return baseAmount * rate;
  }

  /// 대상 통화 입력 금액을 기준 통화 금액으로 역산한다.
  ///
  /// 공식:
  /// 기준 통화 금액 = 대상 통화 금액 ÷ 환율
  double convertToBase({required double targetAmount, required double rate}) {
    _validateRate(rate);

    return targetAmount / rate;
  }

  /// 계산 메서드 내부에서도 동일한 검증 규칙을 강제한다.
  ///
  /// 호출부가 [isValidRate]를 먼저 사용하지 않았더라도
  /// 잘못된 환율로 실제 계산이 수행되지 않도록 마지막 방어선 역할을 한다.
  void _validateRate(double rate) {
    if (!isValidRate(rate)) {
      throw ArgumentError.value(rate, 'rate', '환율은 0보다 큰 유한한 값이어야 합니다.');
    }
  }
}
