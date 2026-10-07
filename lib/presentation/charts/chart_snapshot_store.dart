import '../../models/chart_point.dart';
import '../../services/market_snapshot_store.dart';
import 'chart_data_source.dart';

class ChartSnapshotStore {
  final _store = MarketSnapshotStore();
  Future<ChartData?> read(String key, {required bool crypto}) async {
    final json = await _store.read(
      'chart.$key',
      Duration(days: crypto ? 1 : 7),
    );
    if (json == null) return null;
    try {
      final points = (json['points'] as List).map((raw) {
        final point = raw as Map<String, dynamic>;
        final rate = (point['rate'] as num).toDouble();
        if (!rate.isFinite || rate <= 0) throw const FormatException();
        return ChartSample(
          date: DateTime.parse(point['date'] as String),
          rate: rate,
          baseCurrencyCode: point['base'] as String,
          targetCurrencyCode: point['target'] as String,
          includesTime: point['includesTime'] == true,
        );
      }).toList();
      if (points.isEmpty) return null;
      final rate = (json['currentRate'] as num?)?.toDouble();
      if (rate != null && (!rate.isFinite || rate <= 0)) return null;
      return ChartData(
        history: points,
        currentRate: rate,
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
        stale: true,
        historicalRate: json['historicalRate'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, ChartData data) async {
    if (data.history.isEmpty) return;
    await _store.write('chart.$key', {
      'fetchedAt': data.fetchedAt.toIso8601String(),
      'currentRate': data.currentRate,
      'historicalRate': data.historicalRate,
      'points': data.history
          .map(
            (p) => {
              'date': p.date.toIso8601String(),
              'rate': p.rate,
              'base': p.baseCurrencyCode,
              'target': p.targetCurrencyCode,
              'includesTime': p.includesTime,
            },
          )
          .toList(),
    });
  }
}
