import 'dart:convert';

import 'package:http/http.dart' as http;

class ExchangeApiService {
  static const String _baseUrl = 'https://api.frankfurter.app';

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

    final uri = Uri.parse('$_baseUrl/latest?from=$baseCurrency&to=$targets');

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('환율 데이터를 불러오지 못했습니다.');
    }

    final Map<String, dynamic> jsonBody = jsonDecode(response.body);
    final Map<String, dynamic> rates = jsonBody['rates'];

    return rates.map((key, value) {
      return MapEntry(key, (value as num).toDouble());
    });
  }

  Future<Map<String, double>> fetchHistoricalRates({
    required String baseCurrency,
    required String targetCurrency,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = _formatDate(startDate);
    final end = _formatDate(endDate);

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

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
