import 'package:flutter/material.dart';

import '../models/currency_model.dart';
import '../services/exchange_api_service.dart';
import '../services/local_storage_service.dart';

class ExchangeProvider extends ChangeNotifier {
  final ExchangeApiService _apiService = ExchangeApiService();
  final LocalStorageService _localStorageService = LocalStorageService();

  CurrencyModel _baseCurrency = findCurrencyByCode('KRW');

  List<CurrencyModel> _visibleCurrencies = [];

  double _inputAmount = 10000;
  Map<String, double> _rates = {};
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastUpdated;

  CurrencyModel get baseCurrency => _baseCurrency;
  List<CurrencyModel> get visibleCurrencies => _visibleCurrencies;
  double get inputAmount => _inputAmount;
  Map<String, double> get rates => _rates;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;

  List<CurrencyModel> get allRows {
    return [_baseCurrency, ..._visibleCurrencies];
  }

  Future<void> initialize() async {
    await _loadSavedState();
    await fetchRates();
  }

  Future<void> _loadSavedState() async {
    final savedBaseCode = await _localStorageService.loadBaseCurrency();
    final savedVisibleCodes = await _localStorageService
        .loadVisibleCurrencies();
    final savedRates = await _localStorageService.loadCachedRates();
    final savedLastUpdated = await _localStorageService.loadLastUpdated();
    final savedAmount = await _localStorageService.loadInputAmount();

    if (savedBaseCode != null) {
      _baseCurrency = findCurrencyByCode(savedBaseCode);
    }

    if (savedVisibleCodes != null && savedVisibleCodes.isNotEmpty) {
      _visibleCurrencies = savedVisibleCodes
          .where((code) => code != _baseCurrency.code)
          .map(findCurrencyByCode)
          .toList();
    }

    if (savedRates != null) {
      _rates = savedRates;
    }

    if (savedLastUpdated != null) {
      _lastUpdated = savedLastUpdated;
    }

    if (savedAmount != null) {
      _inputAmount = savedAmount;
    }

    notifyListeners();
  }

  Future<void> fetchRates() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final targetCodes = _visibleCurrencies.map((e) => e.code).toList();

      final latestRates = await _apiService.fetchLatestRates(
        baseCurrency: _baseCurrency.code,
        targetCurrencies: targetCodes,
      );

      _rates = latestRates;
      _lastUpdated = DateTime.now();

      await _localStorageService.saveCachedRates(_rates);
      await _localStorageService.saveLastUpdated(_lastUpdated!);
    } catch (e) {
      final cachedRates = await _localStorageService.loadCachedRates();

      if (cachedRates != null && cachedRates.isNotEmpty) {
        _rates = cachedRates;
        _errorMessage = '최신 환율을 불러오지 못했습니다. 마지막 저장 데이터를 표시합니다.';
      } else {
        _errorMessage = '환율 데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> changeAmount(double amount) async {
    _inputAmount = amount;
    await _localStorageService.saveInputAmount(amount);
    notifyListeners();
  }

  Future<void> changeBaseCurrency(CurrencyModel currency) async {
    if (_baseCurrency.code == currency.code) {
      return;
    }

    final oldBase = _baseCurrency;

    _visibleCurrencies.removeWhere((item) => item.code == currency.code);

    if (!_visibleCurrencies.any((item) => item.code == oldBase.code)) {
      _visibleCurrencies.insert(0, oldBase);
    }

    _baseCurrency = currency;

    await _saveCurrencyState();
    await fetchRates();
  }

  Future<void> replaceVisibleCurrency({
    required int index,
    required CurrencyModel newCurrency,
  }) async {
    if (newCurrency.code == _baseCurrency.code) {
      return;
    }

    final duplicateIndex = _visibleCurrencies.indexWhere(
      (item) => item.code == newCurrency.code,
    );

    if (duplicateIndex != -1 && duplicateIndex != index) {
      return;
    }

    _visibleCurrencies[index] = newCurrency;

    await _saveCurrencyState();
    await fetchRates();
  }

  Future<void> applyVisibleCurrencies(List<CurrencyModel> currencies) async {
    _visibleCurrencies = currencies
        .where((currency) => currency.code != _baseCurrency.code)
        .toList();

    await _saveCurrencyState();
    await fetchRates();
  }

  Future<void> addCurrency(CurrencyModel currency) async {
    if (currency.code == _baseCurrency.code) {
      return;
    }

    if (_visibleCurrencies.any((item) => item.code == currency.code)) {
      return;
    }

    _visibleCurrencies.add(currency);

    await _saveCurrencyState();
    await fetchRates();
  }

  Future<void> removeCurrency(CurrencyModel currency) async {
    if (currency.code == _baseCurrency.code) {
      _errorMessage = '기준 통화는 삭제할 수 없습니다.';
      notifyListeners();
      return;
    }

    _visibleCurrencies.removeWhere((item) => item.code == currency.code);

    await _saveCurrencyState();
    await fetchRates();
  }

  double convertedAmount(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return _inputAmount;
    }

    final rate = _rates[targetCode];

    if (rate == null) {
      return 0;
    }

    return _inputAmount * rate;
  }

  double? rateFor(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return 1;
    }

    return _rates[targetCode];
  }

  Future<void> _saveCurrencyState() async {
    await _localStorageService.saveBaseCurrency(_baseCurrency.code);
    await _localStorageService.saveVisibleCurrencies(
      _visibleCurrencies.map((e) => e.code).toList(),
    );

    notifyListeners();
  }
}
