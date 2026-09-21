import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/network/api_exception.dart';
import '../models/api_error_response.dart';
import '../models/exchange_rate_history_model.dart';
import '../models/exchange_rate_history_response.dart';
import '../models/exchange_rate_response.dart';

/// 환율 API 통신을 담당하는 단일 서비스.
///
/// 기존 `ExchangeApiService`와 `ExchangeRateApiService`에 중복되어 있던
/// 최신 환율 조회, 기간별 환율 조회, URI 생성, 네트워크 예외 처리,
/// JSON 파싱 및 백엔드 오류 응답 처리를 이 클래스 하나로 통합한다.
///
/// 역할:
/// - 최신 환율 조회
/// - 기간별 환율 조회
/// - `ApiConfig`를 이용한 URI 생성
/// - 프로젝트 공통 `ApiException`으로 예외 통일
/// - 백엔드 `ApiErrorResponse` 처리
/// - 응답 모델을 이용한 JSON 파싱
///
/// 현재 환율 API 규모에서는 HTTP/파싱/오류 처리를 별도 클래스로 더 쪼개지 않고
/// 이 서비스 내부의 private 메서드로 역할을 분리한다. 기능이 커져 책임이 복잡해질 때
/// `ExchangeHttpClient`/Parser 계층 분리를 다시 검토한다.
///
/// 사용이 끝난 경우 [dispose]를 호출하여 내부 [http.Client]를 정리해야 한다.
class ExchangeRateApiService {
  ExchangeRateApiService({http.Client? client})
    : _client = client ?? http.Client();

  /// 환율 API 공통 타임아웃.
  ///
  /// 기존 서비스의 8초/15초 설정이 서로 달랐기 때문에
  /// 하나의 값으로 통일한다.
  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      '백엔드 서버에 연결하지 못했습니다. 인터넷 연결 상태를 확인해 주세요.';

  final http.Client _client;

  // ---------------------------------------------------------------------------
  // 최신 환율
  // ---------------------------------------------------------------------------

  /// 최신 환율 응답 중 rates만 반환한다.
  ///
  /// 화면이나 Provider에서 전체 응답의 `fetchedAt`, `rateDate`가 필요하지 않고
  /// 환율 Map만 필요한 경우 사용할 수 있다.
  Future<Map<String, double>> fetchLatestRates({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final response = await fetchLatestRatesResponse(
      baseCurrency: baseCurrency,
      targetCurrencies: targetCurrencies,
    );

    return response.rates;
  }

  /// 최신 환율 API의 전체 응답을 반환한다.
  ///
  /// 백엔드:
  /// GET /api/v1/exchange/rates
  ///
  /// Query:
  /// - base
  /// - targets
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final normalizedBaseCurrency = _normalizeCurrencyCode(baseCurrency);

    if (normalizedBaseCurrency.isEmpty) {
      throw const ApiException(message: '기준 통화 코드가 올바르지 않습니다.');
    }

    final normalizedTargetCurrencies = targetCurrencies
        .map(_normalizeCurrencyCode)
        .where((currency) => currency.isNotEmpty)
        .where((currency) => currency != normalizedBaseCurrency)
        .toSet()
        .toList(growable: false);

    // 대상 통화가 없다면 서버를 호출할 필요가 없다.
    if (normalizedTargetCurrencies.isEmpty) {
      return ExchangeRateResponse(
        baseCurrency: normalizedBaseCurrency,
        rates: const <String, double>{},
        rateDate: null,
        fetchedAt: DateTime.now(),
      );
    }

    final uri = ApiConfig.exchangeRatesUri(
      baseCurrency: normalizedBaseCurrency,
      targetCurrencies: normalizedTargetCurrencies,
    );

    final response = await _sendGetRequest(uri);

    return _parseLatestRatesResponse(response);
  }

  // ---------------------------------------------------------------------------
  // 기간별 환율
  // ---------------------------------------------------------------------------

  /// 기존 `ExchangeApiService` 호출부와 호환되는 기간별 환율 조회 메서드.
  ///
  /// 현재 차트 위젯들이 `ChartPeriod`를 전달하고 있기 때문에
  /// UI 호출부를 즉시 모두 바꾸지 않아도 되도록 유지한다.
  ///
  /// 내부적으로는 [fetchHistoricalRatesResponse]를 호출하여
  /// 전체 응답을 받은 뒤 `rates`만 반환한다.
  Future<List<ExchangeRateHistoryModel>> fetchHistoricalRates({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required ChartPeriod period,
  }) async {
    final endDate = DateTime.now();
    final startDate = period.startDateFrom(endDate);

    final response = await fetchHistoricalRatesResponse(
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
      startDate: startDate,
      endDate: endDate,
    );

    return response.rates;
  }

