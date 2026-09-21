import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../domain/exchange/exchange_calculator.dart';
import '../domain/exchange/exchange_currency_manager.dart';
import '../models/currency_model.dart';
import '../services/exchange_rate_api_service.dart';
import '../services/local_storage_service.dart';

/// 환율 관련 상태를 관리하는 Provider.
class ExchangeProvider extends ChangeNotifier {
  ExchangeProvider({
    ExchangeRateApiService? apiService,
    LocalStorageService? localStorageService,
    ExchangeCurrencyManager? currencyManager,
    ExchangeCalculator? calculator,
  }) : _ownsApiService = apiService == null,
       _apiService = apiService ?? ExchangeRateApiService(),
       _localStorageService = localStorageService ?? LocalStorageService(),
       _currencyManager = currencyManager ?? const ExchangeCurrencyManager(),
       _calculator = calculator ?? const ExchangeCalculator();

  final bool _ownsApiService;
  final ExchangeRateApiService _apiService;
  final LocalStorageService _localStorageService;
  // 통화 목록의 정규화/비교/입력 가능 여부 같은 순수 규칙을 담당함.
  final ExchangeCurrencyManager _currencyManager;

  // 기준 금액 ↔ 대상 금액 간 순수 환산 공식을 담당함.
  final ExchangeCalculator _calculator;

  // 기준 통화, 화면에 표시할 통화 목록, 입력 금액, 환율, 로딩 상태, 오류 메시지, 마지막 업데이트 시각을 관리.
  CurrencyModel _baseCurrency = findCurrencyByCode('KRW')!;
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
      try {
        await _loadSavedState();
      } catch (error, stackTrace) {
        debugPrint('저장된 상태 불러오기 실패: $error');
        debugPrint('$stackTrace');
        // 저장된 상태를 못 불러와도 기본값(KRW, 빈 목록)으로 계속 진행함.
      }

