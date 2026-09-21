// 특정 날짜의 환율 기록을 저장하는 모델 클래스
class ExchangeRateHistoryModel {
  final DateTime date;
  final double rate;
  final String baseCurrencyCode;
  final String targetCurrencyCode;

  const ExchangeRateHistoryModel({
    required this.date,
    required this.rate,
    required this.baseCurrencyCode,
    required this.targetCurrencyCode,
  }) : assert(
         baseCurrencyCode.length == 3,
         'baseCurrencyCode must be 3 letters (ISO 4217), got "$baseCurrencyCode"',
       ),
       assert(
         targetCurrencyCode.length == 3,
         'targetCurrencyCode must be 3 letters (ISO 4217), got "$targetCurrencyCode"',
       );

  // 환율 기록 객체를 JSON 형태의 Map으로 변환.
  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'rate': rate,
      'baseCurrencyCode': baseCurrencyCode,
      'targetCurrencyCode': targetCurrencyCode,
    };
  }

  // JSON 형태의 Map을 환율 기록 객체로 변환
  factory ExchangeRateHistoryModel.fromJson(Map<String, dynamic> json) {
    final (date, rate) = _parseDateAndRate(json);

    return ExchangeRateHistoryModel(
      date: date,
      rate: rate,
      baseCurrencyCode: json['baseCurrencyCode'] as String,
      targetCurrencyCode: json['targetCurrencyCode'] as String,
    );
  }

  factory ExchangeRateHistoryModel.fromBackendJson(
    Map<String, dynamic> json, {
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) {
    final (date, rate) = _parseDateAndRate(json);

    return ExchangeRateHistoryModel(
      date: date,
      rate: rate,
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
    );
  }

  // fromJson과 fromBackendJson이 공통으로 사용하는 date/rate 파싱 로직.
  static (DateTime, double) _parseDateAndRate(Map<String, dynamic> json) {
    final date = _parseRequiredLocalDate(json['date'], fieldName: 'date');

    final rate = _parseRequiredRate(json['rate'], fieldName: 'rate');

    return (date, rate);
  }

  // 백엔드의 LocalDate 형식인 yyyy-MM-dd를 검증하고 파싱한다.
  //
  // 단순히 DateTime.parse()만 사용하면 잘못된 날짜가 자동 보정될 수 있으므로
  // 먼저 형식을 확인한 뒤 실제 달력 날짜인지 다시 검증한다.
  static DateTime _parseRequiredLocalDate(
    dynamic value, {
    required String fieldName,
  }) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$fieldName 값이 올바르지 않습니다.');
    }

    final normalizedValue = value.trim();

    final datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

    if (!datePattern.hasMatch(normalizedValue)) {
      throw FormatException('$fieldName 날짜 형식이 올바르지 않습니다.');
    }

    final parsedDate = DateTime.tryParse(normalizedValue);

    if (parsedDate == null) {
      throw FormatException('$fieldName 날짜 형식이 올바르지 않습니다.');
    }

    // DateTime이 비정상 날짜를 다른 날짜로 자동 보정했는지 확인한다.
    final normalizedParsedDate =
        '${parsedDate.year.toString().padLeft(4, '0')}-'
        '${parsedDate.month.toString().padLeft(2, '0')}-'
        '${parsedDate.day.toString().padLeft(2, '0')}';

    if (normalizedParsedDate != normalizedValue) {
      throw FormatException('$fieldName 날짜가 실제 달력에 존재하지 않습니다.');
    }

    return parsedDate;
  }

  // 환율 값이 숫자이며,
  // 0보다 큰 유한한 값인지 검증한다.
  static double _parseRequiredRate(dynamic value, {required String fieldName}) {
    if (value is! num) {
      throw FormatException('$fieldName 값이 숫자가 아닙니다.');
    }

    final rate = value.toDouble();

    if (!rate.isFinite || rate <= 0) {
      throw FormatException('$fieldName 값은 0보다 큰 유한한 숫자여야 합니다.');
    }

    return rate;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExchangeRateHistoryModel &&
          other.date == date &&
          other.rate == rate &&
          other.baseCurrencyCode == baseCurrencyCode &&
          other.targetCurrencyCode == targetCurrencyCode);

  @override
  int get hashCode => Object.hash(date, rate, baseCurrencyCode, targetCurrencyCode);

  @override
  String toString() =>
      'ExchangeRateHistoryModel(date: $date, rate: $rate, '
      '$baseCurrencyCode->$targetCurrencyCode)';
}