  /// 기간별 환율 API의 전체 응답을 반환한다.
  ///
  /// 백엔드:
  /// GET /api/v1/exchange/history
  ///
  /// Query:
  /// - base
  /// - target
  /// - startDate
  /// - endDate
  ///
  /// `rates`뿐 아니라 `fetchedAt`, `startDate`, `endDate`도 유지하므로
  /// 차트의 마지막 업데이트 시각이나 캐시 메타데이터가 필요한 경우
  /// 이 메서드를 사용하는 것이 적합하다.
  Future<ExchangeRateHistoryResponse> fetchHistoricalRatesResponse({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final normalizedBaseCurrency = _normalizeCurrencyCode(baseCurrencyCode);
    final normalizedTargetCurrency = _normalizeCurrencyCode(targetCurrencyCode);

    if (normalizedBaseCurrency.isEmpty || normalizedTargetCurrency.isEmpty) {
      throw const ApiException(message: '통화 코드가 올바르지 않습니다.');
    }

    if (startDate.isAfter(endDate)) {
      throw const ApiException(message: '환율 조회 시작일은 종료일보다 늦을 수 없습니다.');
    }

    // 기준 통화와 대상 통화가 같으면 서버 호출 없이 환율 1을 반환한다.
    // 같은 통화의 환율은 기간 전체에서 항상 1이므로 시작일/종료일 두 점만으로
    // 직선을 표현한다. 기간 내 모든 날짜를 생성하지 않는 의도된 최적화다.
    if (normalizedBaseCurrency == normalizedTargetCurrency) {
      return ExchangeRateHistoryResponse(
        baseCurrency: normalizedBaseCurrency,
        targetCurrency: normalizedTargetCurrency,
        startDate: startDate,
        endDate: endDate,
        rates: <ExchangeRateHistoryModel>[
          ExchangeRateHistoryModel(
            date: startDate,
            rate: 1,
            baseCurrencyCode: normalizedBaseCurrency,
            targetCurrencyCode: normalizedTargetCurrency,
          ),
          ExchangeRateHistoryModel(
            date: endDate,
            rate: 1,
            baseCurrencyCode: normalizedBaseCurrency,
            targetCurrencyCode: normalizedTargetCurrency,
          ),
        ],
        // 서버 호출이 없으므로 로컬 생성 시각을 사용한다.
        fetchedAt: DateTime.now(),
      );
    }

    final uri = ApiConfig.exchangeHistoryUri(
      baseCurrency: normalizedBaseCurrency,
      targetCurrency: normalizedTargetCurrency,
      startDate: startDate,
      endDate: endDate,
    );

    final response = await _sendGetRequest(uri);

    return _parseHistoricalRatesResponse(response);
  }

  // ---------------------------------------------------------------------------
  // HTTP 요청
  // ---------------------------------------------------------------------------

  /// GET 요청을 수행하고 네트워크 계층의 오류를 [ApiException]으로 변환한다.
  ///
  /// `http.ClientException`과 플랫폼별 연결 예외는 사용자 입장에서 원인을
  /// 정확히 구분하기 어렵기 때문에 동일한 안내 메시지를 사용한다.
  /// 대신 디버그 로그에서는 예외 종류를 구분해 원인 추적이 가능하도록 한다.
  Future<http.Response> _sendGetRequest(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        message: '백엔드 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on http.ClientException catch (error, stackTrace) {
      debugPrint('환율 API HTTP 연결 실패: $error');
      debugPrint('$stackTrace');

      throw const ApiException(message: _connectionErrorMessage);
    } catch (error, stackTrace) {
      debugPrint('환율 API 연결 실패: $error');
      debugPrint('$stackTrace');

      throw const ApiException(message: _connectionErrorMessage);
    }
  }

  // ---------------------------------------------------------------------------
  // 정상 응답 파싱
  // ---------------------------------------------------------------------------

  /// 최신 환율 API 응답을 [ExchangeRateResponse]로 변환한다.
  ExchangeRateResponse _parseLatestRatesResponse(http.Response response) {
    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode != 200) {
      throw _createApiExceptionFromErrorResponse(
        response: response,
        decodedBody: decodedBody,
      );
    }

