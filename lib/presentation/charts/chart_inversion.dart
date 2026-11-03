import '../../models/chart_point.dart';

/// 조회한 환율을 다시 요청하지 않고 반대 방향(1 / rate)으로 바꾼다.
class ChartInversion {
  // 비정규 수처럼 아주 작은 양수는 뒤집으면 무한대가 되므로 결과도 확인한다.
  static double? rate(double? value) {
    if (value == null || !value.isFinite || value <= 0) return null;
    final inverted = 1 / value;
    return inverted.isFinite ? inverted : null;
  }

  // 뒤집을 수 없는 값(0 이하, 무한대, 뒤집으면 무한대)은 차트에서 제외한다.
  // 원본 기록처럼 수정할 수 없는 목록으로 돌려준다.
  static List<ChartPoint> history(List<ChartPoint> points) =>
      List.unmodifiable([
        for (final point in points)
          if (rate(point.rate) case final inverted?)
            ChartSample(
              date: point.date,
              rate: inverted,
              baseCurrencyCode: point.targetCurrencyCode,
              targetCurrencyCode: point.baseCurrencyCode,
              includesTime: point.includesTime,
            ),
      ]);
}