// 환율 차트에서 선택할 수 있는 조회 기간 - 수정 예정
enum ChartPeriod {
  sevenDays,
  oneMonth,
  threeMonths,
  sixMonths,
  oneYear,
  twoYears,
  fiveYears,
}

// ChartPeriod별 표시 라벨과 X축 간격을 한 곳에 모아둔 메타데이터.
class _ChartPeriodMeta {
  final String label;
  final String shortLabel;
  final int xAxisLabelInterval;
  final int? months; // null이면 개월 수 대신 일(day) 단위(startDateFrom에서 처리)

  const _ChartPeriodMeta({
    required this.label,
    required this.shortLabel,
    required this.xAxisLabelInterval,
    this.months,
  });
}

const Map<ChartPeriod, _ChartPeriodMeta> _chartPeriodMeta = {
  ChartPeriod.sevenDays: _ChartPeriodMeta(
    label: '7일',
    shortLabel: '7d',
    xAxisLabelInterval: 1,
  ),
  ChartPeriod.oneMonth: _ChartPeriodMeta(
    label: '1개월',
    shortLabel: '1m',
    xAxisLabelInterval: 5,
    months: 1,
  ),
  ChartPeriod.threeMonths: _ChartPeriodMeta(
    label: '3개월',
    shortLabel: '3m',
    xAxisLabelInterval: 15,
    months: 3,
  ),
  ChartPeriod.sixMonths: _ChartPeriodMeta(
    label: '6개월',
    shortLabel: '6m',
    xAxisLabelInterval: 30,
    months: 6,
  ),
  ChartPeriod.oneYear: _ChartPeriodMeta(
    label: '1년',
    shortLabel: '1y',
    xAxisLabelInterval: 60,
    months: 12,
  ),
  ChartPeriod.twoYears: _ChartPeriodMeta(
    label: '2년',
    shortLabel: '2y',
    xAxisLabelInterval: 120,
    months: 24,
  ),
  ChartPeriod.fiveYears: _ChartPeriodMeta(
    label: '5년',
    shortLabel: '5y',
    xAxisLabelInterval: 365,
    months: 60,
  ),
};

extension ChartPeriodExtension on ChartPeriod {
  // 사용자 화면에 표시할 한글 기간 이름 - 수정 예정
  String get label => _chartPeriodMeta[this]!.label;

  // 사용자 화면에 표시할 짧은 기간 이름 - 수정 예정
  String get shortLabel => _chartPeriodMeta[this]!.shortLabel;

  // 차트 X축 날짜 라벨을 표시할 간격
  int get xAxisLabelInterval => _chartPeriodMeta[this]!.xAxisLabelInterval;

  // 특정 기간의 시작 날짜를 계산하는 메서드 - 수정 예정
  DateTime startDateFrom(DateTime endDate) {
    if (this == ChartPeriod.sevenDays) {
      return endDate.subtract(const Duration(days: 7));
    }

    final months = _chartPeriodMeta[this]!.months!;
    return _subtractMonths(endDate, months);
  }
}

// date에서 months만큼 이전 날짜를 계산.
// 대상 월에 date.day에 해당하는 날짜가 없으면(예: 1월 31일의 1개월 전)
// 대상 월의 마지막 날짜로 clamp하여 DateTime 생성자의 자동 롤오버를 방지한다.
DateTime _subtractMonths(DateTime date, int months) {
  final totalMonths = date.year * 12 + (date.month - 1) - months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;

  // 다음 달 0일 = 이번 달의 마지막 날짜
  final lastDayOfTargetMonth = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : date.day;

  return DateTime(year, month, day);
}
