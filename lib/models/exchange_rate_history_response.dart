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
    final baseCurrency = _parseCurrencyCode(
      json['baseCurrency'],
      fieldName: 'baseCurrency',
    );

    final targetCurrency = _parseCurrencyCode(
      json['targetCurrency'],
      fieldName: 'targetCurrency',
    );

    final startDate = _parseRequiredLocalDate(
      json['startDate'],
      fieldName: 'startDate',
    );

    final endDate = _parseRequiredLocalDate(
      json['endDate'],
      fieldName: 'endDate',
    );

    // 조회 시작일은 종료일보다 뒤일 수 없다.
    if (startDate.isAfter(endDate)) {
      throw const FormatException('startDate는 endDate보다 이후일 수 없습니다.');
    }

    final fetchedAt = _parseRequiredDateTime(
      json['fetchedAt'],
      fieldName: 'fetchedAt',
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

    // 각 환율 기록의 날짜가 조회 기간 안에 있는지 확인한다.
    for (final historyRate in historyRates) {
      if (historyRate.date.isBefore(startDate) ||
          historyRate.date.isAfter(endDate)) {
        throw FormatException(
          'rates에 조회 기간을 벗어난 날짜가 포함되어 있습니다: '
          '${historyRate.date.toIso8601String()}',
        );
      }
    }

    // 동일한 날짜의 환율 데이터가 중복되어 있는지 확인한다.
    final seenDates = <DateTime>{};

    for (final historyRate in historyRates) {
      if (!seenDates.add(historyRate.date)) {
        throw FormatException(
          'rates에 동일한 날짜가 중복되어 있습니다: '
          '${historyRate.date.toIso8601String()}',
        );
      }
    }

    return ExchangeRateHistoryResponse(
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
      startDate: startDate,
      endDate: endDate,
      rates: historyRates,
      fetchedAt: fetchedAt,
    );
  }

  // 통화 코드가 영문 3자리인지 확인하고,
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

  // 백엔드 LocalDate 형식인 yyyy-MM-dd를 검증한다.
  //
  // startDate와 endDate는 시간대가 없는 순수 날짜이므로
  // 시간 정보가 포함된 값은 허용하지 않는다.
  static DateTime _parseRequiredLocalDate(
    dynamic value, {
    required String fieldName,
  }) {
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
}
