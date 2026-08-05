import 'exchange_rate_history_model.dart';

class ExchangeRateHistoryResponse {
  final String baseCurrency;
  final String targetCurrency;
  final DateTime startDate;
  final DateTime endDate;
  final List<ExchangeRateHistoryModel> rates;
  final DateTime fetchedAt;

  const ExchangeRateHistoryResponse({
    required this.baseCurrency,
    required this.targetCurrency,
    required this.startDate,
    required this.endDate,
    required this.rates,
    required this.fetchedAt,
  });

  factory ExchangeRateHistoryResponse.fromJson(Map<String, dynamic> json) {
    final baseCurrency = _parseRequiredString(
      json['baseCurrency'],
      fieldName: 'baseCurrency',
    );

    final targetCurrency = _parseRequiredString(
      json['targetCurrency'],
      fieldName: 'targetCurrency',
    );

    final ratesValue = json['rates'];

    if (ratesValue is! List) {
      throw const FormatException('rates 값이 올바르지 않습니다.');
    }

    final historyRates = ratesValue.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('rates 항목 형식이 올바르지 않습니다.');
      }

      return ExchangeRateHistoryModel.fromBackendJson(
        item,
        baseCurrencyCode: baseCurrency,
        targetCurrencyCode: targetCurrency,
      );
    }).toList()..sort((first, second) => first.date.compareTo(second.date));

    return ExchangeRateHistoryResponse(
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
      startDate: _parseRequiredDateTime(
        json['startDate'],
        fieldName: 'startDate',
      ),
      endDate: _parseRequiredDateTime(json['endDate'], fieldName: 'endDate'),
      rates: historyRates,
      fetchedAt: _parseRequiredDateTime(
        json['fetchedAt'],
        fieldName: 'fetchedAt',
      ),
    );
  }

  static String _parseRequiredString(
    dynamic value, {
    required String fieldName,
  }) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$fieldName 값이 올바르지 않습니다.');
    }

    return value.trim().toUpperCase();
  }

  static DateTime _parseRequiredDateTime(
    dynamic value, {
    required String fieldName,
  }) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$fieldName 값이 올바르지 않습니다.');
    }

    final parsedDate = DateTime.tryParse(value);

    if (parsedDate == null) {
      throw FormatException('$fieldName 날짜 형식이 올바르지 않습니다.');
    }

    return parsedDate;
  }
}
