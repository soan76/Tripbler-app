import 'package:flutter/material.dart';
import '../../presentation/exchange/display_currency.dart';
import '../../widgets/charts/market_chart_card.dart';
import '../../widgets/charts/market_chart_carousel.dart';
import '../models/crypto_coin.dart';
import '../presentation/crypto_chart_data_source.dart';
import '../services/crypto_api_service.dart';

/// 선택된 코인의 조회 설정만 구성한다. 카드/기간/페이지/그래프 UI는 공유한다.
class CryptoChartCarousel extends StatelessWidget {
  const CryptoChartCarousel({
    super.key,
    required this.coins,
    this.active = true,
    this.api,
  });
  final List<CryptoCoin> coins;
  final bool active;
  final CryptoApiService? api;

  @override
  Widget build(BuildContext context) => MarketChartCarousel(
    itemIds: coins.map((coin) => 'crypto:${coin.symbol}/KRW').toList(),
    active: active,
    cardBuilder: (context, index, period, shouldLoad) {
      final coin = coins[index];
      return MarketChartCard(
        key: ValueKey('crypto:${coin.symbol}/KRW/${period.name}'),
        iconCurrency: DisplayCurrency.fromCrypto(coin),
        baseCode: coin.symbol,
        targetCode: 'KRW',
        title: '암호화폐 차트',
        errorText: '암호화폐 차트를 불러오지 못했습니다.',
        requestKey: 'crypto:${coin.symbol}/KRW',
        createDataSource: () =>
            CryptoChartDataSource(symbol: coin.symbol, api: api),
        period: period,
        shouldLoad: shouldLoad,
        maxXAxisLabels: 6,
      );
    },
  );
}
