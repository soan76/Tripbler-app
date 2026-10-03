/// 조회 API와 무관하게 공통 차트가 읽는 데이터 계약.
abstract class ChartPoint {
  const ChartPoint();
  DateTime get date;
  double get rate;
  String get baseCurrencyCode;
  String get targetCurrencyCode;
  bool get includesTime => false;
}

class ChartSample extends ChartPoint {
  const ChartSample({
    required this.date,
    required this.rate,
    required this.baseCurrencyCode,
    required this.targetCurrencyCode,
    this.includesTime = false,
  });
  @override
  final DateTime date;
  @override
  final double rate;
  @override
  final String baseCurrencyCode;
  @override
  final String targetCurrencyCode;
  @override
  final bool includesTime;

  @override
  bool operator ==(Object other) =>
      other is ChartSample &&
      date == other.date &&
      rate == other.rate &&
      baseCurrencyCode == other.baseCurrencyCode &&
      targetCurrencyCode == other.targetCurrencyCode &&
      includesTime == other.includesTime;
  @override
  int get hashCode => Object.hash(
    date,
    rate,
    baseCurrencyCode,
    targetCurrencyCode,
    includesTime,
  );
}
