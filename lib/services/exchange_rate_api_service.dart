import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/exchange_rate_history_model.dart';

// 환율 API와 통신하여 환율 데이터를 가져오는 서비스 클래스
class ExchangeRateApiService {
  static const String _baseUrl = 'https://api.frankfurter.dev/v1';

  // 최신 환율 데이터를 가져오는 메서드
  Future<double> fetchLatestRate({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) async {
    if (baseCurrencyCode == targetCurrencyCode) {
      return 1;
    }

    // API 요청을 위한 URI를 생성
    final uri = Uri.parse(
      '$_baseUrl/latest?base=$baseCurrencyCode&symbols=$targetCurrencyCode',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('최신 환율 데이터를 불러오지 못했습니다.');
    }
    // JSON 응답을 파싱하여 환율 데이터를 추출
    final Map<String, dynamic> jsonBody = jsonDecode(response.body);
    final Map<String, dynamic> rates = jsonBody['rates'];

    final rate = rates[targetCurrencyCode];

    if (rate == null) {
      throw Exception('해당 통화의 환율 데이터가 없습니다.');
    }

    return (rate as num).toDouble();
  }

  // 기간별 환율 데이터를 가져오는 메서드
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

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('기간별 환율 데이터를 불러오지 못했습니다.');
    }

    final Map<String, dynamic> jsonBody = jsonDecode(response.body);
    final Map<String, dynamic> rates = jsonBody['rates'];

    final List<ExchangeRateHistoryModel> history = [];

    // 각 날짜별 환율 데이터를 ExchangeRateHistoryModel 객체로 변환하여 리스트에 추가
    for (final entry in rates.entries) {
      final dateText = entry.key;
      final rateMap = entry.value as Map<String, dynamic>;
      final rate = rateMap[targetCurrencyCode];

      if (rate == null) {
        continue;
      }

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

    return history;
  }

  // 동일한 통화 간의 환율 변동 데이터를 생성하는 메서드
  List<ExchangeRateHistoryModel> _generateSameCurrencyHistory({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // 동일한 통화 간의 환율은 항상 1이므로, 지정된 기간 동안의 환율 변동 데이터를 생성
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

  // 최신 환율 데이터를 가져오는 메서드
  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
