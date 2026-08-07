import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/exchange_rate_response.dart';
import '../models/exchange_rate_history_model.dart';

// 환율 API 서비스를 제공하는 클래스
class ExchangeApiService {
  ExchangeApiService({http.Client? client}) : _client = client ?? http.Client();

  static const String _definedBaseUrl = String.fromEnvironment(
    'TRIPBLER_API_BASE_URL',
  );

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;

  // 실행 환경에 따라 백엔드 기본 주소를 결정하는 getter
  String get _baseUrl {
    if (_definedBaseUrl.isNotEmpty) {
      return _definedBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8080';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8080';

      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return 'http://localhost:8080';

      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return 'http://localhost:8080';
    }
  }

  // 최신 환율 데이터의 rates만 가져오는 메서드
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

  // 최신 환율 데이터 전체 응답을 가져오는 메서드
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final normalizedBaseCurrency = baseCurrency.trim().toUpperCase();

    final normalizedTargetCurrencies = targetCurrencies
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .where((code) => code != normalizedBaseCurrency)
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

    final uri = Uri.parse('$_baseUrl/api/v1/exchange/rates').replace(
      queryParameters: <String, String>{
        'base': normalizedBaseCurrency,
        'targets': normalizedTargetCurrencies.join(','),
      },
    );

    final response = await _sendGetRequest(uri);

    if (response.statusCode != 200) {
      throw _createApiExceptionFromResponse(response);
    }

