import '../../models/currency_model.dart';

/// 환율 화면에서 사용하는 통화 목록 관련 순수 로직을 담당하는 클래스.
///
/// [ExchangeProvider]가 직접 가지고 있던 다음 책임을 분리한다.
/// - 기준 통화를 제외한 표시 통화 목록 정규화
/// - 표시 통화 중복 제거
/// - 특정 통화가 현재 입력 가능한 통화인지 확인
/// - 두 통화 목록의 순서 비교
/// - 두 통화 목록의 구성 비교
class ExchangeCurrencyManager {
  const ExchangeCurrencyManager();

  /// 표시 통화 목록을 정규화한다.
  ///
  /// 규칙:
  /// 1. 기준 통화와 동일한 통화는 제거한다.
  /// 2. 동일한 통화 코드가 여러 번 들어오면 최초 항목만 유지한다.
  /// 3. 입력 순서는 그대로 유지한다.
  List<CurrencyModel> normalizeVisibleCurrencies({
    required CurrencyModel baseCurrency,
    required Iterable<CurrencyModel> currencies,
  }) {
    final uniqueCurrencies = <String, CurrencyModel>{};

    for (final currency in currencies) {
      if (currency.code == baseCurrency.code) {
        continue;
      }

      uniqueCurrencies.putIfAbsent(currency.code, () => currency);
    }

    return uniqueCurrencies.values.toList(growable: true);
  }

  /// 특정 통화가 현재 환율 입력에 사용할 수 있는 통화인지 확인한다.
  ///
  /// 기준 통화이거나 현재 화면에 표시 중인 통화라면 true를 반환한다.
  bool isAvailableInputCurrency({
    required CurrencyModel baseCurrency,
    required List<CurrencyModel> visibleCurrencies,
    required String currencyCode,
  }) {
    if (baseCurrency.code == currencyCode) {
      return true;
    }

    return visibleCurrencies.any((currency) => currency.code == currencyCode);
  }

  /// 두 표시 통화 목록의 통화 코드와 순서가 모두 동일한지 확인한다.
  bool hasSameOrder(List<CurrencyModel> first, List<CurrencyModel> second) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index].code != second[index].code) {
        return false;
      }
    }

    return true;
  }

  /// 두 표시 통화 목록이 순서와 관계없이 동일한 통화 구성인지 확인한다.
  bool hasSameSet(List<CurrencyModel> first, List<CurrencyModel> second) {
    if (first.length != second.length) {
      return false;
    }

    final firstCodes = first.map((currency) => currency.code).toSet();
    final secondCodes = second.map((currency) => currency.code).toSet();

    final firstHasDuplicates = firstCodes.length != first.length;
    final secondHasDuplicates = secondCodes.length != second.length;

    if (firstHasDuplicates || secondHasDuplicates) {
      return false;
    }

    return firstCodes.length == secondCodes.length &&
        firstCodes.containsAll(secondCodes);
  }
}
