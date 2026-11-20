import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, UncontrolledProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/crypto/models/crypto_price.dart';
import 'package:tripbler/crypto/providers/crypto_provider.dart';
import 'package:tripbler/crypto/services/crypto_api_service.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/presentation/exchange/exchange_display_provider.dart';
import 'package:tripbler/presentation/exchange/exchange_display_view.dart';
import 'package:tripbler/providers/exchange/exchange_provider.dart';
import 'package:tripbler/services/exchange_rate_api_service.dart';
import 'package:tripbler/services/local_storage_service.dart';

/// 환율·암호화폐 서비스를 가짜로 바꾸는 override.
List<Override> exchangeOverrides({
  ExchangeRateApiService? fiatApi,
  CryptoApiService? cryptoApi,
  LocalStorageService? storage,
}) => [
  if (fiatApi != null)
    exchangeRateApiServiceProvider.overrideWithValue(fiatApi),
  if (cryptoApi != null) cryptoApiServiceProvider.overrideWithValue(cryptoApi),
  if (storage != null) localStorageServiceProvider.overrideWithValue(storage),
];

/// 테스트 컨테이너 하나에 있는 환율·암호화폐·표시 상태를 읽고 바꾼다.
class ExchangeHarness {
  ExchangeHarness(this.container);

  /// 가짜 서비스로 새 컨테이너를 만든다. 테스트가 끝나면 폐기된다.
  factory ExchangeHarness.create({
    ExchangeRateApiService? fiatApi,
    CryptoApiService? cryptoApi,
    LocalStorageService? storage,
  }) => ExchangeHarness(
    ProviderContainer.test(
      retry: (_, _) => null,
      overrides: exchangeOverrides(
        fiatApi: fiatApi,
        cryptoApi: cryptoApi,
        storage: storage,
      ),
    ),
  );

  final ProviderContainer container;

  late final ExchangeHandle exchange = ExchangeHandle(container);
  late final CryptoHandle crypto = CryptoHandle(container);
  late final DisplayHandle display = DisplayHandle(container, crypto);

  /// 이 컨테이너를 쓰는 위젯 트리.
  Widget scope(Widget child) =>
      UncontrolledProviderScope(container: container, child: child);

  void dispose() => container.dispose();
}

class ExchangeHandle {
  ExchangeHandle(this.container);

  final ProviderContainer container;

  ExchangeNotifier get _notifier => container.read(exchangeProvider.notifier);
  ExchangeState get state => container.read(exchangeProvider);

  CurrencyModel get baseCurrency => state.baseCurrency;
  List<CurrencyModel> get visibleCurrencies => state.visibleCurrencies;
  double get inputAmount => state.inputAmount;
  String get activeInputCurrencyCode => state.activeInputCurrencyCode;
  Map<String, double> get rates => state.rates;
  bool get isLoading => state.isLoading;
  String? get errorMessage => state.errorMessage;
  DateTime? get lastUpdated => state.lastUpdated;
  double? rateFor(String code) => state.rateFor(code);
  double convertedAmount(String code) => state.convertedAmount(code);

  Future<void> initialize() => _notifier.initialize();
  Future<void> fetchRates() => _notifier.fetchRates();
  Future<void> changeBaseCurrency(CurrencyModel currency) =>
      _notifier.changeBaseCurrency(currency);
  Future<void> addCurrency(CurrencyModel currency) =>
      _notifier.addCurrency(currency);
  Future<void> changeAmountFromCurrency({
    required String currencyCode,
    required double amount,
  }) => _notifier.changeAmountFromCurrency(
    currencyCode: currencyCode,
    amount: amount,
  );
}

class CryptoHandle {
  CryptoHandle(this.container);

  final ProviderContainer container;

  CryptoNotifier get _notifier => container.read(cryptoProvider.notifier);
  CryptoState get state => container.read(cryptoProvider);

  List<CryptoCoin> get coins => state.coins;
  List<CryptoCoin> get selectedCoins => state.selectedCoins;
  bool get loading => state.loading;
  String? get catalogError => state.catalogError;
  CryptoPrice? priceFor(String symbol) => state.priceFor(symbol);
  bool isStale(String symbol) => state.isStale(symbol);
  String? errorFor(String symbol) => state.errorFor(symbol);
  bool isLoading(String symbol) => state.isLoading(symbol);

  Future<void> initialize() => _notifier.initialize();
  Future<void> refresh() => _notifier.refresh();
  Future<void> refreshCatalog() => _notifier.refreshCatalog();
  Future<void> select(List<String> symbols) => _notifier.select(symbols);
  Future<void> fetchPrice(String symbol) => _notifier.fetchPrice(symbol);
}

class DisplayHandle {
  DisplayHandle(this.container, this.crypto);

  final ProviderContainer container;
  final CryptoHandle crypto;

  ExchangeDisplayNotifier get _notifier =>
      container.read(exchangeDisplayProvider.notifier);
  ExchangeDisplayState get state => container.read(exchangeDisplayProvider);
  ExchangeDisplayView get view => container.read(exchangeDisplayViewProvider);

  DisplayCurrency get base => view.base;
  List<DisplayCurrency> get available => view.available;
  List<DisplayCurrency> get visible => view.visible;
  String? get activeCrypto => state.activeCrypto;
  double? get krwRate => state.krwRate;
  String? get conversionError => state.conversionError;
  double? amountFor(DisplayCurrency row) => view.rowOf(row).amount;
  bool isActive(DisplayCurrency row) => view.rowOf(row).isActive;

  Future<void> initialize() => _notifier.initialize();
  Future<void> apply(List<DisplayCurrency> rows) => _notifier.apply(rows);
  Future<void> refresh() => _notifier.refresh();
  Future<void> refreshConversion() => _notifier.refreshConversion();
  void selectInput(DisplayCurrency row) => _notifier.selectInput(row);
  Future<void> changeAmount(DisplayCurrency row, double value) =>
      _notifier.changeAmount(row, value);
}
