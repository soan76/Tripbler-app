import 'package:flutter/material.dart';

import '../../crypto/presentation/crypto_chart_data_source.dart';
import '../../presentation/charts/chart_data_source.dart';
import '../../presentation/charts/chart_pair.dart';
import '../../presentation/charts/chart_selection_provider.dart';
import '../../presentation/charts/chart_snapshot_store.dart';
import '../../presentation/charts/exchange_chart_data_source.dart';
import '../../presentation/exchange/display_currency.dart';
import 'market_chart_card.dart';
import 'market_chart_carousel.dart';

/// 차트 통화쌍마다 카드를 하나씩 넘겨 보여 준다. 국가 통화 쌍과 코인 쌍이 한
/// 캐러셀에 섞이며, 조회는 쌍의 종류에 맞는 데이터 소스로 나눈다.
class ChartPairCarousel extends StatelessWidget {
  const ChartPairCarousel({
    super.key,
    required this.pairs,
    required this.currencies,
    this.active = true,
    this.onPick,
    this.onAdd,
    this.onRemove,
    this.createDataSource,
    this.snapshotStore,
    this.swappedAfterReplace,
    this.swappedAfterExchange,
  });

  /// 지원하지 않는 코인 카드의 안내. 앞 문장은 현재 시세 자리, 뒤 문장은 차트 자리에 둔다.
  static const unsupportedCoinText = '지원하지 않는 코인입니다.';
  static const unsupportedCoinHint = '통화명을 눌러 다른 코인을 골라 주세요.';

  final List<ChartPair> pairs;

  /// 통화 이름·아이콘을 찾을 목록. 없는 코인은 심볼만으로 표시한다. 코인이 하나라도
  /// 있으면 코인 목록을 받은 것으로 보고, 목록에 없는 코인 카드는 조회하지 않는다.
  final List<DisplayCurrency> currencies;
  final bool active;

  /// [index] 카드의 기준([base]가 true)·대상 통화를 바꾸려 할 때. [base]는 원래 방향
  /// 기준이고, [swapped]는 그때 카드가 뒤집혀 보였는지다.
  final void Function(int index, {required bool base, required bool swapped})?
  onPick;

  /// 차트를 더할 때. null이면 마지막 추가 페이지를 두지 않는다.
  final VoidCallback? onAdd;

  /// [index] 카드를 지울 때. null이면 카드에 지우기 버튼을 두지 않는다.
  final void Function(int index)? onRemove;

  /// 테스트에서 조회를 바꿔 끼울 때 쓴다. 비우면 쌍의 종류에 맞는 실제 소스를 만든다.
  final ChartDataSource Function(ChartPair pair)? createDataSource;
  final ChartSnapshotStore? snapshotStore;

  /// 통화를 바꾼 카드를 보여 줄 방향([MarketChartCarousel.swappedAfterReplace]).
  final bool? Function(String oldId, String newId)? swappedAfterReplace;

  /// 위치를 바꿔 옮겨 온 카드를 보여 줄 방향([MarketChartCarousel.swappedAfterExchange]).
  final ({String id, bool swapped})? Function(String firstId, String secondId)?
  swappedAfterExchange;

  static ChartDataSource _defaultSource(ChartPair pair) => pair.isCrypto
      ? CryptoChartDataSource(symbol: pair.baseCode)
      : ExchangeChartDataSource(base: pair.baseCode, target: pair.targetCode);

  @override
  Widget build(BuildContext context) => MarketChartCarousel(
    itemIds: [for (final pair in pairs) pair.id],
    active: active,
    swappedAfterReplace: swappedAfterReplace,
    swappedAfterExchange: swappedAfterExchange,
    trailing: onAdd == null
        ? null
        : _AddChartPage(
            onAdd: onAdd!,
            remaining: ChartSelectionProvider.maxCards - pairs.length,
          ),
    cardBuilder: (context, index, period, shouldLoad, swapped, onSwap) {
      final pair = pairs[index];
      final onPick = this.onPick;
      final onRemove = this.onRemove;
      final unsupported = pair.isUnsupportedIn(currencies);
      return MarketChartCard(
        key: ValueKey('${pair.id}/${period.name}'),
        baseCurrency: pair.currencyOf(base: true, currencies: currencies),
        targetCurrency: pair.currencyOf(base: false, currencies: currencies),
        swapped: swapped,
        onSwap: onSwap,
        title: pair.isCrypto ? '암호화폐 차트' : '환율 차트',
        errorText: pair.isCrypto
            ? '암호화폐 차트를 불러오지 못했습니다.'
            : '환율 차트를 불러오지 못했습니다.',
        requestKey: pair.id,
        createDataSource: () => (createDataSource ?? _defaultSource).call(pair),
        period: period,
        shouldLoad: shouldLoad,
        unavailableText: unsupported ? unsupportedCoinText : null,
        unavailableHint: unsupported && onPick != null
            ? unsupportedCoinHint
            : null,
        maxXAxisLabels: pair.isCrypto ? 6 : null,
        snapshotStore: snapshotStore,
        onPickCurrency: onPick == null
            ? null
            : ({required bool base}) =>
                  onPick(index, base: base, swapped: swapped),
        onRemove: onRemove == null ? null : () => onRemove(index),
      );
    },
  );
}

/// 캐러셀 끝의 차트 추가 페이지. 빈 칸으로 보이지 않도록 무엇을 할 수 있는지와
/// 남은 개수를 함께 보여 준다.
class _AddChartPage extends StatelessWidget {
  const _AddChartPage({required this.onAdd, required this.remaining});

  final VoidCallback onAdd;

  /// 더 추가할 수 있는 차트 수.
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(22),
      ),
      // 글자를 크게 키워도 넘치지 않게 내용이 길면 스크롤한다.
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.show_chart,
                    size: 32,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '다른 통화쌍도 함께 보기',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '추가한 차트의 통화명을 눌러 원하는 통화나 코인으로 바꿀 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                key: const ValueKey('market-chart-add'),
                onPressed: onAdd,
                style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                icon: const Icon(Icons.add),
                label: const Text('차트 추가'),
              ),
              const SizedBox(height: 12),
              Text(
                '최대 ${ChartSelectionProvider.maxCards}개 · $remaining개 더 추가할 수 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
