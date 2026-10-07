import 'dart:async';
import '../../services/market_snapshot_store.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../crypto/providers/crypto_provider.dart';
import '../../models/currency_model.dart';
import '../../providers/exchange_provider.dart';
import '../../services/exchange_rate_api_service.dart';
import 'display_currency.dart';

/// 두 도메인의 상태를 화면에서만 조합한다. KRW 연결 환율도 이 계층에서 조회한다.
class ExchangeDisplayProvider extends ChangeNotifier {
  ExchangeDisplayProvider(
    this.exchange,
    this.crypto, {
    ExchangeRateApiService? fiatApi,
  }) : _fiatApi = fiatApi ?? ExchangeRateApiService(),
       _ownsApi = fiatApi == null {
    _base = exchange.baseCurrency.code;
    exchange.addListener(_onExchange);
    crypto.addListener(_notify);
  }
  final ExchangeProvider exchange;
  final CryptoProvider crypto;
  final ExchangeRateApiService _fiatApi;
  final bool _ownsApi;
  List<String> _order = [];
  String? activeCrypto;
  late String _base;
  double? _krwRate;
  final _snapshots = MarketSnapshotStore();
  int _request = 0;
  bool _disposed = false;
  bool _initialized = false;
  Future<void>? _initialization;
  String? conversionError;

  DisplayCurrency get base => DisplayCurrency.fromFiat(exchange.baseCurrency);
  List<DisplayCurrency> get available => [
    ...supportedCurrencies.map(DisplayCurrency.fromFiat),
    ...crypto.coins.map(DisplayCurrency.fromCrypto),
  ];
  List<DisplayCurrency> get visible {
    final rows = [
      ...exchange.visibleCurrencies.map(DisplayCurrency.fromFiat),
      ...crypto.selectedCoins.map(DisplayCurrency.fromCrypto),
    ];
    final byId = {for (final row in rows) row.id: row};
    return [
      for (final id in _order)
        if (byId.containsKey(id)) byId.remove(id)!,
      ...byId.values,
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onExchange() {
    if (_base != exchange.baseCurrency.code) {
      _base = exchange.baseCurrency.code;
      _krwRate = null;
      activeCrypto = null;
      refreshConversion();
    }
    _notify();
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _order = prefs.getStringList('exchange.displayOrder.v1') ?? [];
      await Future.wait([exchange.initialize(), crypto.initialize()]);
      if (_disposed) return;
      unawaited(refreshConversion());
      _initialized = true;
      _notify();
    } finally {
      _initialization = null;
    }
  }

  Future<void> apply(List<DisplayCurrency> rows) async {
    _order = rows.map((row) => row.id).toSet().toList();
    if (!rows.any((row) => row.isCrypto && row.code == activeCrypto)) {
      activeCrypto = null;
    }
    final cryptoUpdate = crypto.select(
      rows.where((row) => row.isCrypto).map((row) => row.code).toList(),
    );
    final fiatUpdate = exchange.applyVisibleCurrencies(
      rows.map((row) => row.fiat).whereType<CurrencyModel>().toList(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('exchange.displayOrder.v1', _order);
    await Future.wait([cryptoUpdate, fiatUpdate, refreshConversion()]);
    _notify();
  }

  Future<void> refresh() async {
    await Future.wait([
      exchange.fetchRates(),
      crypto.refresh(),
      refreshConversion(),
    ]);
  }

  Future<void> refreshConversion() async {
    final request = ++_request;
    final baseCode = exchange.baseCurrency.code;
    conversionError = null;
    if (baseCode == 'KRW' || crypto.selectedCoins.isEmpty) {
      _krwRate = baseCode == 'KRW' ? 1 : null;
      _notify();
      return;
    }
    try {
      if (_krwRate == null) {
        final cached = await _snapshots.read(
          'conversion.$baseCode.KRW',
          const Duration(days: 3),
        );
        if (_disposed || request != _request) return;
        final rate = (cached?['rate'] as num?)?.toDouble();
        if (rate != null && rate.isFinite && rate > 0) {
          _krwRate = rate;
          _notify();
        }
      }
      final response = await _fiatApi.fetchLatestRatesResponse(
        baseCurrency: baseCode,
        targetCurrencies: ['KRW'],
      );
      final rate = response.rates['KRW'];
      if (rate == null || !rate.isFinite || rate <= 0) {
        throw const FormatException();
      }
      if (!_disposed && request == _request) {
        _krwRate = rate;
        if (response.stale) conversionError = '마지막 성공 KRW 환율로 환산하고 있습니다.';
        await _snapshots.write('conversion.$baseCode.KRW', {
          'rate': rate,
          'fetchedAt': response.fetchedAt.toIso8601String(),
        });
      }
    } catch (_) {
      if (!_disposed && request == _request) {
        conversionError = _krwRate == null
            ? '암호화폐 환산에 필요한 KRW 환율을 불러오지 못했습니다.'
            : '갱신 지연으로 마지막 성공 KRW 환율로 환산합니다.';
      }
    }
    _notify();
  }

  double? amountFor(DisplayCurrency row) {
    if (!row.isCrypto) return exchange.convertedAmount(row.code);
    final price = crypto.priceFor(row.code)?.price;
    final rate = exchange.baseCurrency.code == 'KRW' ? 1.0 : _krwRate;
    if (price == null || rate == null) return null;
    final value = exchange.inputAmount * rate / price;
    return value.isFinite ? value : null;
  }

  bool isActive(DisplayCurrency row) => row.isCrypto
      ? activeCrypto == row.code
      : activeCrypto == null && exchange.activeInputCurrencyCode == row.code;
  void selectInput(DisplayCurrency row) {
    activeCrypto = row.isCrypto ? row.code : null;
    if (!row.isCrypto) exchange.selectInputCurrency(row.code);
    _notify();
  }

  Future<void> changeAmount(DisplayCurrency row, double value) async {
    if (!value.isFinite || value < 0) return;
    selectInput(row);
    if (!row.isCrypto) {
      await exchange.changeAmountFromCurrency(
        currencyCode: row.code,
        amount: value,
      );
      return;
    }
    final price = crypto.priceFor(row.code)?.price;
    final rate = exchange.baseCurrency.code == 'KRW' ? 1.0 : _krwRate;
    if (price == null || rate == null) return;
    final amount = value * price / rate;
    if (amount.isFinite) {
      await exchange.changeAmountFromCurrency(
        currencyCode: exchange.baseCurrency.code,
        amount: amount,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    exchange.removeListener(_onExchange);
    crypto.removeListener(_notify);
    if (_ownsApi) _fiatApi.dispose();
    super.dispose();
  }
}
