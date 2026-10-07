import '../models/crypto_price.dart';
import '../models/crypto_history.dart';
import '../../core/network/api_exception.dart';
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
    if (!CryptoHistory.supportedPeriods.containsKey(
      period.shortLabel.toUpperCase(),
    )) {
      throw const ApiException(message: '암호화폐 차트를 불러오지 못했습니다.');
    }
    final currentFuture = _api
        .fetchPrice(symbol)
        .then<CryptoPrice?>((value) => value, onError: (Object _) => null);
    final history = await _api.fetchHistory(
      symbol: symbol,
      period: period.shortLabel.toUpperCase(),
    );
    if (_disposed) throw StateError('Chart data source disposed');
    final current = await currentFuture;
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
      currentRate: current?.price ?? history.prices.lastOrNull?.price,
      historicalRate: current == null,
      stale: history.stale || (current?.stale ?? false),
      fetchedAt: history.fetchedAt,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsApi) _api.dispose();
  }
}
