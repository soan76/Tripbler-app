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
  // date는 기기 시간대에 관계없이 항상 UTC 기준으로 저장하여,
  // 저장 시점과 로드 시점의 시간대가 다르더라도 값이 어긋나지 않도록 한다.
  Map<String, dynamic> toJson() {
    return {
      'date': date.toUtc().toIso8601String(),
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
  // 두 팩토리에 중복 작성되어 있던 부분을 한 곳으로 모아
  // 필드가 늘어나거나 파싱 규칙이 바뀔 때 한쪽만 고치는 실수를 방지한다.
  static (DateTime, double) _parseDateAndRate(Map<String, dynamic> json) {
    // toJson에서 UTC로 저장했으므로, 파싱 시에도 UTC 기준임을 명시적으로 보장한다.
    // (JSON 문자열에 오프셋이 없는 과거 데이터가 남아 있어도 안전하게 UTC로 해석됨)
    final date = DateTime.parse(json['date'] as String).toUtc();
    final rate = (json['rate'] as num).toDouble();

    return (date, rate);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExchangeRateHistoryModel &&
          other.date == date &&
          other.baseCurrencyCode == baseCurrencyCode &&
          other.targetCurrencyCode == targetCurrencyCode);

  @override
  int get hashCode => Object.hash(date, baseCurrencyCode, targetCurrencyCode);

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
// 기존에는 label / shortLabel / xAxisLabelInterval이 각각 별도의 switch문으로
// 흩어져 있어서, 새 기간을 추가할 때 하나라도 빠뜨리면 컴파일 에러 없이
// 조용히 값이 누락될 위험이 있었다. 이제는 새 ChartPeriod를 추가할 때
// 이 맵 한 곳만 채우면 되므로 실수 여지가 줄어든다.
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
  //
  // 월/연 단위 계산 시, 대상 월에 endDate.day에 해당하는 날짜가 없으면
  // (예: 5/31의 1개월 전은 4/31이 아니라 4/30) 자동으로 다음 달로 넘어가
  // 버리는 DateTime 생성자의 오버플로우 문제를 막기 위해
  // 대상 월의 마지막 날짜로 clamp 처리한다.
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