    try {
      return ExchangeRateResponse.fromJson(decodedBody);
    } on FormatException catch (error) {
      debugPrint('최신 환율 응답 파싱 실패: $error');

      throw const ApiException(message: '환율 응답 형식이 올바르지 않습니다.');
    } catch (error, stackTrace) {
      debugPrint('최신 환율 응답 처리 실패: $error');
      debugPrint('$stackTrace');

      throw const ApiException(message: '환율 데이터를 처리하지 못했습니다.');
    }
  }

  /// 기간별 환율 API 응답을 [ExchangeRateHistoryResponse]로 변환한다.
  ///
  /// 기존 두 서비스에 중복되어 있던 `baseCurrency`, `targetCurrency`,
  /// `rates` 수동 파싱 로직은 Response Model로 이동하여 한 곳에서 관리한다.
  ExchangeRateHistoryResponse _parseHistoricalRatesResponse(
    http.Response response,
  ) {
    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode != 200) {
      throw _createApiExceptionFromErrorResponse(
        response: response,
        decodedBody: decodedBody,
      );
    }

    try {
      return ExchangeRateHistoryResponse.fromJson(decodedBody);
    } on FormatException catch (error) {
      debugPrint('기간별 환율 응답 파싱 실패: $error');

      throw const ApiException(message: '기간별 환율 응답 형식이 올바르지 않습니다.');
    } catch (error, stackTrace) {
      debugPrint('기간별 환율 응답 처리 실패: $error');
      debugPrint('$stackTrace');

      throw const ApiException(message: '기간별 환율 데이터를 처리하지 못했습니다.');
    }
  }

  // ---------------------------------------------------------------------------
  // 공통 JSON 디코딩
  // ---------------------------------------------------------------------------

  /// HTTP 응답 본문을 JSON 객체로 변환한다.
  ///
  /// 빈 응답이나 JSON 객체가 아닌 응답은 프로젝트 공통 [ApiException]으로 변환한다.
  Map<String, dynamic> _decodeResponseBody(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _messageForStatusCode(response.statusCode),
      );
    }

    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! Map<String, dynamic>) {
        throw const FormatException('응답 본문이 JSON 객체가 아닙니다.');
      }

      return decodedBody;
    } catch (error) {
      debugPrint('환율 API 응답 JSON 디코딩 실패: $error');

      throw ApiException(
        statusCode: response.statusCode,
        message: '서버 응답 형식이 올바르지 않습니다.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 오류 응답 처리
  // ---------------------------------------------------------------------------

  /// 백엔드 오류 응답을 [ApiErrorResponse]로 파싱한 뒤 [ApiException]으로 변환한다.
  ApiException _createApiExceptionFromErrorResponse({
    required http.Response response,
    required Map<String, dynamic> decodedBody,
  }) {
    ApiErrorResponse? errorResponse;

    try {
      errorResponse = ApiErrorResponse.fromJson(decodedBody);
    } catch (error, stackTrace) {
      // 오류 응답 파싱 자체가 실패해도 실제 HTTP 상태 코드는 유지한다.
      debugPrint('환율 API 오류 응답 파싱 실패: $error');
      debugPrint('$stackTrace');
    }

    return ApiException(
      statusCode: response.statusCode,
      code: errorResponse?.code,
      message: _messageForErrorResponse(
        statusCode: response.statusCode,
        errorResponse: errorResponse,
      ),
      path: errorResponse?.path,
      timestamp: errorResponse?.timestamp,
    );
  }

  /// HTTP 상태 코드와 백엔드 오류 코드를 기준으로 사용자용 메시지를 결정한다.
  String _messageForErrorResponse({
    required int statusCode,
    required ApiErrorResponse? errorResponse,
  }) {
    switch (errorResponse?.errorCode) {
      case ApiErrorCode.exchangeProviderUnavailable:
        return '현재 환율 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해 주세요.';

      case ApiErrorCode.internalServerError:
        return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';

      case ApiErrorCode.invalidRequest:
        return errorResponse?.message ?? '환율 요청값이 올바르지 않습니다.';

      default:
        break;
    }

    // 오류 코드가 없거나 알 수 없는 경우 HTTP 상태 코드 기준으로 fallback.
    if (statusCode == 503) {
      return '현재 환율 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 500) {
      return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 400) {
      return errorResponse?.message ?? '환율 요청값이 올바르지 않습니다.';
    }

    return errorResponse?.message ?? _messageForStatusCode(statusCode);
  }

  /// 백엔드 ErrorResponse를 해석할 수 없을 때 사용할 기본 메시지를 반환한다.
  String _messageForStatusCode(int statusCode) {
    if (statusCode == 400) {
      return '환율 요청값이 올바르지 않습니다.';
    }

    if (statusCode == 404) {
      return '요청한 환율 API 주소를 찾을 수 없습니다.';
    }

    if (statusCode == 500) {
      return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 503) {
      return '현재 환율 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    }

    return '환율 데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
  }

  // ---------------------------------------------------------------------------
  // 입력값 정규화
  // ---------------------------------------------------------------------------

  /// 통화 코드를 API 요청에서 사용하는 표준 형태로 정규화한다.
  ///
  /// 현재는 공백 제거와 대문자 변환만 담당한다.
  /// 향후 ISO 4217 형식 검증이나 지원 통화 목록 검증이 필요해지면
  /// 이 메서드 한 곳에서 규칙을 확장할 수 있다.
  String _normalizeCurrencyCode(String code) {
    return code.trim().toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // 리소스 정리
  // ---------------------------------------------------------------------------

  /// 내부 [http.Client]를 종료한다.
  ///
  /// 이 서비스를 직접 생성한 객체가 자신의 `dispose()`에서 호출해야 한다.
  void dispose() {
    _client.close();
  }
}
