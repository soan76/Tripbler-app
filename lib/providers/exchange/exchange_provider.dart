import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../../domain/exchange/exchange_calculator.dart';
import '../../domain/exchange/exchange_currency_manager.dart';
import '../../models/currency_model.dart';
import '../../services/exchange_rate_api_service.dart';
import '../../services/local_storage_service.dart';
import 'exchange_currency_list_editor.dart';
import 'exchange_rate_fetcher.dart';
import 'exchange_saved_state_loader.dart';
import 'exchange_state.dart';

export 'exchange_state.dart';

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

/// 환율 관련 상태를 관리한다.
class ExchangeNotifier extends Notifier<ExchangeState> {
  // 금액 입력 통화가 현재 입력 가능한 통화인지 확인하는 순수 규칙을 담당함.
  final ExchangeCurrencyManager _currencyManager =
      const ExchangeCurrencyManager();

  // 기준 금액 ↔ 대상 금액 간 순수 환산 공식을 담당함.
  final ExchangeCalculator _calculator = const ExchangeCalculator();

  bool _hasInitialized = false;
  Future<void>? _initializationFuture;

  // 가장 최근에 시작된 환율 요청을 식별함.
  int _fetchRequestId = 0;

  LocalStorageService get _localStorageService =>
      ref.read(localStorageServiceProvider);

  /// 저장된 기준 통화·표시 통화·입력 금액·환율 캐시를 불러온다.
  late final ExchangeSavedStateLoader _savedStateLoader =
      ExchangeSavedStateLoader(
        readStorage: () => _localStorageService,
        isMounted: () => ref.mounted,
        readState: () => state,
        writeState: _writeState,
      );

  /// 서버 환율을 조회하고 실패 시 마지막 성공값·기기 캐시로 대신한다.
  late final ExchangeRateFetcher _rateFetcher = ExchangeRateFetcher(
    readApiService: () => ref.read(exchangeRateApiServiceProvider),
    readStorage: () => _localStorageService,
    isMounted: () => ref.mounted,
    readState: () => state,
    writeState: _writeState,
    startRequest: () => ++_fetchRequestId,
    isLatestRequest: _isLatestRequest,
  );

  /// 기준 통화·표시 통화 목록을 바꾸고 저장한 뒤 환율을 다시 조회한다.
  late final ExchangeCurrencyListEditor _currencyListEditor =
      ExchangeCurrencyListEditor(
        readStorage: () => _localStorageService,
        isMounted: () => ref.mounted,
        readState: () => state,
        writeState: _writeState,
        invalidatePendingFetches: _invalidatePendingFetches,
        fetchRates: fetchRates,
        setErrorMessage: _setErrorMessage,
      );

  @override
  ExchangeState build() {
    return ExchangeState(baseCurrency: findCurrencyByCode('KRW')!);
  }

  void _writeState(ExchangeState next) {
    state = next;
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
        await _savedStateLoader.load();
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

  // 환율 정보를 가져오는 비동기 작업.
  // 가장 최근에 시작된 요청만 처리하고, 이전 요청은 무시함.
  // 자세한 규칙은 [ExchangeRateFetcher.fetch].
  Future<void> fetchRates() => _rateFetcher.fetch();

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
  // 자세한 규칙은 [ExchangeCurrencyListEditor.changeBaseCurrency].
  Future<void> changeBaseCurrency(CurrencyModel currency) =>
      _currencyListEditor.changeBaseCurrency(currency);

  // 화면에 표시할 통화 목록에서 특정 위치의 통화를 새로운 통화로 교체하는 비동기 작업.
  Future<void> replaceVisibleCurrency({
    required int index,
    required CurrencyModel newCurrency,
  }) => _currencyListEditor.replaceVisibleCurrency(
    index: index,
    newCurrency: newCurrency,
  );

  // 화면에 표시할 통화 목록 전체를 적용하는 비동기 작업.
  // 순서만 바뀌면 저장만 하고, 구성이 바뀌면 저장 후 환율을 다시 조회한다.
  Future<void> applyVisibleCurrencies(List<CurrencyModel> currencies) =>
      _currencyListEditor.applyVisibleCurrencies(currencies);

  // 화면에 표시할 통화를 추가하는 비동기 작업.
  Future<void> addCurrency(CurrencyModel currency) =>
      _currencyListEditor.addCurrency(currency);

  // 화면에 표시할 통화 목록에서 특정 통화를 제거하는 비동기 작업.
  // 기준 통화는 제거할 수 없음.
  Future<void> removeCurrency(CurrencyModel currency) =>
      _currencyListEditor.removeCurrency(currency);

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
