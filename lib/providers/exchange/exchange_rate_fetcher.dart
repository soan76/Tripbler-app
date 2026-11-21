import '../../core/network/api_exception.dart';
import '../../services/exchange_rate_api_service.dart';
import '../../services/local_storage_service.dart';
import 'exchange_state.dart';

/// 저장된 환율을 화면에 쓸 수 있는 최대 기간.
const Duration exchangeRateCacheMaxAge = Duration(days: 3);

/// 서버에서 환율을 받아 상태에 반영하고, 실패하면 마지막 성공값이나 기기 캐시로 대신한다.
///
/// 상태를 읽고 내보내는 일과 요청 번호 관리는 넘겨받은 함수가 맡는다.
/// - [readApiService]: 현재 환율 API 서비스를 읽는다.
/// - [readStorage]: 현재 기기 저장소 서비스를 읽는다.
/// - [isMounted]: 상태 객체가 아직 폐기되지 않았는지 확인한다.
/// - [readState]: 현재 상태를 읽는다.
/// - [writeState]: 새 상태를 내보낸다.
/// - [startRequest]: 새 요청 번호를 발급한다. 목록 편집 때 무효화하는 번호와 같은 카운터다.
/// - [isLatestRequest]: 요청 번호가 가장 최근 요청인지(폐기되지 않았는지 포함) 확인한다.
class ExchangeRateFetcher {
  const ExchangeRateFetcher({
    required this.readApiService,
    required this.readStorage,
    required this.isMounted,
    required this.readState,
    required this.writeState,
    required this.startRequest,
    required this.isLatestRequest,
  });

  final ExchangeRateApiService Function() readApiService;
  final LocalStorageService Function() readStorage;
  final bool Function() isMounted;
  final ExchangeState Function() readState;
  final void Function(ExchangeState state) writeState;
  final int Function() startRequest;
  final bool Function(int requestId) isLatestRequest;

  // 환율 정보를 가져오는 비동기 작업.
  // 가장 최근에 시작된 요청만 처리하고, 이전 요청은 무시함.
  Future<void> fetch() async {
    final requestId = startRequest();

    if (!isMounted()) return;

    final baseCurrencyCode = readState().baseCurrency.code;

    writeState(readState().copyWith(isLoading: true, clearErrorMessage: true));

    final storage = readStorage();

    try {
      if (readState().rates.isEmpty) {
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
              DateTime.now().difference(updated) < exchangeRateCacheMaxAge) {
            writeState(
              readState().copyWith(
                rates: Map<String, double>.from(rates),
                lastUpdated: updated,
                usesFallbackSource: false,
              ),
            );
          }
        } catch (_) {
          // 기기 저장소 오류가 서버 재조회까지 막지 않게 한다.
        }
      }
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) return;
      final targetCodes = readState().visibleCurrencies
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
        // 환율을 비우면 대체 출처 안내도 함께 지운다.
        final current = readState();
        if (current.rates.isNotEmpty || current.usesFallbackSource) {
          writeState(
            current.copyWith(
              rates: <String, double>{},
              usesFallbackSource: false,
            ),
          );
        }
        return;
      }

      // Spring Boot 백엔드의 최신 환율 API 응답 전체를 가져옴.
      // rates뿐만 아니라 fetchedAt도 함께 받기 위해 fetchLatestRatesResponse()를 사용함.
      final latestRatesResponse = await readApiService()
          .fetchLatestRatesResponse(
            baseCurrency: baseCurrencyCode,
            targetCurrencies: targetCodes,
          );

      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      // Flutter에서 DateTime.now()로 만든 시간이 아니라,
      // 백엔드가 환율을 가져온 시각인 fetchedAt을 마지막 업데이트 시각으로 사용함.
      final savedRates = Map<String, double>.from(latestRatesResponse.rates);
      writeState(
        readState().copyWith(
          rates: savedRates,
          lastUpdated: latestRatesResponse.fetchedAt,
          usesFallbackSource: latestRatesResponse.fromFallbackSource,
          errorMessage: latestRatesResponse.stale
              ? '응답 지연으로 마지막 성공 환율을 표시합니다.'
              : null,
        ),
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
          writeState(
            readState().copyWith(errorMessage: '최신 환율은 표시했지만 기기에 저장하지 못했습니다.'),
          );
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
        writeState(readState().copyWith(isLoading: false));
      }
    }
  }

  bool _isCurrentFetch(int requestId, String baseCurrencyCode) {
    return isLatestRequest(requestId) &&
        readState().baseCurrency.code == baseCurrencyCode;
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
    final lastUpdated = readState().lastUpdated;
    if (readState().rates.isNotEmpty &&
        lastUpdated != null &&
        DateTime.now().difference(lastUpdated) < exchangeRateCacheMaxAge) {
      writeState(
        readState().copyWith(
          errorMessage: '$fallbackMessage 마지막 성공 데이터를 표시합니다.',
        ),
      );
      return;
    }
    final storage = readStorage();
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
              exchangeRateCacheMaxAge) {
        writeState(
          readState().copyWith(
            rates: Map<String, double>.from(cachedRates),
            lastUpdated: cachedLastUpdated,
            usesFallbackSource: false,
            errorMessage:
                '$fallbackMessage '
                '마지막 저장 데이터를 표시합니다.',
          ),
        );
      } else {
        // 현재 기준 통화에서 사용할 수 있는 캐시가 없으면
        // 이전 환율과 업데이트 시각을 화면에 남기지 않는다.
        writeState(
          readState().copyWith(
            rates: <String, double>{},
            clearLastUpdated: true,
            usesFallbackSource: false,
            errorMessage: fallbackMessage,
          ),
        );
      }
    } catch (_) {
      // 캐시 조회 과정에서 예외가 발생했더라도,
      // 이미 오래된 요청이라면 현재 화면 상태를 변경하지 않는다.
      if (!_isCurrentFetch(requestId, baseCurrencyCode)) {
        return;
      }

      writeState(
        readState().copyWith(
          rates: <String, double>{},
          clearLastUpdated: true,
          usesFallbackSource: false,
          errorMessage: fallbackMessage,
        ),
      );
    }
  }
}
