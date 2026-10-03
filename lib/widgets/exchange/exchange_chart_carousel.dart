import 'package:flutter/material.dart';
import '../../models/currency_model.dart';
import '../charts/market_chart_carousel.dart';
import 'exchange_chart_card.dart';

class ExchangeChartCarousel extends StatelessWidget {
  const ExchangeChartCarousel({
    super.key,
    required this.baseCurrency,
    required this.targetCurrencies,
    this.active = true,
  });
  final CurrencyModel baseCurrency;
  final List<CurrencyModel> targetCurrencies;
  final bool active;

  @override
  Widget build(BuildContext context) => MarketChartCarousel(
    itemIds: targetCurrencies
        .map((currency) => '${baseCurrency.code}/${currency.code}')
        .toList(),
    active: active,
    cardBuilder: (context, index, period, shouldLoad) => ExchangeChartCard(
      key: ValueKey(
        '${baseCurrency.code}/${targetCurrencies[index].code}/${period.name}',
      ),
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrencies[index],
      period: period,
      shouldLoad: shouldLoad,
    ),
  );
}
