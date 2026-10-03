import '../../models/chart_point.dart';
import '../../models/exchange_rate_history_model.dart';

class ChartData {
  ChartData({
    required List<ChartPoint> history,
    required this.currentRate,
    required this.fetchedAt,
  }) : history = List.unmodifiable(history);
  final List<ChartPoint> history;
  final double? currentRate;
  final DateTime fetchedAt;
}

/// 카드의 요청 수명은 공통 관리하고, 실제 조회는 도메인별 구현에 위임한다.
abstract interface class ChartDataSource {
  Future<ChartData> load(ChartPeriod period);
  void dispose();
}
