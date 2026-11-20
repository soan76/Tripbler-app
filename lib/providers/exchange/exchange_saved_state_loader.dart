import '../../domain/exchange/exchange_currency_manager.dart';
import '../../models/currency_model.dart';
import '../../services/local_storage_service.dart';
import 'exchange_rate_fetcher.dart';
import 'exchange_state.dart';

/// 기기에 저장된 기준 통화·표시 통화·입력 금액·환율 캐시를 불러와 상태에 반영한다.
///
/// 상태를 읽고 내보내는 일은 넘겨받은 함수가 맡는다.
/// - [readStorage]: 현재 기기 저장소 서비스를 읽는다.
/// - [isMounted]: 상태 객체가 아직 폐기되지 않았는지 확인한다.
/// - [readState]: 현재 상태를 읽는다.
/// - [writeState]: 새 상태를 내보낸다.
class ExchangeSavedStateLoader {
  const ExchangeSavedStateLoader({
    required this.readStorage,
    required this.isMounted,
    required this.readState,
    required this.writeState,
  });

  final LocalStorageService Function() readStorage;
  final bool Function() isMounted;
  final ExchangeState Function() readState;
  final void Function(ExchangeState state) writeState;

  // 통화 목록의 정규화/비교/입력 가능 여부 같은 순수 규칙을 담당함.
  static const ExchangeCurrencyManager _currencyManager =
      ExchangeCurrencyManager();

  // 저장된 상태를 불러오는 비동기 작업.
  // 로컬 스토리지에서 기준 통화, 화면에 표시할 통화 목록, 환율,
  // 마지막 업데이트 시각, 입력 금액을 불러와서 상태에 반영.
  Future<void> load() async {
    final storage = readStorage();

    // 기준 통화, 표시 통화, 입력 금액은 서로 독립적이므로 먼저 요청을 시작한다.
    final baseCurrencyFuture = storage.loadBaseCurrency();

    final visibleCurrenciesFuture = storage.loadVisibleCurrencies();

    final inputAmountFuture = storage.loadInputAmount();

    // 기준 통화를 먼저 확정한다.
    final savedBaseCode = await baseCurrencyFuture;

    if (!isMounted()) return;

    if (savedBaseCode != null) {
      final savedBase =
          findCurrencyByCode(savedBaseCode) ?? findCurrencyByCode('KRW')!;
      if (savedBase.code != readState().baseCurrency.code) {
        writeState(readState().copyWith(baseCurrency: savedBase));
      }
    }

    final baseCurrency = readState().baseCurrency;

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

    if (!isMounted()) return;

    final current = readState();

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
                exchangeRateCacheMaxAge
        ? Map<String, double>.from(savedRates)
        : current.rates;

    final lastUpdated = rates.isEmpty ? null : savedLastUpdated;

    writeState(
      current.copyWith(
        visibleCurrencies: visibleCurrencies,
        rates: rates,
        lastUpdated: lastUpdated,
        clearLastUpdated: lastUpdated == null,
        inputAmount: savedAmount,
      ),
    );
  }
}
