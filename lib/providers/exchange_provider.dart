import 'dart:collection';

import 'package:flutter/material.dart';

import '../models/currency_model.dart';
import '../services/exchange_api_service.dart';
import '../services/local_storage_service.dart';

/// 환율 관련 상태를 관리하는 Provider.
class ExchangeProvider extends ChangeNotifier {
  ExchangeProvider({
    ExchangeApiService? apiService,
    LocalStorageService? localStorageService,
  })  : _apiService = apiService ?? ExchangeApiService(),
        _localStorageService =
            localStorageService ?? LocalStorageService();

  final ExchangeApiService _apiService;
  final LocalStorageService _localStorageService;

  // 기준 통화, 화면에 표시할 통화 목록, 입력 금액, 환율, 로딩 상태, 오류 메시지, 마지막 업데이트 시각을 관리.
  CurrencyModel _baseCurrency = findCurrencyByCode('KRW');
  List<CurrencyModel> _visibleCurrencies = <CurrencyModel>[];
  double _inputAmount = 10000;
  Map<String, double> _rates = <String, double>{};
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastUpdated;

  bool _hasInitialized = false;
  Future<void>? _initializationFuture;

  // 가장 최근에 시작된 환율 요청을 식별함.
  int _fetchRequestId = 0;
  // 가장 최근에 시작된 환율 요청이 완료되었는지 확인하는 데 사용.
  CurrencyModel get baseCurrency => _baseCurrency;
  // 화면에 표시할 통화 목록을 읽기 전용으로 제공.
  List<CurrencyModel> get visibleCurrencies =>
      UnmodifiableListView(_visibleCurrencies);

  double get inputAmount => _inputAmount;
  // 환율 정보를 읽기 전용으로 제공.
  Map<String, double> get rates => UnmodifiableMapView(_rates);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  // 기준 통화와 화면에 표시할 통화 목록을 합쳐서 읽기 전용으로 제공.
  List<CurrencyModel> get allRows =>
      List<CurrencyModel>.unmodifiable(<CurrencyModel>[
        _baseCurrency,
        ..._visibleCurrencies,
      ]);
  // 초기화 메서드. 이미 초기화된 경우에는 즉시 완료된 Future를 반환.
  Future<void> initialize() {
    if (_hasInitialized) {
      return Future<void>.value();
    }

    final runningInitialization = _initializationFuture;

    if (runningInitialization != null) {
      return runningInitialization;
    }

    final initialization = _runInitialization();
    _initializationFuture = initialization;

    return initialization;
  }
  // 초기화 과정에서 저장된 상태를 불러오고, 환율을 가져오는 비동기 작업을 수행.
  Future<void> _runInitialization() async {
    try {
      await _loadSavedState();
      await fetchRates();

      _hasInitialized = true;
    } finally {
      // 초기화 과정에서 예외가 발생하면 다음 initialize()에서
      // 다시 시도할 수 있도록 실행 중 상태를 해제함.
      _initializationFuture = null;
    }
  }
  // 저장된 상태를 불러오는 비동기 작업. 로컬 스토리지에서 기준 통화, 
  // 화면에 표시할 통화 목록, 환율, 마지막 업데이트 시각, 입력 금액을 불러와서 Provider 상태에 반영.
  Future<void> _loadSavedState() async {
    final savedBaseCode =
        await _localStorageService.loadBaseCurrency();

    final savedVisibleCodes =
        await _localStorageService.loadVisibleCurrencies();

    final savedRates =
        await _localStorageService.loadCachedRates();

    final savedLastUpdated =
        await _localStorageService.loadLastUpdated();

    final savedAmount =
        await _localStorageService.loadInputAmount();

    if (savedBaseCode != null) {
      _baseCurrency = findCurrencyByCode(savedBaseCode);
    }

    if (savedVisibleCodes != null) {
      _visibleCurrencies = _normalizeVisibleCurrencies(
        savedVisibleCodes.map(findCurrencyByCode),
      );
    }

    if (savedRates != null) {
      _rates = Map<String, double>.from(savedRates);
    }

    _lastUpdated = savedLastUpdated;

    if (savedAmount != null) {
      _inputAmount = savedAmount;
    }
  }
  