      await fetchRates();
      _hasInitialized = true;
    } finally {
      _initializationFuture = null;
    }
  }

  // 저장된 상태를 불러오는 비동기 작업.
  // 로컬 스토리지에서 기준 통화, 화면에 표시할 통화 목록, 환율,
  // 마지막 업데이트 시각, 입력 금액을 불러와서 Provider 상태에 반영.
  Future<void> _loadSavedState() async {
    // 기준 통화, 표시 통화, 입력 금액은 서로 독립적이므로 먼저 요청을 시작한다.
    final baseCurrencyFuture = _localStorageService.loadBaseCurrency();

    final visibleCurrenciesFuture = _localStorageService
        .loadVisibleCurrencies();

    final inputAmountFuture = _localStorageService.loadInputAmount();

    // 기준 통화를 먼저 확정한다.
    final savedBaseCode = await baseCurrencyFuture;

    if (savedBaseCode != null) {
      _baseCurrency =
          findCurrencyByCode(savedBaseCode) ?? findCurrencyByCode('KRW')!;
    }

    // 기준 통화가 확정된 뒤 해당 기준 통화의 캐시를 읽는다.
    final cachedRatesFuture = _localStorageService.loadCachedRates(
      baseCurrency: _baseCurrency.code,
    );

    final lastUpdatedFuture = _localStorageService.loadLastUpdated(
      baseCurrency: _baseCurrency.code,
    );

    final savedVisibleCodes = await visibleCurrenciesFuture;

    final savedAmount = await inputAmountFuture;

    final savedRates = await cachedRatesFuture;

    final savedLastUpdated = await lastUpdatedFuture;

    if (savedVisibleCodes != null) {
      _visibleCurrencies = _currencyManager.normalizeVisibleCurrencies(
        baseCurrency: _baseCurrency,
        currencies: savedVisibleCodes
            .map(findCurrencyByCode)
            .whereType<CurrencyModel>(),
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

    final baseCurrencyCode = _baseCurrency.code;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final targetCodes = _visibleCurrencies
          .map((currency) => currency.code)
          .toSet()
          .toList(growable: false);

      if (targetCodes.isEmpty) {
        if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
          return;
        }

        _rates = <String, double>{};
        // 표시할 통화가 없어서 API를 호출하지 않은 경우이므로
        // "마지막으로 서버에서 실제로 데이터를 받은 시각"이라는 의미를 지키기 위해
        // _lastUpdated는 변경하지 않고 이전 값을 그대로 유지함.
        return;
      }

      // Spring Boot 백엔드의 최신 환율 API 응답 전체를 가져옴.
      // rates뿐만 아니라 fetchedAt도 함께 받기 위해 fetchLatestRatesResponse()를 사용함.
      final latestRatesResponse = await _apiService.fetchLatestRatesResponse(
        baseCurrency: baseCurrencyCode,
        targetCurrencies: targetCodes,
      );
  
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      // 백엔드 응답의 rates를 Provider 상태에 반영함.
      _rates = Map<String, double>.from(latestRatesResponse.rates);

      // Flutter에서 DateTime.now()로 만든 시간이 아니라,
      // 백엔드가 환율을 가져온 시각인 fetchedAt을 마지막 업데이트 시각으로 사용함.
      _lastUpdated = latestRatesResponse.fetchedAt;

      try {
        await _localStorageService.saveCachedRates(
          baseCurrency: baseCurrencyCode,
          rates: _rates,
        );

        await _localStorageService.saveLastUpdated(
          baseCurrency: baseCurrencyCode,
          dateTime: latestRatesResponse.fetchedAt,
        );
      } catch (_) {
        if (_isCurrentFetch(requestId, baseCurrencyCode)) {
          _errorMessage = '최신 환율은 표시했지만 기기에 저장하지 못했습니다.';
        }
      }
    } catch (error) {
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      await _restoreCachedRatesAfterFetchFailure(
        requestId: requestId,
        baseCurrencyCode: baseCurrencyCode,
        fallbackMessage: _cleanErrorMessage(error),
      );
    } finally {
      if (_isCurrentFetch(requestId, baseCurrencyCode)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // 오류 메시지를 정리하여 사용자에게 표시할 수 있는 형태로 반환하는 메서드.
  String _cleanErrorMessage(Object error) {
    if (error is ApiException) {
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
    required int requestId,
    required String baseCurrencyCode,
    required String fallbackMessage,
  }) async {
    try {
      final cachedRatesFuture = _localStorageService.loadCachedRates(
        baseCurrency: baseCurrencyCode,
      );

      final lastUpdatedFuture = _localStorageService.loadLastUpdated(
        baseCurrency: baseCurrencyCode,
      );

      final cachedRates = await cachedRatesFuture;
      final cachedLastUpdated = await lastUpdatedFuture;

      // 캐시를 읽는 동안 기준 통화나 요청 상태가 변경되었다면
      // 이전 요청의 캐시 결과를 현재 화면에 적용하지 않는다.
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      if (cachedRates != null && cachedRates.isNotEmpty) {
        _rates = Map<String, double>.from(cachedRates);
        _lastUpdated = cachedLastUpdated;

        _errorMessage =
            '$fallbackMessage '
            '마지막 저장 데이터를 표시합니다.';
      } else {
        // 현재 기준 통화에서 사용할 수 있는 캐시가 없으면
        // 이전 환율과 업데이트 시각을 화면에 남기지 않는다.
        _rates = <String, double>{};
        _lastUpdated = null;
        _errorMessage = fallbackMessage;
      }
    } catch (_) {
      // 캐시 조회 과정에서 예외가 발생했더라도,
      // 이미 오래된 요청이라면 현재 화면 상태를 변경하지 않는다.
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      _rates = <String, double>{};
      _lastUpdated = null;
      _errorMessage = fallbackMessage;
    }
  }

  Future<void> changeAmountFromCurrency({
    required String currencyCode,
    required double amount,
  }) async {
    // 현재 화면에서 사용할 수 있는 통화인지 확인
    if (!_currencyManager.isAvailableInputCurrency(
      baseCurrency: _baseCurrency,
      visibleCurrencies: _visibleCurrencies,
      currencyCode: currencyCode,
    )) {
      _setErrorMessage('선택한 통화를 찾을 수 없습니다.');
      return;
    }

    final activeCurrencyChanged = _activeInputCurrencyCode != currencyCode;

    // 기준 통화에 직접 입력한 경우
    if (currencyCode == _baseCurrency.code) {
      _activeInputCurrencyCode = currencyCode;

      await _updateBaseAmount(amount, forceNotify: activeCurrencyChanged);

      return;
    }

    // 기준 통화 → 입력 통화 환율
    final rate = _rates[currencyCode];

    if (!_calculator.isValidRate(rate)) {
      _setErrorMessage('선택한 통화의 환율 정보가 없어 금액을 계산할 수 없습니다.');
      return;
    }

    // 정상적인 경우에만 현재 입력 통화를 변경
    _activeInputCurrencyCode = currencyCode;

    // 실제 환산 공식은 ExchangeCalculator에 위임하고,
    // Provider는 계산 결과를 상태에 반영하는 역할만 담당함.
    final baseAmount = _calculator.convertToBase(
      targetAmount: amount,
      rate: rate!,
    );

    await _updateBaseAmount(baseAmount, forceNotify: activeCurrencyChanged);
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

    _invalidatePendingFetches();

    final oldBaseCurrency = _baseCurrency;

    _baseCurrency = currency;

    _visibleCurrencies = _currencyManager.normalizeVisibleCurrencies(
      baseCurrency: _baseCurrency,
      currencies: <CurrencyModel>[
        oldBaseCurrency,
        ..._visibleCurrencies.where((item) => item.code != currency.code),
      ],
    );

    // 이전 기준 통화에서 가져온 환율을
    // 새로운 기준 통화의 환율처럼 사용하지 않도록 즉시 제거한다.
    _rates = <String, double>{};
    _lastUpdated = null;
    _errorMessage = null;

    notifyListeners();

    await _persistAndRefreshRates();
  }

  Future<void> _persistAndRefreshRates() async {
    try {
      await _saveCurrencyState();
    } catch (error, stackTrace) {
      debugPrint('통화 설정 저장 실패: $error');
      debugPrint('$stackTrace');
    }

    // 로컬 저장 실패가 최신 환율 조회까지 막지 않도록 한다.
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
      _setErrorMessage('기준 통화와 동일한 통화로 변경할 수 없습니다.');
      return;
    }

    final duplicateIndex = _visibleCurrencies.indexWhere(
      (item) => item.code == newCurrency.code,
    );

    if (duplicateIndex != -1 && duplicateIndex != index) {
      _setErrorMessage('이미 화면에 표시된 통화입니다.');
      return;
    }

    if (_visibleCurrencies[index].code == newCurrency.code) {
      return;
    }

    _invalidatePendingFetches();

    _visibleCurrencies[index] = newCurrency;

    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화 목록 전체를 적용하는 비동기 작업.
  Future<void> applyVisibleCurrencies(List<CurrencyModel> currencies) async {
    final normalizedCurrencies = _currencyManager.normalizeVisibleCurrencies(
      baseCurrency: _baseCurrency,
      currencies: currencies,
    );

    // 통화와 순서가 모두 동일
    if (_currencyManager.hasSameOrder(
      _visibleCurrencies,
      normalizedCurrencies,
    )) {
      return;
    }

    // 통화 종류는 같고 순서만 변경되었는지 확인
    final sameCurrencySet = _currencyManager.hasSameSet(
      _visibleCurrencies,
      normalizedCurrencies,
    );

    if (!sameCurrencySet) {
      _invalidatePendingFetches();
    }

    _visibleCurrencies = normalizedCurrencies;

    if (sameCurrencySet) {
      // 순서만 변경 → 로컬에만 저장
      notifyListeners();
      await _saveCurrencyState();
      return;
    }

    // 실제 통화 구성이 변경됨 → 저장 + 새 환율 조회
    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화를 추가하는 비동기 작업.
  Future<void> addCurrency(CurrencyModel currency) async {
    if (currency.code == _baseCurrency.code) {
      _setErrorMessage('기준 통화는 표시 통화에 다시 추가할 수 없습니다.');
      return;
    }

    if (_visibleCurrencies.any((item) => item.code == currency.code)) {
      _setErrorMessage('이미 화면에 표시된 통화입니다.');
      return;
    }

    _invalidatePendingFetches();

    _visibleCurrencies.add(currency);

    await _persistAndRefreshRates();
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

    _invalidatePendingFetches();

    await _persistAndRefreshRates();
  }

  // 입력 금액을 기준으로 특정 통화로 환산한 금액을 계산하는 메서드.
  // 기준 통화와 동일한 경우에는 입력 금액 그대로 반환.
  double convertedAmount(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return _inputAmount;
    }

    final rate = _rates[targetCode];

    if (!_calculator.isValidRate(rate)) {
      return 0;
    }

    return _calculator.convertFromBase(baseAmount: _inputAmount, rate: rate!);
  }

  // 특정 통화의 환율을 반환하는 메서드.
  double? rateFor(String targetCode) {
    if (targetCode == _baseCurrency.code) {
      return 1;
    }

    return _rates[targetCode];
  }

  Future<void> _updateBaseAmount(
    double amount, {
    bool forceNotify = false,
  }) async {
    final amountChanged = _inputAmount != amount;

    if (!amountChanged && !forceNotify) {
      return;
    }

    _inputAmount = amount;

    notifyListeners();

    if (amountChanged) {
      await _localStorageService.saveInputAmount(_inputAmount);
    }
  }

  // 기준 통화와 화면에 표시할 통화 목록을 로컬 스토리지에 저장하는 비동기 작업.
  Future<void> _saveCurrencyState() async {
    await _localStorageService.saveBaseCurrency(_baseCurrency.code);

    await _localStorageService.saveVisibleCurrencies(
      _visibleCurrencies.map((currency) => currency.code).toList(),
    );
  }

  // 현재 진행 중인 환율 요청을 즉시 오래된 요청으로 만든다.
  //
  // 기준 통화나 표시 통화 구성이 변경되면
  // 이전 조건으로 시작한 요청의 결과를 더 이상 화면에 반영하면 안 된다.
  void _invalidatePendingFetches() {
    _fetchRequestId++;
  }

  // 현재 처리 중인 요청이 가장 최근 요청인지 확인하는 메서드.
  bool _isLatestRequest(int requestId) {
    return requestId == _fetchRequestId;
  }

  bool _isCurrentFetch(int requestId, String baseCurrencyCode) {
    return _isLatestRequest(requestId) &&
        _baseCurrency.code == baseCurrencyCode;
  }

  // 오류 메시지를 설정하고 화면에 반영하는 메서드.
  void _setErrorMessage(String message) {
    if (_errorMessage == message) {
      return;
    }

    _errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_ownsApiService) {
      _apiService.dispose();
    }

    super.dispose();
  }
}
