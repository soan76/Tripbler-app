import 'package:flutter/material.dart';
import '../../models/currency_model.dart';
import '../../models/exchange_rate_history_model.dart';
import '../../presentation/exchange/display_currency.dart';
import '../../presentation/charts/exchange_chart_data_source.dart';
import '../charts/market_chart_card.dart';

/// 기존 환율 카드의 진입점. 조회 설정만 제공하고 렌더링은 공통 카드를 사용한다.
class ExchangeChartCard extends StatelessWidget {
  const ExchangeChartCard({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.period,
    required this.shouldLoad,
  });
  final CurrencyModel baseCurrency;
  final CurrencyModel targetCurrency;
  final ChartPeriod period;
  final bool shouldLoad;

  @override
  Widget build(BuildContext context) => MarketChartCard(
    iconCurrency: DisplayCurrency.fromFiat(targetCurrency),
    baseCode: baseCurrency.code,
    targetCode: targetCurrency.code,
    title: '환율 차트',
    errorText: '환율 차트를 불러오지 못했습니다.',
    requestKey: 'fiat:${baseCurrency.code}/${targetCurrency.code}',
    createDataSource: () => ExchangeChartDataSource(
      base: baseCurrency.code,
      target: targetCurrency.code,
    ),
    period: period,
    shouldLoad: shouldLoad,
  );
}