  // 환율 정보를 가져오는 비동기 작업. 가장 최근에 시작된 요청만 처리하고, 이전 요청은 무시함.
  Future<void> fetchRates() async {
    final requestId = ++_fetchRequestId;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final targetCodes = _visibleCurrencies
          .map((currency) => currency.code)
          .toSet()
          .toList(growable: false);

      if (targetCodes.isEmpty) {
        if (!_isLatestRequest(requestId)) {
          return;
        }

        _rates = <String, double>{};
        _lastUpdated = DateTime.now();
        return;
      }

      final latestRates = await _apiService.fetchLatestRates(
        baseCurrency: _baseCurrency.code,
        targetCurrencies: targetCodes,
      );

      if (!_isLatestRequest(requestId)) {
        return;
      }

      final updatedAt = DateTime.now();

      _rates = Map<String, double>.from(latestRates);
      _lastUpdated = updatedAt;

      try {
        await _localStorageService.saveCachedRates(_rates);
        await _localStorageService.saveLastUpdated(updatedAt);
      } catch (_) {
        if (_isLatestRequest(requestId)) {
          _errorMessage = '최신 환율은 표시했지만 기기에 저장하지 못했습니다.';
        }
      }
    } catch (_) {
      if (!_isLatestRequest(requestId)) {
        return;
      }

      await _restoreCachedRatesAfterFetchFailure();
    } finally {
      if (_isLatestRequest(requestId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
  // 환율 가져오기 실패 시 로컬 캐시에서 환율 정보를 복원하는 비동기 작업.
  Future<void> _restoreCachedRatesAfterFetchFailure() async {
    try {
      final cachedRates =
          await _localStorageService.loadCachedRates();

      if (cachedRates != null && cachedRates.isNotEmpty) {
        _rates = Map<String, double>.from(cachedRates);
        _errorMessage =
            '최신 환율을 불러오지 못했습니다. '
            '마지막 저장 데이터를 표시합니다.';
      } else {
        _errorMessage =
            '환율 데이터를 불러오지 못했습니다. '
            '다시 시도해 주세요.';
      }
    } catch (_) {
      _errorMessage =
          '환율 데이터를 불러오지 못했습니다. '
          '다시 시도해 주세요.';
    }
  }

  Future<void> changeAmount(double amount) async {
    if (_inputAmount == amount) {
      return;
    }

    _inputAmount = amount;

    // 입력 결과는 즉시 화면에 반영함.
    notifyListeners();

    await _localStorageService.saveInputAmount(amount);
  }

  Future<void> changeBaseCurrency(
    CurrencyModel currency,
  ) async {
    if (_baseCurrency.code == currency.code) {
      return;
    }

    final oldBaseCurrency = _baseCurrency;

    _baseCurrency = currency;

    _visibleCurrencies =
        _normalizeVisibleCurrencies(<CurrencyModel>[
      oldBaseCurrency,
      ..._visibleCurrencies.where(
        (item) => item.code != currency.code,
      ),
    ]);

    await _saveCurrencyState();
    await fetchRates();
  }
  // 화면에 표시할 통화 목록에서 특정 위치의 통화를 새로운 통화로 교체하는 비동기 작업.
  Future<void> replaceVisibleCurrency({
    required int index,
    required CurrencyModel newCurrency,
  }) async {
    if (index < 0 || index >= _visibleCurrencies.length) {
      _setErrorMessage('변경할 통화 위치가 올바르지 않습니다.');
      return;
    }

    if (newCurrency.code == _baseCurrency.code) {
      return;
    }

    final duplicateIndex = _visibleCurrencies.indexWhere(
      (item) => item.code == newCurrency.code,
    );

    if (duplicateIndex != -1 && duplicateIndex != index) {
      return;
    }

    if (_visibleCurrencies[index].code == newCurrency.code) {
      return;
    }

    _visibleCurrencies[index] = newCurrency;

    await _saveCurrencyState();
    await fetchRates();
  }

  Future<void> applyVisibleCurrencies(
    List<CurrencyModel> currencies,
  ) async {
    final normalizedCurrencies =
        _normalizeVisibleCurrencies(currencies);

    if (_hasSameCurrencyCodes(
      _visibleCurrencies,
      normalizedCurrencies,
    )) {
      return;
    }

    _visibleCurrencies = normalizedCurrencies;

    await _saveCurrencyState();
    await fetchRates();
  }

  Future<void> addCurrency(
    CurrencyModel currency,
  ) async {
    if (currency.code == _baseCurrency.code ||
        _visibleCurrencies.any(
          (item) => item.code == currency.code,
        )) {
      return;
    }

    _visibleCurrencies.add(currency);

    await _saveCurrencyState();
    await fetchRates();
  }
  // 화면에 표시할 통화 목록에서 특정 통화를 제거하는 비동기 작업. 기준 통화는 제거할 수 없음.
  Future<void> removeCurrency(
    CurrencyModel currency,
  ) async {
    if (currency.code == _baseCurrency.code) {
      _setErrorMessage('기준 통화는 삭제할 수 없습니다.');
      return;
    }

    final previousLength = _visibleCurrencies.length;

    _visibleCurrencies.removeWhere(
      (item) => item.code == currency.code,
    );

    if (_visibleCurrencies.length == previousLength) {
      return;
    }

    await _saveCurrencyState();
    await fetchRates();
  }
  // 입력 금액을 기준으로 특정 통화로 환산한 금액을 계산하는 메서드. 기준 통화와 동일한 경우에는 입력 금액 그대로 반환.
  double convertedAmount(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return _inputAmount;
    }

    final rate = _rates[targetCode];

    return rate == null ? 0 : _inputAmount * rate;
  }

  double? rateFor(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return 1;
    }

    return _rates[targetCode];
  }
  // 기준 통화와 화면에 표시할 통화 목록을 로컬 스토리지에 저장하는 비동기 작업.
  Future<void> _saveCurrencyState() async {
    await _localStorageService.saveBaseCurrency(
      _baseCurrency.code,
    );

    await _localStorageService.saveVisibleCurrencies(
      _visibleCurrencies
          .map((currency) => currency.code)
          .toList(),
    );
  }
  // 화면에 표시할 통화 목록에서 중복된 통화를 제거하고, 기준 통화를 제외한 고유한 통화 목록을 반환하는 메서드.
  List<CurrencyModel> _normalizeVisibleCurrencies(
    Iterable<CurrencyModel> currencies,
  ) {
    final uniqueCurrencies =
        LinkedHashMap<String, CurrencyModel>();

    for (final currency in currencies) {
      if (currency.code == _baseCurrency.code) {
        continue;
      }

      uniqueCurrencies.putIfAbsent(
        currency.code,
        () => currency,
      );
    }

    return uniqueCurrencies.values.toList();
  }
  // 두 통화 목록이 동일한 통화 코드를 가지고 있는지 확인하는 메서드. 
  // 길이가 다르거나, 동일한 위치에 다른 통화 코드가 있으면 false를 반환.
  bool _hasSameCurrencyCodes(
    List<CurrencyModel> first,
    List<CurrencyModel> second,
  ) {
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

  bool _isLatestRequest(int requestId) {
    return requestId == _fetchRequestId;
  }

  void _setErrorMessage(String message) {
    if (_errorMessage == message) {
      return;
    }

    _errorMessage = message;
    notifyListeners();
  }
}