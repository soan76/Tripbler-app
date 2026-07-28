import 'dart:convert';

import 'package:http/http.dart' as http;

// 환율 API 서비스를 제공하는 클래스
class ExchangeApiService {
  static const String _baseUrl = 'https://api.frankfurter.app';

  // 최신 환율 데이터를 가져오는 메서드
  Future<Map<String, double>> fetchLatestRates({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final targets = targetCurrencies
        .where((code) => code != baseCurrency)
        .toSet()
        .join(',');

    if (targets.isEmpty) {
      return {};
    }

    // API 요청을 위한 URI 생성
    final uri = Uri.parse('$_baseUrl/latest?from=$baseCurrency&to=$targets');
    // API 호출 및 응답 처리
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('환율 데이터를 불러오지 못했습니다.');
    }
    // JSON 응답을 파싱하여 Map<String, double> 형태로 변환
    final Map<String, dynamic> jsonBody = jsonDecode(response.body);
    final Map<String, dynamic> rates = jsonBody['rates'];

    return rates.map((key, value) {
      return MapEntry(key, (value as num).toDouble());
    });
  }

  // 특정 기간 동안의 환율 변동 데이터를 가져오는 메서드
  Future<Map<String, double>> fetchHistoricalRates({
    required String baseCurrency,
    required String targetCurrency,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // 날짜를 API 요청 형식에 맞게 변환
    final start = _formatDate(startDate);
    final end = _formatDate(endDate);
    // API 요청을 위한 URI 생성
    final uri = Uri.parse(
      '$_baseUrl/$start..$end?from=$baseCurrency&to=$targetCurrency',
    );
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('환율 그래프 데이터를 불러오지 못했습니다.');
    }

    final Map<String, dynamic> jsonBody = jsonDecode(response.body);
    final Map<String, dynamic> rates = jsonBody['rates'];

    final Map<String, double> result = {};

    // 각 날짜별 환율 데이터를 Map<String, double> 형태로 변환
    for (final entry in rates.entries) {
      final date = entry.key;
      final rateMap = entry.value as Map<String, dynamic>;
      final rate = rateMap[targetCurrency];

      if (rate != null) {
        result[date] = (rate as num).toDouble();
      }
    }

    return result;
  }
  // DateTime 객체를 API 요청 형식에 맞게 문자열로 변환하는 메서드
  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
