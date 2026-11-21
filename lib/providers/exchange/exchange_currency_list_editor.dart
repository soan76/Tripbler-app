import 'package:flutter/foundation.dart';

import '../../domain/exchange/exchange_currency_manager.dart';
import '../../models/currency_model.dart';
import '../../services/local_storage_service.dart';
import 'exchange_state.dart';

/// 기준 통화와 표시 통화 목록을 바꾸고, 바뀐 구성을 저장한 뒤 환율을 다시 조회한다.
///
/// 상태를 읽고 내보내는 일과 요청 번호·오류 문구 관리는 넘겨받은 함수가 맡는다.
/// - [readStorage]: 현재 기기 저장소 서비스를 읽는다.
/// - [isMounted]: 상태 객체가 아직 폐기되지 않았는지 확인한다.
/// - [readState]: 현재 상태를 읽는다.
/// - [writeState]: 새 상태를 내보낸다.
/// - [invalidatePendingFetches]: 진행 중인 환율 요청을 오래된 요청으로 만든다.
///   환율 조회가 발급하는 요청 번호와 같은 카운터다.
/// - [fetchRates]: 현재 구성으로 환율을 다시 조회한다.
/// - [setErrorMessage]: 오류 문구를 상태에 반영한다. 같은 문구면 내보내지 않는다.
class ExchangeCurrencyListEditor {
  const ExchangeCurrencyListEditor({
    required this.readStorage,
    required this.isMounted,
    required this.readState,
    required this.writeState,
    required this.invalidatePendingFetches,
    required this.fetchRates,
    required this.setErrorMessage,
  });

  final LocalStorageService Function() readStorage;
  final bool Function() isMounted;
  final ExchangeState Function() readState;
  final void Function(ExchangeState state) writeState;
  final void Function() invalidatePendingFetches;
  final Future<void> Function() fetchRates;
  final void Function(String message) setErrorMessage;

  // 통화 목록의 정규화/비교 같은 순수 규칙을 담당함.
  static const ExchangeCurrencyManager _currencyManager =
      ExchangeCurrencyManager();

  // 기준 통화를 변경하는 비동기 작업.
  Future<void> changeBaseCurrency(CurrencyModel currency) async {
    final current = readState();

    if (current.baseCurrency.code == currency.code) {
      return;
    }

    invalidatePendingFetches();

    final oldBaseCurrency = current.baseCurrency;

    // 이전 기준 통화에서 가져온 환율을
    // 새로운 기준 통화의 환율처럼 사용하지 않도록 즉시 제거한다.
    writeState(
      current.copyWith(
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
        usesFallbackSource: false,
        clearErrorMessage: true,
      ),
    );

    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화 목록에서 특정 위치의 통화를 새로운 통화로 교체하는 비동기 작업.
  Future<void> replaceVisibleCurrency({
    required int index,
    required CurrencyModel newCurrency,
  }) async {
    final current = readState();
    final visibleCurrencies = current.visibleCurrencies;

    if (index < 0 || index >= visibleCurrencies.length) {
      setErrorMessage('변경할 통화 위치가 올바르지 않습니다.');
      return;
    }

    if (newCurrency.code == current.baseCurrency.code) {
      setErrorMessage('기준 통화와 동일한 통화로 변경할 수 없습니다.');
      return;
    }

    final duplicateIndex = visibleCurrencies.indexWhere(
      (item) => item.code == newCurrency.code,
    );

    if (duplicateIndex != -1 && duplicateIndex != index) {
      setErrorMessage('이미 화면에 표시된 통화입니다.');
      return;
    }

    if (visibleCurrencies[index].code == newCurrency.code) {
      return;
    }

    invalidatePendingFetches();

    writeState(
      current.copyWith(
        visibleCurrencies: <CurrencyModel>[...visibleCurrencies]
          ..[index] = newCurrency,
      ),
    );

    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화 목록 전체를 적용하는 비동기 작업.
  Future<void> applyVisibleCurrencies(List<CurrencyModel> currencies) async {
    final current = readState();

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
      invalidatePendingFetches();
    }

    writeState(current.copyWith(visibleCurrencies: normalizedCurrencies));

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
    final current = readState();

    if (currency.code == current.baseCurrency.code) {
      setErrorMessage('기준 통화는 표시 통화에 다시 추가할 수 없습니다.');
      return;
    }

    if (current.visibleCurrencies.any((item) => item.code == currency.code)) {
      setErrorMessage('이미 화면에 표시된 통화입니다.');
      return;
    }

    invalidatePendingFetches();

    writeState(
      current.copyWith(
        visibleCurrencies: <CurrencyModel>[
          ...current.visibleCurrencies,
          currency,
        ],
      ),
    );

    await _persistAndRefreshRates();
  }

  // 화면에 표시할 통화 목록에서 특정 통화를 제거하는 비동기 작업.
  // 기준 통화는 제거할 수 없음.
  Future<void> removeCurrency(CurrencyModel currency) async {
    final current = readState();

    if (currency.code == current.baseCurrency.code) {
      setErrorMessage('기준 통화는 삭제할 수 없습니다.');
      return;
    }

    final remaining = current.visibleCurrencies
        .where((item) => item.code != currency.code)
        .toList();

    if (remaining.length == current.visibleCurrencies.length) {
      return;
    }

    invalidatePendingFetches();

    writeState(current.copyWith(visibleCurrencies: remaining));

    await _persistAndRefreshRates();
  }

  Future<void> _persistAndRefreshRates() async {
    try {
      await _saveCurrencyState();
    } catch (error, stackTrace) {
      debugPrint('통화 설정 저장 실패: $error');
      debugPrint('$stackTrace');
    }

    if (!isMounted()) return;

    // 로컬 저장 실패가 최신 환율 조회까지 막지 않도록 한다.
    await fetchRates();
  }

  // 기준 통화와 화면에 표시할 통화 목록을 로컬 스토리지에 저장하는 비동기 작업.
  Future<void> _saveCurrencyState() async {
    final storage = readStorage();

    await storage.saveBaseCurrency(readState().baseCurrency.code);

    if (!isMounted()) return;

    await storage.saveVisibleCurrencies(
      readState().visibleCurrencies.map((currency) => currency.code).toList(),
    );
  }
}
