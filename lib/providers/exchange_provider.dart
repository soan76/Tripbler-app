import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../core/network/api_exception.dart';
import '../domain/exchange/exchange_calculator.dart';
import '../domain/exchange/exchange_currency_manager.dart';
import '../models/currency_model.dart';
import '../services/exchange_rate_api_service.dart';
import '../services/local_storage_service.dart';

/// 서버 환율 API를 호출하는 서비스. 환율 목록과 KRW 연결 환율 조회가 함께 쓴다.
final exchangeRateApiServiceProvider = Provider<ExchangeRateApiService>((ref) {
  final service = ExchangeRateApiService();
  ref.onDispose(service.dispose);
  return service;
});

/// 기준 통화·표시 통화·환율 캐시를 기기에 저장하는 서비스.
final localStorageServiceProvider = Provider<LocalStorageService>(
  (ref) => LocalStorageService(),
);

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
    );
  }
}

/// 환율 관련 상태를 관리한다.
class ExchangeNotifier extends Notifier<ExchangeState> {
  // 통화 목록의 정규화/비교/입력 가능 여부 같은 순수 규칙을 담당함.
  final ExchangeCurrencyManager _currencyManager =
      const ExchangeCurrencyManager();

  // 기준 금액 ↔ 대상 금액 간 순수 환산 공식을 담당함.
  final ExchangeCalculator _calculator = const ExchangeCalculator();

  bool _hasInitialized = false;
  Future<void>? _initializationFuture;

  // 가장 최근에 시작된 환율 요청을 식별함.
  int _fetchRequestId = 0;

  ExchangeRateApiService get _apiService =>
      ref.read(exchangeRateApiServiceProvider);

  LocalStorageService get _localStorageService =>
      ref.read(localStorageServiceProvider);

  @override
  ExchangeState build() {
    return ExchangeState(baseCurrency: findCurrencyByCode('KRW')!);
  }

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

