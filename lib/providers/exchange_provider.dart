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
  }) : _apiService = apiService ?? ExchangeApiService(),
       _localStorageService = localStorageService ?? LocalStorageService();

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
  String? _activeInputCurrencyCode;

  bool _hasInitialized = false;
  Future<void>? _initializationFuture;

  // 가장 최근에 시작된 환율 요청을 식별함.
  int _fetchRequestId = 0;

  // 기준 통화를 제공.
  CurrencyModel get baseCurrency => _baseCurrency;

  // 화면에 표시할 통화 목록을 읽기 전용으로 제공.
  List<CurrencyModel> get visibleCurrencies =>
      UnmodifiableListView(_visibleCurrencies);

  // 사용자가 입력한 기준 통화 금액을 제공.
  double get inputAmount => _inputAmount;

  // 현재 입력 중인 통화 코드를 제공.
  String get activeInputCurrencyCode =>
      _activeInputCurrencyCode ?? _baseCurrency.code;

  // 환율 정보를 읽기 전용으로 제공.
  Map<String, double> get rates => UnmodifiableMapView(_rates);

  // 로딩 상태를 제공.
  bool get isLoading => _isLoading;

  // 오류 메시지를 제공.
  String? get errorMessage => _errorMessage;

  // 마지막 환율 업데이트 시각을 제공.
  DateTime? get lastUpdated => _lastUpdated;

  // 기준 통화와 화면에 표시할 통화 목록을 합쳐서 읽기 전용으로 제공.
  List<CurrencyModel> get allRows => List<CurrencyModel>.unmodifiable(
    <CurrencyModel>[_baseCurrency, ..._visibleCurrencies],
  );

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

  // 저장된 상태를 불러오는 비동기 작업.
  // 로컬 스토리지에서 기준 통화, 화면에 표시할 통화 목록, 환율,
  // 마지막 업데이트 시각, 입력 금액을 불러와서 Provider 상태에 반영.
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

  // 환율 정보를 가져오는 비동기 작업.
  // 가장 최근에 시작된 요청만 처리하고, 이전 요청은 무시함.
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

      // Spring Boot 백엔드의 최신 환율 API 응답 전체를 가져옴.
      // rates뿐만 아니라 fetchedAt도 함께 받기 위해 fetchLatestRatesResponse()를 사용함.
      final latestRatesResponse = await _apiService.fetchLatestRatesResponse(
        baseCurrency: _baseCurrency.code,
        targetCurrencies: targetCodes,
      );

      if (!_isLatestRequest(requestId)) {
        return;
      }

      // 백엔드 응답의 rates를 Provider 상태에 반영함.
      _rates = Map<String, double>.from(latestRatesResponse.rates);

      // Flutter에서 DateTime.now()로 만든 시간이 아니라,
      // 백엔드가 환율을 가져온 시각인 fetchedAt을 마지막 업데이트 시각으로 사용함.
      _lastUpdated = latestRatesResponse.fetchedAt;

      try {
        await _localStorageService.saveCachedRates(_rates);
        await _localStorageService.saveLastUpdated(
          latestRatesResponse.fetchedAt,
        );
      } catch (_) {
        if (_isLatestRequest(requestId)) {
          _errorMessage = '최신 환율은 표시했지만 기기에 저장하지 못했습니다.';
        }
      }
    } catch (error) {
      if (!_isLatestRequest(requestId)) {
        return;
      }

      await _restoreCachedRatesAfterFetchFailure(
        fallbackMessage: _cleanErrorMessage(error),
      );
    } finally {
      if (_isLatestRequest(requestId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
  // 오류 메시지를 정리하여 사용자에게 표시할 수 있는 형태로 반환하는 메서드.
  String _cleanErrorMessage(Object error) {
    if (error is ExchangeApiException) {
      return error.message;
    }

    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.replaceFirst('Exception: ', '');
    }

    if (message.trim().isEmpty) {
      return '환율 데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
    }

    return message;
  }

  // 환율 가져오기 실패 시 로컬 캐시에서 환율 정보를 복원하는 비동기 작업.
  Future<void> _restoreCachedRatesAfterFetchFailure({
    required String fallbackMessage,
  }) async {
    try {
      final cachedRates = await _localStorageService.loadCachedRates();

      if (cachedRates != null && cachedRates.isNotEmpty) {
        _rates = Map<String, double>.from(cachedRates);

        // 최신 데이터 조회는 실패했지만 캐시가 있으면 캐시 표시 사실을 함께 알려줌.
        _errorMessage =
            '$fallbackMessage '
            '마지막 저장 데이터를 표시합니다.';
      } else {
        // 캐시가 없으면 Service/백엔드에서 정리한 사용자용 메시지를 그대로 표시함.
        _errorMessage = fallbackMessage;
      }
    } catch (_) {
      // 캐시 조회마저 실패해도 기술적 예외 대신 사용자용 메시지만 표시함.
      _errorMessage = fallbackMessage;
    }
  }

  // 사용자가 입력한 기준 통화 금액을 변경하는 비동기 작업.
  Future<void> changeAmount(double amount) async {
    if (_inputAmount == amount) {
      return;
    }

    _inputAmount = amount;

    // 입력 결과는 즉시 화면에 반영함.
    notifyListeners();

    await _localStorageService.saveInputAmount(amount);
  }

  Future<void> changeAmountFromCurrency({
    required String currencyCode,
    required double amount,
  }) async {
    // 현재 입력하고 있는 통화를 선택 상태로 변경
    _activeInputCurrencyCode = currencyCode;

    // 기준 통화에 직접 입력한 경우
    if (currencyCode == _baseCurrency.code) {
      _inputAmount = amount;

      notifyListeners();

      await _localStorageService.saveInputAmount(_inputAmount);
      return;
    }

    // 기준 통화 → 해당 통화의 환율
    final rate = _rates[currencyCode];

    if (rate == null || rate == 0) {
      notifyListeners();
      return;
    }

    // 상대 통화에 입력된 값을 기준 통화 금액으로 역산
    _inputAmount = amount / rate;

    notifyListeners();

    await _localStorageService.saveInputAmount(_inputAmount);
  }

  // 현재 입력 대상으로 선택된 통화
  void selectInputCurrency(String currencyCode) {
    if (_activeInputCurrencyCode == currencyCode) {
      return;
    }

    _activeInputCurrencyCode = currencyCode;
    notifyListeners();
  }

  // 기준 통화를 변경하는 비동기 작업.
  Future<void> changeBaseCurrency(CurrencyModel currency) async {
    if (_baseCurrency.code == currency.code) {
      return;
    }

    final oldBaseCurrency = _baseCurrency;

    _baseCurrency = currency;

    _visibleCurrencies = _normalizeVisibleCurrencies(<CurrencyModel>[
      oldBaseCurrency,
      ..._visibleCurrencies.where((item) => item.code != currency.code),
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

  // 화면에 표시할 통화 목록 전체를 적용하는 비동기 작업.
  Future<void> applyVisibleCurrencies(List<CurrencyModel> currencies) async {
    final normalizedCurrencies = _normalizeVisibleCurrencies(currencies);

    if (_hasSameCurrencyCodes(_visibleCurrencies, normalizedCurrencies)) {
      return;
    }

    _visibleCurrencies = normalizedCurrencies;

    await _saveCurrencyState();
    await fetchRates();
  }

  // 화면에 표시할 통화를 추가하는 비동기 작업.
  Future<void> addCurrency(CurrencyModel currency) async {
    if (currency.code == _baseCurrency.code ||
        _visibleCurrencies.any((item) => item.code == currency.code)) {
      return;
    }

    _visibleCurrencies.add(currency);

    await _saveCurrencyState();
    await fetchRates();
  }

  // 화면에 표시할 통화 목록에서 특정 통화를 제거하는 비동기 작업.
  // 기준 통화는 제거할 수 없음.
  Future<void> removeCurrency(CurrencyModel currency) async {
    if (currency.code == _baseCurrency.code) {
      _setErrorMessage('기준 통화는 삭제할 수 없습니다.');
      return;
    }

    final previousLength = _visibleCurrencies.length;

    _visibleCurrencies.removeWhere((item) => item.code == currency.code);

    if (_visibleCurrencies.length == previousLength) {
      return;
    }

    await _saveCurrencyState();
    await fetchRates();
  }

  // 입력 금액을 기준으로 특정 통화로 환산한 금액을 계산하는 메서드.
  // 기준 통화와 동일한 경우에는 입력 금액 그대로 반환.
  double convertedAmount(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return _inputAmount;
    }

    final rate = _rates[targetCode];

    return rate == null ? 0 : _inputAmount * rate;
  }

  // 특정 통화의 환율을 반환하는 메서드.
  double? rateFor(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return 1;
    }

    return _rates[targetCode];
  }

  // 기준 통화와 화면에 표시할 통화 목록을 로컬 스토리지에 저장하는 비동기 작업.
  Future<void> _saveCurrencyState() async {
    await _localStorageService.saveBaseCurrency(_baseCurrency.code);

    await _localStorageService.saveVisibleCurrencies(
      _visibleCurrencies.map((currency) => currency.code).toList(),
    );
  }

  // 화면에 표시할 통화 목록에서 중복된 통화를 제거하고,
  // 기준 통화를 제외한 고유한 통화 목록을 반환하는 메서드.
  List<CurrencyModel> _normalizeVisibleCurrencies(
    Iterable<CurrencyModel> currencies,
  ) {
    final uniqueCurrencies = LinkedHashMap<String, CurrencyModel>();

    for (final currency in currencies) {
      if (currency.code == _baseCurrency.code) {
        continue;
      }

      uniqueCurrencies.putIfAbsent(currency.code, () => currency);
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

  // 현재 처리 중인 요청이 가장 최근 요청인지 확인하는 메서드.
  bool _isLatestRequest(int requestId) {
    return requestId == _fetchRequestId;
  }

  // 오류 메시지를 설정하고 화면에 반영하는 메서드.
  void _setErrorMessage(String message) {
    if (_errorMessage == message) {
      return;
    }

    _errorMessage = message;
    notifyListeners();
  }
}
