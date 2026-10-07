import '../../models/exchange_rate_response.dart';
import '../../models/exchange_rate_history_model.dart';
import '../../services/exchange_rate_api_service.dart';
import 'chart_data_source.dart';

class ExchangeChartDataSource implements ChartDataSource {
  ExchangeChartDataSource({
    required this.base,
    required this.target,
    ExchangeRateApiService? api,
  }) : _api = api ?? ExchangeRateApiService(),
       _ownsApi = api == null;
  final String base;
  final String target;
  final ExchangeRateApiService _api;
  final bool _ownsApi;
  bool _disposed = false;

  @override
  Future<ChartData> load(ChartPeriod period) async {
    final latestFuture = _api
        .fetchLatestRatesResponse(
          baseCurrency: base,
          targetCurrencies: [target],
        )
        .then<ExchangeRateResponse?>(
          (value) => value,
          onError: (Object _) => null,
        );
    final end = DateTime.now();
    if (_disposed) throw StateError('Chart data source disposed');
    final history = await _api.fetchHistoricalRatesResponse(
      baseCurrencyCode: base,
      targetCurrencyCode: target,
      startDate: period.startDateFrom(end),
      endDate: end,
    );
    final latest = await latestFuture;
    return ChartData(
      history: history.rates,
      currentRate: latest?.rates[target] ?? history.rates.lastOrNull?.rate,
      historicalRate: latest?.rates[target] == null,
      stale: history.stale || (latest?.stale ?? false),
      fetchedAt: history.fetchedAt,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsApi) _api.dispose();
  }
}
