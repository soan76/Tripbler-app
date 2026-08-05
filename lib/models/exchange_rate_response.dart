class ExchangeRateResponse {
  final String baseCurrency;
  final Map<String, double> rates;
  final DateTime? rateDate;
  final DateTime fetchedAt;

  const ExchangeRateResponse({
    required this.baseCurrency,
    required this.rates,
    required this.rateDate,
    required this.fetchedAt,
  });

  factory ExchangeRateResponse.fromJson(Map<String, dynamic> json) {
    final baseCurrency = json['baseCurrency'];

    if (baseCurrency is! String || baseCurrency.trim().isEmpty) {
      throw const FormatException('baseCurrency 값이 올바르지 않습니다.');
    }

    final ratesValue = json['rates'];

    if (ratesValue is! Map<String, dynamic>) {
      throw const FormatException('rates 값이 올바르지 않습니다.');
    }

    final rates = <String, double>{};

    for (final entry in ratesValue.entries) {
      final value = entry.value;

      if (value is num) {
        rates[entry.key] = value.toDouble();
      }
    }

    final fetchedAt = _parseRequiredDateTime(
      json['fetchedAt'],
      fieldName: 'fetchedAt',
    );

    return ExchangeRateResponse(
      baseCurrency: baseCurrency,
      rates: rates,
      rateDate: _parseDateTime(json['rateDate']),
      fetchedAt: fetchedAt,
    );
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

  static DateTime? _parseDateTime(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }
}