    try {
      final Map<String, dynamic> jsonBody = _decodeJsonObject(response);

      return ExchangeRateResponse.fromJson(jsonBody);
    } catch (_) {
      throw Exception('환율 응답 형식이 올바르지 않습니다.');
    }
  }
  // GET 요청을 보내고 네트워크 오류와 타임아웃을 처리하는 메서드
  Future<http.Response> _sendGetRequest(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      // 백엔드가 응답하지 않는 경우 사용자용 메시지로 변환함.
      throw const ExchangeApiException(
        message: '서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on http.ClientException {
      // HTTP 클라이언트 레벨의 연결 실패를 사용자용 메시지로 변환함.
      throw const ExchangeApiException(
        message: '서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    } catch (_) {
      // SocketException 등 플랫폼별 네트워크 예외를 한 번에 사용자용 메시지로 변환함.
      throw const ExchangeApiException(
        message: '서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    }
  }

  //
  // 백엔드 응답:
  // {
  //   "baseCurrency": "KRW",
  //   "targetCurrency": "USD",
  //   "startDate": "2026-07-01",
  //   "endDate": "2026-07-31",
  //   "rates": [
  //     {
  //       "date": "2026-07-01",
  //       "rate": 0.00064
  //     }
  //   ],
  //   "fetchedAt": "2026-08-05T22:03:47.0770315"
  // }
  //
  // 백엔드의 기간별 환율 응답을 차트에서 사용할 수 있는 모델 리스트로 변환함.
  // 특정 기간 동안의 환율 변동 데이터를 가져오는 메서드
  Future<List<ExchangeRateHistoryModel>> fetchHistoricalRates({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required ChartPeriod period,
  }) async {
    final endDate = DateTime.now();
    final startDate = period.startDateFrom(endDate);

    final normalizedBaseCurrency = baseCurrencyCode.trim().toUpperCase();
    final normalizedTargetCurrency = targetCurrencyCode.trim().toUpperCase();

    if (normalizedBaseCurrency.isEmpty || normalizedTargetCurrency.isEmpty) {
      throw Exception('통화 코드가 올바르지 않습니다.');
    }

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

    final uri = Uri.parse('$_baseUrl/api/v1/exchange/history').replace(
      queryParameters: <String, String>{
        'base': normalizedBaseCurrency,
        'target': normalizedTargetCurrency,
        'startDate': _formatDate(startDate),
        'endDate': _formatDate(endDate),
      },
    );

    final response = await _sendGetRequest(uri);

    if (response.statusCode != 200) {
      throw _createApiExceptionFromResponse(response);
    }

    final Map<String, dynamic> jsonBody = _decodeJsonObject(response);

    final baseCurrencyValue = jsonBody['baseCurrency'];
    final targetCurrencyValue = jsonBody['targetCurrency'];
    final ratesValue = jsonBody['rates'];

    final responseBaseCurrencyCode =
        baseCurrencyValue is String && baseCurrencyValue.trim().isNotEmpty
        ? baseCurrencyValue.trim().toUpperCase()
        : normalizedBaseCurrency;

    final responseTargetCurrencyCode =
        targetCurrencyValue is String && targetCurrencyValue.trim().isNotEmpty
        ? targetCurrencyValue.trim().toUpperCase()
        : normalizedTargetCurrency;

    if (ratesValue is! List) {
      throw Exception('환율 그래프 응답 형식이 올바르지 않습니다.');
    }

    final historyRates = ratesValue.map((item) {
      if (item is! Map<String, dynamic>) {
        throw Exception('환율 그래프 응답 항목 형식이 올바르지 않습니다.');
      }

      return ExchangeRateHistoryModel.fromBackendJson(
        item,
        baseCurrencyCode: responseBaseCurrencyCode,
        targetCurrencyCode: responseTargetCurrencyCode,
      );
    }).toList()..sort((first, second) => first.date.compareTo(second.date));

    return historyRates;
  }

  // 응답 본문을 JSON 객체로 변환하는 메서드
  Map<String, dynamic> _decodeJsonObject(http.Response response) {
    final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

    if (decodedBody is! Map<String, dynamic>) {
      throw Exception('서버 응답 형식이 올바르지 않습니다.');
    }

    return decodedBody;
  }

  // 백엔드 오류 응답에서 message 값을 추출하는 메서드
  String _parseErrorMessage(
    http.Response response, {
    required String fallbackMessage,
  }) {
    try {
      final Map<String, dynamic> jsonBody = _decodeJsonObject(response);
      final message = jsonBody['message'];

      if (message is String && message.trim().isNotEmpty) {
        return message;
      }

      return fallbackMessage;
    } catch (_) {
      return fallbackMessage;
    }
  }

  // 백엔드 오류 응답을 읽어서 사용자에게 보여줄 예외로 변환하는 메서드
  ExchangeApiException _createApiExceptionFromResponse(http.Response response) {
    try {
      final Map<String, dynamic> jsonBody = _decodeJsonObject(response);

      final status = jsonBody['status'];
      final code = jsonBody['code'];
      final message = jsonBody['message'];

      final parsedStatus = status is int ? status : response.statusCode;
      final parsedCode = code is String ? code : null;

      final backendMessage = message is String && message.trim().isNotEmpty
          ? message.trim()
          : _messageForStatusCode(response.statusCode);

      return ExchangeApiException(
        status: parsedStatus,
        code: parsedCode,
        message: _messageForErrorCode(
          statusCode: response.statusCode,
          code: parsedCode,
          backendMessage: backendMessage,
        ),
      );
    } catch (_) {
      return ExchangeApiException(
        status: response.statusCode,
        message: _messageForStatusCode(response.statusCode),
      );
    }
  }

  // 백엔드 code와 HTTP 상태 코드를 기준으로 최종 사용자 메시지를 결정하는 메서드
  String _messageForErrorCode({
    required int statusCode,
    required String? code,
    required String backendMessage,
  }) {
    if (statusCode == 503 || code == 'EXCHANGE_PROVIDER_UNAVAILABLE') {
      return '환율 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 500 || code == 'INTERNAL_SERVER_ERROR') {
      return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    // 400 INVALID_REQUEST는 백엔드가 내려준 구체적인 message를 우선 사용함.
    if (statusCode == 400 || code == 'INVALID_REQUEST') {
      return backendMessage;
    }

    return backendMessage;
  }

  // HTTP 상태 코드에 따라 사용자에게 보여줄 기본 오류 메시지를 반환하는 메서드
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

  // DateTime 객체를 API 요청 형식에 맞게 문자열로 변환하는 메서드
  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  // http.Client를 정리하는 메서드
  void dispose() {
    _client.close();
  }
}

// 백엔드 오류와 네트워크 오류를 Flutter 내부에서 구분하기 위한 예외 클래스
class ExchangeApiException implements Exception {
  final int? status;
  final String? code;
  final String message;

  const ExchangeApiException({required this.message, this.status, this.code});

  @override
  String toString() {
    return message;
  }
}
