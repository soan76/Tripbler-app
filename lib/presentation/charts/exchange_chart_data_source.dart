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
    final latest = await _api.fetchLatestRatesResponse(
      baseCurrency: base,
      targetCurrencies: [target],
    );
    final end = DateTime.now();
    if (_disposed) throw StateError('Chart data source disposed');
    final history = await _api.fetchHistoricalRatesResponse(
      baseCurrencyCode: base,
      targetCurrencyCode: target,
      startDate: period.startDateFrom(end),
      endDate: end,
    );
    return ChartData(
      history: history.rates,
      currentRate: latest.rates[target],
      fetchedAt: history.fetchedAt,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsApi) _api.dispose();
  }
}
