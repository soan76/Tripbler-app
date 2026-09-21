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
    final baseCurrency = _parseCurrencyCode(
      json['baseCurrency'],
      fieldName: 'baseCurrency',
    );
    
    final ratesValue = json['rates'];

    if (ratesValue is! Map<String, dynamic>) {
      throw const FormatException('rates 값이 올바르지 않습니다.');
    }

    final rates = <String, double>{};

    for (final entry in ratesValue.entries) {
      final currencyCode = _parseCurrencyCode(
        entry.key,
        fieldName: 'rates 통화 코드',
      );

      final rate = _parseRate(entry.value, currencyCode: currencyCode);

      // 정규화 과정에서 동일한 통화 코드가 중복되는 것도 허용하지 않는다.
      if (rates.containsKey(currencyCode)) {
        throw FormatException('rates에 $currencyCode 통화가 중복되어 있습니다.');
      }

      rates[currencyCode] = rate;
    }

    final fetchedAt = _parseRequiredDateTime(
      json['fetchedAt'],
      fieldName: 'fetchedAt',
    );

    return ExchangeRateResponse(
      baseCurrency: baseCurrency,
      rates: rates,
      rateDate: _parseOptionalLocalDate(json['rateDate'], fieldName: 'rateDate'),
      fetchedAt: fetchedAt,
    );
  }

  // 통화 코드가 영문 3자리인지 확인하고
  // 앞뒤 공백 제거 및 대문자 정규화를 수행한다.
  static String _parseCurrencyCode(dynamic value, {required String fieldName}) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$fieldName 값이 올바르지 않습니다.');
    }

    final normalizedCode = value.trim().toUpperCase();

    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCode)) {
      throw FormatException('$fieldName 값은 영문 3자리 통화 코드여야 합니다.');
    }

    return normalizedCode;
  }

  static DateTime _parseRequiredDateTime(
    dynamic value, {
    required String fieldName,
  }) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$fieldName 값이 올바르지 않습니다.');
    }

    final parsedDate = DateTime.tryParse(value.trim());

    if (parsedDate == null) {
      throw FormatException('$fieldName 날짜 형식이 올바르지 않습니다.');
    }

    return parsedDate;
  }

  // 환율 값이 숫자이며,
  // 0보다 큰 유한한 값인지 검증한다.
  static double _parseRate(dynamic value, {required String currencyCode}) {
    if (value is! num) {
      throw FormatException('$currencyCode 환율 값이 숫자가 아닙니다.');
    }

    final rate = value.toDouble();

    if (!rate.isFinite || rate <= 0) {
      throw FormatException('$currencyCode 환율 값은 0보다 큰 유한한 숫자여야 합니다.');
    }

    return rate;
  }

  // 선택값인 LocalDate를 파싱한다.
  //
  // null은 허용하지만,
  // 값이 존재하면 반드시 yyyy-MM-dd 형식의 실제 날짜여야 한다.
  static DateTime? _parseOptionalLocalDate(
    dynamic value, {
    required String fieldName,
  }) {
    if (value == null) {
      return null;
    }

    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$fieldName 값이 올바르지 않습니다.');
    }

    final normalizedValue = value.trim();

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(normalizedValue)) {
      throw FormatException('$fieldName 날짜 형식이 올바르지 않습니다.');
    }

    final parsedDate = DateTime.tryParse(normalizedValue);

    if (parsedDate == null) {
      throw FormatException('$fieldName 날짜 형식이 올바르지 않습니다.');
    }

    final normalizedParsedDate =
        '${parsedDate.year.toString().padLeft(4, '0')}-'
        '${parsedDate.month.toString().padLeft(2, '0')}-'
        '${parsedDate.day.toString().padLeft(2, '0')}';

    if (normalizedParsedDate != normalizedValue) {
      throw FormatException('$fieldName 날짜가 실제 달력에 존재하지 않습니다.');
    }

    return parsedDate;
  }
}
