import '../../domain/exchange/exchange_calculator.dart';
import '../../models/currency_model.dart';

/// 환율 화면이 보여 주는 값.
class ExchangeState {
  const ExchangeState({
    required this.baseCurrency,
    this.visibleCurrencies = const <CurrencyModel>[],
    this.inputAmount = 10000,
    this.inputCurrencyCode,
    this.rates = const <String, double>{},
    this.isLoading = false,
    this.errorMessage,
    this.lastUpdated,
    this.usesFallbackSource = false,
  });

  static const ExchangeCalculator _calculator = ExchangeCalculator();

  // 기준 통화
  final CurrencyModel baseCurrency;

  // 화면에 표시할 통화 목록(기준 통화 제외)
  final List<CurrencyModel> visibleCurrencies;

  // 사용자가 입력한 기준 통화 금액
  final double inputAmount;

  // 사용자가 고른 입력 통화. 고른 적이 없으면 null이고 기준 통화를 입력 통화로 본다.
  final String? inputCurrencyCode;

  // 기준 통화 → 대상 통화 환율
  final Map<String, double> rates;

  final bool isLoading;
  final String? errorMessage;

  // 서버가 환율을 가져온 시각(fetchedAt)
  final DateTime? lastUpdated;

  // 현재 입력 중인 통화 코드
  String get activeInputCurrencyCode => inputCurrencyCode ?? baseCurrency.code;

  // 기준 통화와 화면에 표시할 통화 목록을 합친 목록
  List<CurrencyModel> get allRows => List<CurrencyModel>.unmodifiable(
    <CurrencyModel>[baseCurrency, ...visibleCurrencies],
  );

  // 입력 금액을 기준으로 특정 통화로 환산한 금액.
  // 기준 통화와 동일한 경우에는 입력 금액 그대로 반환.
  double convertedAmount(String targetCode) {
    if (targetCode == baseCurrency.code) {
      return inputAmount;
    }

    final rate = rates[targetCode];

    if (!_calculator.isValidRate(rate)) {
      return 0;
    }

    return _calculator.convertFromBase(baseAmount: inputAmount, rate: rate!);
  }

  // 특정 통화의 환율
  double? rateFor(String targetCode) {
    if (targetCode == baseCurrency.code) {
      return 1;
    }

    return rates[targetCode];
  }

  /// 지금 보여 주는 환율이 서버의 대체 출처에서 온 값인지. 화면은 이때만 안내를 띄운다.
  /// 기기에 저장해 둔 값을 불러오면 출처를 알 수 없어 false로 둔다.
  final bool usesFallbackSource;

  ExchangeState copyWith({
    CurrencyModel? baseCurrency,
    List<CurrencyModel>? visibleCurrencies,
    double? inputAmount,
    String? inputCurrencyCode,
    Map<String, double>? rates,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? lastUpdated,
    bool clearLastUpdated = false,
    bool? usesFallbackSource,
  }) {
    return ExchangeState(
      baseCurrency: baseCurrency ?? this.baseCurrency,
      visibleCurrencies: visibleCurrencies == null
          ? this.visibleCurrencies
          : List<CurrencyModel>.unmodifiable(visibleCurrencies),
      inputAmount: inputAmount ?? this.inputAmount,
      inputCurrencyCode: inputCurrencyCode ?? this.inputCurrencyCode,
      rates: rates == null
          ? this.rates
          : Map<String, double>.unmodifiable(rates),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      lastUpdated: clearLastUpdated ? null : (lastUpdated ?? this.lastUpdated),
      usesFallbackSource: usesFallbackSource ?? this.usesFallbackSource,
    );
  }
}
