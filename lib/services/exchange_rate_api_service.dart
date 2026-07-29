import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/exchange_rate_history_model.dart';

// 환율 API 서비스
class ExchangeRateApiService {
  static const String _baseUrl = 'https://api.frankfurter.dev/v1';
  static const Duration _timeout = Duration(seconds: 8);

  // 최신 환율 조회
  Future<double> fetchLatestRate({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) async {
    if (baseCurrencyCode == targetCurrencyCode) {
      return 1;
    }
    // Frankfurter API는 base와 symbols를 사용하여 환율을 조회.
    final uri = Uri.parse(
      '$_baseUrl/latest?base=$baseCurrencyCode&symbols=$targetCurrencyCode',
    );

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode != 200) {
      debugPrint('최신 환율 API 실패');
      debugPrint('URL: $uri');
      debugPrint('statusCode: ${response.statusCode}');
      debugPrint('body: ${response.body}');

      throw Exception('최신 환율 데이터를 불러오지 못했습니다.');
    }
    final Map<String, dynamic> jsonBody =
        jsonDecode(response.body) as Map<String, dynamic>;

    final ratesValue = jsonBody['rates'];

    if (ratesValue is! Map<String, dynamic>) {
      debugPrint('최신 환율 rates 구조 오류');
      debugPrint('body: ${response.body}');
      throw Exception('최신 환율 응답 형식이 올바르지 않습니다.');
    }

    final rate = ratesValue[targetCurrencyCode];

    if (rate == null) {
      debugPrint('최신 환율에 대상 통화 없음');
      debugPrint('targetCurrencyCode: $targetCurrencyCode');
      debugPrint('body: ${response.body}');
      throw Exception('해당 통화의 환율 데이터가 없습니다.');
    }

    return (rate as num).toDouble();
  }
  // 기간별 환율 조회
  Future<List<ExchangeRateHistoryModel>> fetchHistoricalRates({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required ChartPeriod period,
  }) async {
    if (baseCurrencyCode == targetCurrencyCode) {
      final now = DateTime.now();
      final startDate = period.startDateFrom(now);

      return _generateSameCurrencyHistory(
        baseCurrencyCode: baseCurrencyCode,
        targetCurrencyCode: targetCurrencyCode,
        startDate: startDate,
        endDate: now,
      );
    }

    final endDate = DateTime.now();
    final startDate = period.startDateFrom(endDate);

    final start = _formatDate(startDate);
    final end = _formatDate(endDate);

    final uri = Uri.parse(
      '$_baseUrl/$start..$end?base=$baseCurrencyCode&symbols=$targetCurrencyCode',
    );

    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode != 200) {
      debugPrint('기간별 환율 API 실패');
      debugPrint('URL: $uri');
      debugPrint('statusCode: ${response.statusCode}');
      debugPrint('body: ${response.body}');

      throw Exception('기간별 환율 데이터를 불러오지 못했습니다.');
    }
    // 응답 JSON 구조 예시:
    // {
    //   "latest": {
    //     "base": "USD",
    //     "date": "2023-04-01",
    //     "rates": {
    //       "KRW": 1300.0
    //     }
    //   }
    // }
    final Map<String, dynamic> jsonBody =
        jsonDecode(response.body) as Map<String, dynamic>;

    final ratesValue = jsonBody['rates'];
    if (ratesValue is! Map<String, dynamic>) {
      debugPrint('기간별 환율 rates 구조 오류');
      debugPrint('URL: $uri');
      debugPrint('body: ${response.body}');

      throw Exception('기간별 환율 응답 형식이 올바르지 않습니다.');
    }

    final List<ExchangeRateHistoryModel> history = [];
    // ratesValue의 각 항목은 날짜를 키로 하고, 해당 날짜의 환율 정보를 값으로 가지는 구조.
    for (final entry in ratesValue.entries) {
      final dateText = entry.key;
      final rateMapValue = entry.value;

      if (rateMapValue is! Map<String, dynamic>) {
        continue;
      }

      final rate = rateMapValue[targetCurrencyCode];

      if (rate == null) {
        continue;
      }
      // 날짜별 환율 데이터를 ExchangeRateHistoryModel로 변환하여 리스트에 추가.
      history.add(
        ExchangeRateHistoryModel(
          date: DateTime.parse(dateText),
          rate: (rate as num).toDouble(),
          baseCurrencyCode: baseCurrencyCode,
          targetCurrencyCode: targetCurrencyCode,
        ),
      );
    }

    history.sort((a, b) => a.date.compareTo(b.date));
    // Frankfurter API는 특정 기간 동안의 환율 데이터를 제공하지만, 일부 날짜에는 데이터가 없을 수 있음. 
    // 시작일부터 종료일까지의 모든 날짜에 대해 환율 데이터를 생성하고, 
    // 실제 API 응답에서 누락된 날짜에 대해서는 null 또는 0과 같은 기본값을 설정할 수 있음. 이 부분은 필요에 따라 구현할 수 있음.
    if (history.isEmpty) {
      debugPrint('기간별 환율 데이터가 비어 있음');
      debugPrint('URL: $uri');
      debugPrint('body: ${response.body}');
    }

    return history;
  }
  // 동일한 통화 코드일 경우, 환율은 항상 1이므로, 시작일부터 종료일까지의 모든 날짜에 대해 환율 데이터를 생성.
  List<ExchangeRateHistoryModel> _generateSameCurrencyHistory({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final List<ExchangeRateHistoryModel> history = [];

    DateTime currentDate = startDate;

    while (!currentDate.isAfter(endDate)) {
      history.add(
        ExchangeRateHistoryModel(
          date: currentDate,
          rate: 1,
          baseCurrencyCode: baseCurrencyCode,
          targetCurrencyCode: targetCurrencyCode,
        ),
      );

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return history;
  }
  // 날짜를 'YYYY-MM-DD' 형식으로 변환하는 유틸리티 함수
  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