      if (!ref.mounted) return;
      _hasInitialized = true;
      unawaited(fetchRates());
    } finally {
      _initializationFuture = null;
    }
  }

  // 저장된 상태를 불러오는 비동기 작업.
  // 로컬 스토리지에서 기준 통화, 화면에 표시할 통화 목록, 환율,
  // 마지막 업데이트 시각, 입력 금액을 불러와서 상태에 반영.
  Future<void> _loadSavedState() async {
    final storage = _localStorageService;

    // 기준 통화, 표시 통화, 입력 금액은 서로 독립적이므로 먼저 요청을 시작한다.
    final baseCurrencyFuture = storage.loadBaseCurrency();

    final visibleCurrenciesFuture = storage.loadVisibleCurrencies();

    final inputAmountFuture = storage.loadInputAmount();

    // 기준 통화를 먼저 확정한다.
    final savedBaseCode = await baseCurrencyFuture;

    if (!ref.mounted) return;

    if (savedBaseCode != null) {
      final savedBase =
          findCurrencyByCode(savedBaseCode) ?? findCurrencyByCode('KRW')!;
      if (savedBase.code != state.baseCurrency.code) {
        state = state.copyWith(baseCurrency: savedBase);
      }
    }

    final baseCurrency = state.baseCurrency;

    // 기준 통화가 확정된 뒤 해당 기준 통화의 캐시를 읽는다.
    final cachedRatesFuture = storage.loadCachedRates(
      baseCurrency: baseCurrency.code,
    );

    final lastUpdatedFuture = storage.loadLastUpdated(
      baseCurrency: baseCurrency.code,
    );

    final savedVisibleCodes = await visibleCurrenciesFuture;

    final savedAmount = await inputAmountFuture;

    final savedRates = await cachedRatesFuture;

    final savedLastUpdated = await lastUpdatedFuture;

    if (!ref.mounted) return;

    final current = state;

    final visibleCurrencies = savedVisibleCodes == null
        ? current.visibleCurrencies
        : _currencyManager.normalizeVisibleCurrencies(
            baseCurrency: current.baseCurrency,
            currencies: savedVisibleCodes
                .map(findCurrencyByCode)
                .whereType<CurrencyModel>(),
          );

    final rates =
        savedRates != null &&
            savedLastUpdated != null &&
            DateTime.now().difference(savedLastUpdated) <
                const Duration(days: 3)
        ? Map<String, double>.from(savedRates)
        : current.rates;

    final lastUpdated = rates.isEmpty ? null : savedLastUpdated;

    state = current.copyWith(
      visibleCurrencies: visibleCurrencies,
      rates: rates,
      lastUpdated: lastUpdated,
      clearLastUpdated: lastUpdated == null,
      inputAmount: savedAmount,
    );
  }

  // 환율 정보를 가져오는 비동기 작업.
  // 가장 최근에 시작된 요청만 처리하고, 이전 요청은 무시함.
  Future<void> fetchRates() async {
    final requestId = ++_fetchRequestId;

    if (!ref.mounted) return;

    final baseCurrencyCode = state.baseCurrency.code;

    state = state.copyWith(isLoading: true, clearErrorMessage: true);

    final storage = _localStorageService;

    try {
      if (state.rates.isEmpty) {
        try {
          final rates = await storage.loadCachedRates(
            baseCurrency: baseCurrencyCode,
          );
          final updated = await storage.loadLastUpdated(
            baseCurrency: baseCurrencyCode,
          );
          if (!_isCurrentFetch(requestId, baseCurrencyCode)) return;
          if (rates != null &&
              updated != null &&
              DateTime.now().difference(updated) < const Duration(days: 3)) {
            state = state.copyWith(
              rates: Map<String, double>.from(rates),
              lastUpdated: updated,
            );
          }
        } catch (_) {
          // 기기 저장소 오류가 서버 재조회까지 막지 않게 한다.
        }
      }
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) return;
      final targetCodes = state.visibleCurrencies
          .map((currency) => currency.code)
          .toSet()
          .toList(growable: false);

      if (targetCodes.isEmpty) {
        if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
          return;
        }

        // 표시할 통화가 없어서 API를 호출하지 않은 경우이므로
        // "마지막으로 서버에서 실제로 데이터를 받은 시각"이라는 의미를 지키기 위해
        // lastUpdated는 변경하지 않고 이전 값을 그대로 유지함.
        if (state.rates.isNotEmpty) {
          state = state.copyWith(rates: <String, double>{});
        }
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

      // Flutter에서 DateTime.now()로 만든 시간이 아니라,
      // 백엔드가 환율을 가져온 시각인 fetchedAt을 마지막 업데이트 시각으로 사용함.
      final savedRates = Map<String, double>.from(latestRatesResponse.rates);
      state = state.copyWith(
        rates: savedRates,
        lastUpdated: latestRatesResponse.fetchedAt,
        errorMessage: latestRatesResponse.stale
            ? '응답 지연으로 마지막 성공 환율을 표시합니다.'
            : null,
      );

      try {
        await storage.saveCachedRates(
          baseCurrency: baseCurrencyCode,
          rates: savedRates,
        );

        await storage.saveLastUpdated(
          baseCurrency: baseCurrencyCode,
          dateTime: latestRatesResponse.fetchedAt,
        );
      } catch (_) {
        if (_isCurrentFetch(requestId, baseCurrencyCode)) {
          state = state.copyWith(errorMessage: '최신 환율은 표시했지만 기기에 저장하지 못했습니다.');
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
        state = state.copyWith(isLoading: false);
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
    final lastUpdated = state.lastUpdated;
    if (state.rates.isNotEmpty &&
        lastUpdated != null &&
        DateTime.now().difference(lastUpdated) < const Duration(days: 3)) {
      state = state.copyWith(
        errorMessage: '$fallbackMessage 마지막 성공 데이터를 표시합니다.',
      );
      return;
    }
    final storage = _localStorageService;
    try {
      final cachedRatesFuture = storage.loadCachedRates(
        baseCurrency: baseCurrencyCode,
      );

      final lastUpdatedFuture = storage.loadLastUpdated(
        baseCurrency: baseCurrencyCode,
      );

      final cachedRates = await cachedRatesFuture;
      final cachedLastUpdated = await lastUpdatedFuture;

      // 캐시를 읽는 동안 기준 통화나 요청 상태가 변경되었다면
      // 이전 요청의 캐시 결과를 현재 화면에 적용하지 않는다.
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      if (cachedRates != null &&
          cachedRates.isNotEmpty &&
          cachedLastUpdated != null &&
          DateTime.now().difference(cachedLastUpdated) <
              const Duration(days: 3)) {
        state = state.copyWith(
          rates: Map<String, double>.from(cachedRates),
          lastUpdated: cachedLastUpdated,
          errorMessage:
              '$fallbackMessage '
              '마지막 저장 데이터를 표시합니다.',
        );
      } else {
        // 현재 기준 통화에서 사용할 수 있는 캐시가 없으면
        // 이전 환율과 업데이트 시각을 화면에 남기지 않는다.
        state = state.copyWith(
          rates: <String, double>{},
          clearLastUpdated: true,
          errorMessage: fallbackMessage,
        );
      }
    } catch (_) {
      // 캐시 조회 과정에서 예외가 발생했더라도,
      // 이미 오래된 요청이라면 현재 화면 상태를 변경하지 않는다.
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      state = state.copyWith(
        rates: <String, double>{},
        clearLastUpdated: true,
        errorMessage: fallbackMessage,
      );
    }
  }

  Future<void> changeAmountFromCurrency({
    required String currencyCode,
    required double amount,
  }) async {
    final current = state;

    // 현재 화면에서 사용할 수 있는 통화인지 확인
    if (!_currencyManager.isAvailableInputCurrency(
      baseCurrency: current.baseCurrency,
      visibleCurrencies: current.visibleCurrencies,
      currencyCode: currencyCode,
    )) {
      _setErrorMessage('선택한 통화를 찾을 수 없습니다.');
      return;
    }

    final activeCurrencyChanged = current.inputCurrencyCode != currencyCode;

    // 기준 통화에 직접 입력한 경우
    if (currencyCode == current.baseCurrency.code) {
      await _updateBaseAmount(
        amount,
        inputCurrencyCode: currencyCode,
        forceNotify: activeCurrencyChanged,
      );

      return;
    }

    // 기준 통화 → 입력 통화 환율
    final rate = current.rates[currencyCode];

    if (!_calculator.isValidRate(rate)) {
      _setErrorMessage('선택한 통화의 환율 정보가 없어 금액을 계산할 수 없습니다.');
      return;
    }

    // 실제 환산 공식은 ExchangeCalculator에 위임하고,
    // Notifier는 계산 결과를 상태에 반영하는 역할만 담당함.
    final baseAmount = _calculator.convertToBase(
      targetAmount: amount,
      rate: rate!,
    );

    // 정상적인 경우에만 현재 입력 통화를 변경
    await _updateBaseAmount(
      baseAmount,
      inputCurrencyCode: currencyCode,
      forceNotify: activeCurrencyChanged,
    );
  }

  // 현재 입력 대상으로 선택된 통화
  void selectInputCurrency(String currencyCode) {
    if (state.inputCurrencyCode == currencyCode) {
      return;
    }

    state = state.copyWith(inputCurrencyCode: currencyCode);
  }

  // 기준 통화를 변경하는 비동기 작업.
  Future<void> changeBaseCurrency(CurrencyModel currency) async {
    final current = state;

    if (current.baseCurrency.code == currency.code) {
      return;
    }

    _invalidatePendingFetches();

    final oldBaseCurrency = current.baseCurrency;

    // 이전 기준 통화에서 가져온 환율을
    // 새로운 기준 통화의 환율처럼 사용하지 않도록 즉시 제거한다.
    state = current.copyWith(
      baseCurrency: currency,
      visibleCurrencies: _currencyManager.normalizeVisibleCurrencies(
        baseCurrency: currency,
        currencies: <CurrencyModel>[
          oldBaseCurrency,
          ...current.visibleCurrencies.where(
            (item) => item.code != currency.code,
          ),
        ],
      ),
      rates: <String, double>{},
      clearLastUpdated: true,
      clearErrorMessage: true,
    );

    await _persistAndRefreshRates();
  }

  Future<void> _persistAndRefreshRates() async {
    try {
      await _saveCurrencyState();
    } catch (error, stackTrace) {
      debugPrint('통화 설정 저장 실패: $error');
      debugPrint('$stackTrace');
    }

    if (!ref.mounted) return;

    // 로컬 저장 실패가 최신 환율 조회까지 막지 않도록 한다.
    await fetchRates();
  }

  // 화면에 표시할 통화 목록에서 특정 위치의 통화를 새로운 통화로 교체하는 비동기 작업.
  Future<void> replaceVisibleCurrency({
    required int index,
    required CurrencyModel newCurrency,
  }) async {
    final current = state;
    final visibleCurrencies = current.visibleCurrencies;

    if (index < 0 || index >= visibleCurrencies.length) {
      _setErrorMessage('변경할 통화 위치가 올바르지 않습니다.');
      return;
    }

    if (newCurrency.code == current.baseCurrency.code) {
      _setErrorMessage('기준 통화와 동일한 통화로 변경할 수 없습니다.');
      return;
    }

    final duplicateIndex = visibleCurrencies.indexWhere(
      (item) => item.code == newCurrency.code,
    );

    if (duplicateIndex != -1 && duplicateIndex != index) {
      _setErrorMessage('이미 화면에 표시된 통화입니다.');
      return;
    }

    if (visibleCurrencies[index].code == newCurrency.code) {
      return;
    }

    _invalidatePendingFetches();

    state = current.copyWith(
      visibleCurrencies: <CurrencyModel>[...visibleCurrencies]
        ..[index] = newCurrency,
    );

    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화 목록 전체를 적용하는 비동기 작업.
  Future<void> applyVisibleCurrencies(List<CurrencyModel> currencies) async {
    final current = state;

    final normalizedCurrencies = _currencyManager.normalizeVisibleCurrencies(
      baseCurrency: current.baseCurrency,
      currencies: currencies,
    );

    // 통화와 순서가 모두 동일
    if (_currencyManager.hasSameOrder(
      current.visibleCurrencies,
      normalizedCurrencies,
    )) {
      return;
    }

    // 통화 종류는 같고 순서만 변경되었는지 확인
    final sameCurrencySet = _currencyManager.hasSameSet(
      current.visibleCurrencies,
      normalizedCurrencies,
    );

    if (!sameCurrencySet) {
      _invalidatePendingFetches();
    }

    state = current.copyWith(visibleCurrencies: normalizedCurrencies);

    if (sameCurrencySet) {
      // 순서만 변경 → 로컬에만 저장
      await _saveCurrencyState();
      return;
    }

    // 실제 통화 구성이 변경됨 → 저장 + 새 환율 조회
    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화를 추가하는 비동기 작업.
  Future<void> addCurrency(CurrencyModel currency) async {
    final current = state;

    if (currency.code == current.baseCurrency.code) {
      _setErrorMessage('기준 통화는 표시 통화에 다시 추가할 수 없습니다.');
      return;
    }

    if (current.visibleCurrencies.any((item) => item.code == currency.code)) {
      _setErrorMessage('이미 화면에 표시된 통화입니다.');
      return;
    }

    _invalidatePendingFetches();

    state = current.copyWith(
      visibleCurrencies: <CurrencyModel>[
        ...current.visibleCurrencies,
        currency,
      ],
    );

    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화 목록에서 특정 통화를 제거하는 비동기 작업.
  // 기준 통화는 제거할 수 없음.
  Future<void> removeCurrency(CurrencyModel currency) async {
    final current = state;

    if (currency.code == current.baseCurrency.code) {
      _setErrorMessage('기준 통화는 삭제할 수 없습니다.');
      return;
    }

    final remaining = current.visibleCurrencies
        .where((item) => item.code != currency.code)
        .toList();

    if (remaining.length == current.visibleCurrencies.length) {
      return;
    }

    _invalidatePendingFetches();

    state = current.copyWith(visibleCurrencies: remaining);

    await _persistAndRefreshRates();
  }

  Future<void> _updateBaseAmount(
    double amount, {
    required String inputCurrencyCode,
    bool forceNotify = false,
  }) async {
    final amountChanged = state.inputAmount != amount;

    if (!amountChanged && !forceNotify) {
      return;
    }

    state = state.copyWith(
      inputAmount: amount,
      inputCurrencyCode: inputCurrencyCode,
    );

    if (amountChanged) {
      await _localStorageService.saveInputAmount(amount);
    }
  }

  // 기준 통화와 화면에 표시할 통화 목록을 로컬 스토리지에 저장하는 비동기 작업.
  Future<void> _saveCurrencyState() async {
    final storage = _localStorageService;

    await storage.saveBaseCurrency(state.baseCurrency.code);

    if (!ref.mounted) return;

    await storage.saveVisibleCurrencies(
      state.visibleCurrencies.map((currency) => currency.code).toList(),
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
    return ref.mounted && requestId == _fetchRequestId;
  }

  bool _isCurrentFetch(int requestId, String baseCurrencyCode) {
    return _isLatestRequest(requestId) &&
        state.baseCurrency.code == baseCurrencyCode;
  }

  // 오류 메시지를 설정하고 화면에 반영하는 메서드.
  void _setErrorMessage(String message) {
    if (state.errorMessage == message) {
      return;
    }

    state = state.copyWith(errorMessage: message);
  }
}

final exchangeProvider = NotifierProvider<ExchangeNotifier, ExchangeState>(
  ExchangeNotifier.new,
);
