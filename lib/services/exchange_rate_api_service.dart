import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/network/api_exception.dart';
import '../models/api_error_response.dart';
import '../models/exchange_rate_history_model.dart';
import '../models/exchange_rate_response.dart';
// 환율 API 서비스 클래스
class ExchangeRateApiService {
  ExchangeRateApiService({http.Client? client})
    : _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;
  // 최신 환율을 조회하는 메서드
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
  // 최신 환율 응답을 조회하는 메서드
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final normalizedBaseCurrency = baseCurrency.trim().toUpperCase();

    final normalizedTargetCurrencies = targetCurrencies
        .map((currency) => currency.trim().toUpperCase())
        .where((currency) => currency.isNotEmpty)
        .where((currency) => currency != normalizedBaseCurrency)
        .toSet()
        .toList(growable: false);

    if (normalizedTargetCurrencies.isEmpty) {
      return ExchangeRateResponse(
        baseCurrency: normalizedBaseCurrency,
        rates: const <String, double>{},
        rateDate: null,
        fetchedAt: DateTime.now(),
      );
    }
    // 최신 환율 조회를 위한 URI 생성
    final uri = ApiConfig.exchangeRatesUri(
      baseCurrency: normalizedBaseCurrency,
      targetCurrencies: normalizedTargetCurrencies,
    );

    final response = await _sendGetRequest(uri);

    return _parseLatestRatesResponse(response);
  }
  // 특정 기간 동안의 환율 기록을 조회하는 메서드
  Future<List<ExchangeRateHistoryModel>> fetchHistoricalRates({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final normalizedBaseCurrency = baseCurrencyCode.trim().toUpperCase();

    final normalizedTargetCurrency = targetCurrencyCode.trim().toUpperCase();

    if (normalizedBaseCurrency.isEmpty || normalizedTargetCurrency.isEmpty) {
      throw const ApiException(message: '통화 코드가 올바르지 않습니다.');
    }
    // 동일한 통화 코드일 경우, 환율 기록을 1로 설정하여 반환
    if (normalizedBaseCurrency == normalizedTargetCurrency) {
      return <ExchangeRateHistoryModel>[
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
      ];
    }

    final uri = ApiConfig.exchangeHistoryUri(
      baseCurrency: normalizedBaseCurrency,
      targetCurrency: normalizedTargetCurrency,
      startDate: startDate,
      endDate: endDate,
    );

    final response = await _sendGetRequest(uri);

    return _parseHistoricalRatesResponse(
      response: response,
      fallbackBaseCurrencyCode: normalizedBaseCurrency,
      fallbackTargetCurrencyCode: normalizedTargetCurrency,
    );
  }
  // 특정 기간 동안의 환율 기록 응답을 조회하는 메서드
  Future<http.Response> _sendGetRequest(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        message: '백엔드 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on ApiException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('백엔드 연결 실패: $error');
      debugPrint('$stackTrace');

      throw const ApiException(
        message: '백엔드 서버에 연결하지 못했습니다. 서버가 실행 중인지 확인해 주세요.',
      );
    }
  }
  // 최신 환율 응답을 파싱하는 메서드
  ExchangeRateResponse _parseLatestRatesResponse(http.Response response) {
    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 200) {
      try {
        return ExchangeRateResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('최신 환율 응답 파싱 실패: $error');

        throw const ApiException(message: '환율 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }
  // 특정 기간 동안의 환율 기록 응답을 파싱하는 메서드
  List<ExchangeRateHistoryModel> _parseHistoricalRatesResponse({
    required http.Response response,
    required String fallbackBaseCurrencyCode,
    required String fallbackTargetCurrencyCode,
  }) {
    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode != 200) {
      throw _createApiExceptionFromErrorResponse(
        response: response,
        decodedBody: decodedBody,
      );
    } 
    // 환율 기록 응답을 파싱하여 ExchangeRateHistoryModel 리스트로 변환
    try {
      final baseCurrencyValue = decodedBody['baseCurrency'];
      final targetCurrencyValue = decodedBody['targetCurrency'];
      final ratesValue = decodedBody['rates'];

      final baseCurrencyCode =
          baseCurrencyValue is String && baseCurrencyValue.trim().isNotEmpty
          ? baseCurrencyValue.trim().toUpperCase()
          : fallbackBaseCurrencyCode;

      final targetCurrencyCode =
          targetCurrencyValue is String && targetCurrencyValue.trim().isNotEmpty
          ? targetCurrencyValue.trim().toUpperCase()
          : fallbackTargetCurrencyCode;

      if (ratesValue is! List) {
        throw const FormatException('rates 값이 올바르지 않습니다.');
      }

      final historyRates = ratesValue.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('rates 항목 형식이 올바르지 않습니다.');
        }

        return ExchangeRateHistoryModel.fromBackendJson(
          item,
          baseCurrencyCode: baseCurrencyCode,
          targetCurrencyCode: targetCurrencyCode,
        );
      }).toList()..sort((first, second) => first.date.compareTo(second.date));

      return historyRates;
    } on FormatException catch (error) {
      debugPrint('기간별 환율 응답 파싱 실패: $error');

      throw const ApiException(message: '기간별 환율 응답 형식이 올바르지 않습니다.');
    } catch (error, stackTrace) {
      debugPrint('기간별 환율 응답 처리 실패: $error');
      debugPrint('$stackTrace');

      throw const ApiException(message: '기간별 환율 데이터를 처리하지 못했습니다.');
    }
  }
  // 응답 본문을 디코딩하고 JSON 객체로 변환하는 메서드
  Map<String, dynamic> _decodeResponseBody(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _messageForStatusCode(response.statusCode),
      );
    }
    // 응답 본문을 UTF-8로 디코딩하고 JSON 객체로 변환
    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! Map<String, dynamic>) {
        throw const FormatException('응답 본문이 JSON 객체가 아닙니다.');
      }

      return decodedBody;
    } on ApiException {
      rethrow;
    } catch (error) {
      debugPrint('응답 JSON 디코딩 실패: $error');

      throw ApiException(
        statusCode: response.statusCode,
        message: '서버 응답 형식이 올바르지 않습니다.',
      );
    }
  }
  // API 오류 응답을 기반으로 ApiException 객체를 생성하는 메서드
  ApiException _createApiExceptionFromErrorResponse({
    required http.Response response,
    required Map<String, dynamic> decodedBody,
  }) {
    ApiErrorResponse? errorResponse;

    try {
      errorResponse = ApiErrorResponse.fromJson(decodedBody);
    } catch (_) {
      errorResponse = null;
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
  // 오류 응답에 대한 사용자 친화적인 메시지를 생성하는 메서드
  String _messageForErrorResponse({
    required int statusCode,
    required ApiErrorResponse? errorResponse,
  }) {
    if (statusCode == 400) {
      return errorResponse?.message ?? '환율 요청값이 올바르지 않습니다.';
    }

    if (statusCode == 503) {
      return '현재 환율 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 500) {
      return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    return errorResponse?.message ?? '환율 데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
  }
  // HTTP 상태 코드에 따른 사용자 친화적인 메시지를 생성하는 메서드
  String _messageForStatusCode(int statusCode) {
    if (statusCode == 400) {
      return '환율 요청값이 올바르지 않습니다.';
    }

    if (statusCode == 503) {
      return '현재 환율 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 500) {
      return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    return '환율 데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
  }

  void dispose() {
    _client.close();
  }
}
