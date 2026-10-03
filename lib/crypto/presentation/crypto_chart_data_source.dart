import '../../models/chart_point.dart';
import '../../models/exchange_rate_history_model.dart';
import '../../presentation/charts/chart_data_source.dart';
import '../services/crypto_api_service.dart';

/// Crypto 응답을 공통 렌더러의 데이터로 변환한다. 법정 통화 API는 사용하지 않는다.
class CryptoChartDataSource implements ChartDataSource {
  CryptoChartDataSource({required this.symbol, CryptoApiService? api})
    : _api = api ?? CryptoApiService(),
      _ownsApi = api == null;
  final String symbol;
  final CryptoApiService _api;
  final bool _ownsApi;
  bool _disposed = false;

  @override
  Future<ChartData> load(ChartPeriod period) async {
    final history = await _api.fetchHistory(
      symbol: symbol,
      period: period.shortLabel.toUpperCase(),
    );
    if (_disposed) throw StateError('Chart data source disposed');
    final current = await _api.fetchPrice(symbol);
    return ChartData(
      history: history.prices
          .map(
            (point) => ChartSample(
              date: point.timestamp.toLocal(),
              rate: point.price,
              baseCurrencyCode: symbol,
              targetCurrencyCode: 'KRW',
              includesTime: true,
            ),
          )
          .toList(),
      currentRate: current.price,
      fetchedAt: history.fetchedAt,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsApi) _api.dispose();
  }
}
