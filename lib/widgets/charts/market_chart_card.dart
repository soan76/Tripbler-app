import 'package:flutter/material.dart';

import '../../models/chart_point.dart';
import '../../models/exchange_rate_history_model.dart';
import '../../presentation/charts/chart_data_source.dart';
import '../../presentation/charts/chart_inversion.dart';
import '../../presentation/charts/chart_load_state.dart';
import '../../presentation/charts/chart_snapshot_store.dart';
import '../../presentation/charts/market_chart_provider.dart';
import '../../presentation/exchange/display_currency.dart';
import '../exchange/exchange_rate_line_chart.dart';
import 'currency_swap_pair.dart';
import 'market_chart_header.dart';

/// 하나의 기준 통화/대상 통화 조합에 대한
/// 현재 환율과 기간별 환율 차트를 표시하는 카드.
/// [swapped]이면 조회한 값을 다시 요청하지 않고 반대 방향으로 표시한다.
/// 조회 상태는 카드마다 [MarketChartProvider]가 관리한다.
class MarketChartCard extends StatefulWidget {
  final DisplayCurrency baseCurrency;
  final DisplayCurrency targetCurrency;
  final bool swapped;
  final VoidCallback? onSwap;
  final String title;
  final String errorText;
  final String requestKey;
  final ChartDataSource Function() createDataSource;
  final int? maxXAxisLabels;
  final ChartPeriod period;
  final bool shouldLoad;

  /// 조회할 수 없는 카드(예: 지원하지 않는 코인)의 안내. 있으면 조회하지 않고
  /// 현재 시세 자리에 이 문구를, 차트 자리에 [unavailableHint]를 보여 준다.
  final String? unavailableText;
  final String? unavailableHint;

  /// 차트 스냅샷 저장소. 비우면 기기 저장소([ChartSnapshotStore])를 쓴다.
  /// 카드 State가 처음 만들어질 때의 값만 쓰고, 다시 그려지며 인스턴스만
  /// 바뀌어도 교체하지 않는다. 저장소는 조회 상태와 함께 [MarketChartProvider]가
  /// 들고 있어, 중간에 바꾸면 이미 보여 준 저장값과 이후 쓰기가 서로 다른
  /// 저장소를 가리키게 되기 때문이다. 바꾸려면 key를 바꿔 카드를 새로 만든다.
  final ChartSnapshotStore? snapshotStore;

  /// 기준([base]이 true)·대상 통화명을 눌러 다른 통화로 바꾸려 할 때.
  /// 화면에서 뒤집혀 있어도 원래 방향 기준으로 알려 준다. null이면 통화명을 누를 수 없다.
  final void Function({required bool base})? onPickCurrency;

  /// 카드를 지울 때. null이면 지우기 버튼을 두지 않는다.
  final VoidCallback? onRemove;

  const MarketChartCard({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    this.swapped = false,
    this.onSwap,
    required this.title,
    required this.errorText,
    required this.requestKey,
    required this.createDataSource,
    this.maxXAxisLabels,
    required this.period,
    required this.shouldLoad,
    this.unavailableText,
    this.unavailableHint,
    this.snapshotStore,
    this.onPickCurrency,
    this.onRemove,
  });

  @override
  State<MarketChartCard> createState() => _MarketChartCardState();
}

class _MarketChartCardState extends State<MarketChartCard>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  // 그래프는 1초에 걸쳐 서서히 나타나게 해, 이동이 끝난 뒤에도 새 그래프가
  // 천천히 자리 잡는 것처럼 보이게 한다.
  static const _chartFadeDuration = Duration(seconds: 1);

  late final AnimationController _chartFade;
  late final Animation<double> _chartOpacity;
  late final MarketChartProvider _chart;

  // 로딩·실패 화면에서 그래프로 바뀌는 순간을 알기 위해 직전 상태를 기억한다.
  bool _hadHistory = false;

  @override
  bool get wantKeepAlive => true;

  static bool _canLoad(MarketChartCard card) =>
      card.shouldLoad && card.unavailableText == null;

  bool get _isCrypto =>
      widget.baseCurrency.isCrypto || widget.targetCurrency.isCrypto;

  DisplayCurrency get _shownBase =>
      widget.swapped ? widget.targetCurrency : widget.baseCurrency;

  DisplayCurrency get _shownTarget =>
      widget.swapped ? widget.baseCurrency : widget.targetCurrency;

  // history는 항상 새 목록으로 교체되므로 같은 목록이면 뒤집은 결과를 재사용한다.
  List<ChartPoint>? _invertedSource;
  List<ChartPoint> _invertedHistory = const [];

  List<ChartPoint> _shownHistory(List<ChartPoint> history) {
    if (!widget.swapped) return history;
    if (!identical(_invertedSource, history)) {
      _invertedSource = history;
      _invertedHistory = ChartInversion.history(history);
    }
    return _invertedHistory;
  }

  @override
  void initState() {
    super.initState();
    _chartFade = AnimationController(
      vsync: this,
      duration: _chartFadeDuration,
      value: 1,
    );
    // 양 끝만 부드럽고 가운데는 거의 일정하게 밝아지는 곡선이라 1초 내내
    // 고르게 서서히 나타난다(easeOut처럼 앞에서 거의 다 보이지 않는다).
    _chartOpacity = CurvedAnimation(
      parent: _chartFade,
      curve: Curves.easeInOutSine,
    );
    _chart = MarketChartProvider(
      requestKey: widget.requestKey,
      crypto: _isCrypto,
      dataSource: widget.createDataSource(),
      period: widget.period,
      snapshots: widget.snapshotStore,
    )..addListener(_onChartChanged);

    if (_canLoad(widget)) {
      _chart.loadIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant MarketChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.swapped != widget.swapped) {
      if (animatesSwap(context, wasEnabled: oldWidget.onSwap != null)) {
        // 페이드 중(통화 이동이 끝난 뒤 남은 시간 포함)에 다시 누르면 반쯤
        // 보이던 그래프가 순간 투명해지지 않도록 지금 투명도에서 이어서
        // 나타나게 한다.
        if (_chartFade.isAnimating) {
          _chartFade.forward();
        } else {
          _chartFade.forward(from: 0);
        }
      } else {
        _chartFade.value = 1;
      }
    }

    final requestChanged = oldWidget.requestKey != widget.requestKey;
    final periodChanged = oldWidget.period != widget.period;
    if (requestChanged) {
      _chart.changeRequest(
        requestKey: widget.requestKey,
        crypto: _isCrypto,
        dataSource: widget.createDataSource(),
      );
    }
    if (periodChanged) {
      _chart.changePeriod(widget.period);
    }
    if (_canLoad(widget) &&
        (!_canLoad(oldWidget) || requestChanged || periodChanged)) {
      _chart.loadIfNeeded();
    }
  }

  void _onChartChanged() {
    final hasHistory = _chart.state.history.isNotEmpty;
    // 로딩 표시나 실패 화면에서 그래프로 바뀔 때만 서서히 보여 준다.
    // 저장값을 보여 주는 중에 새 값으로 갱신될 때는 깜박이지 않게 그대로 둔다.
    if (!_hadHistory && hasHistory) {
      if (reduceMotionOf(context)) {
        _chartFade.value = 1;
      } else {
        _chartFade.forward(from: 0);
      }
    }
    _hadHistory = hasHistory;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final colorScheme = Theme.of(context).colorScheme;
    final state = _chart.state;
    final onPick = widget.onPickCurrency;
    final unavailable = widget.unavailableText != null;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: MarketChartHeader(
              title: widget.title,
              pair: CurrencySwapPair(
                baseCurrency: widget.baseCurrency,
                targetCurrency: widget.targetCurrency,
                swapped: widget.swapped,
                onSwap: widget.onSwap,
                // 뒤집혀 있으면 화면 왼쪽이 원래 대상 통화다.
                onPickShownBase: onPick == null
                    ? null
                    : () => onPick(base: !widget.swapped),
                onPickShownTarget: onPick == null
                    ? null
                    : () => onPick(base: widget.swapped),
              ),
              onRemove: widget.onRemove,
              isLoading: !unavailable && state.isLoading,
              showsOldData: !unavailable && state.showsOldData,
              fetchedAt: unavailable ? null : state.fetchedAt,
              onRefresh: unavailable ? null : _chart.reload,
            ),
          ),

          // 헤더 끝 줄의 버튼(48dp)이 위아래 여백을 품고 있어 간격을 줄인다.
          const SizedBox(height: 4),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: MarketChartCurrentRate(
              rate: widget.swapped
                  ? ChartInversion.rate(state.currentRate)
                  : state.currentRate,
              baseCode: _shownBase.code,
              targetCode: _shownTarget.code,
              historicalRate: state.historicalRate,
              message:
                  widget.unavailableText ??
                  (!widget.shouldLoad && !state.hasLoaded
                      ? '차트를 넘기면 데이터를 불러옵니다.'
                      : null),
            ),
          ),

          const SizedBox(height: 18),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: _buildChartArea(state),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildChartArea(ChartLoadState state) {
    final mutedStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    if (widget.unavailableText != null) {
      final hint = widget.unavailableHint;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: mutedStyle,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (!widget.shouldLoad && !state.hasLoaded) {
      return Center(child: Text('이 차트는 아직 불러오지 않았습니다.', style: mutedStyle));
    }

    if (state.isLoading && state.history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.failed && state.history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.errorText, style: mutedStyle),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _chart.reload,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final shownHistory = _shownHistory(state.history);
    if (shownHistory.isEmpty) {
      return Center(child: Text('표시할 차트 데이터가 없습니다.', style: mutedStyle));
    }

    // 방향을 바꾸거나 처음 그려질 때 새 그래프를 서서히 보여 준다.
    // 투명도만 바뀌므로 터치 선택·툴팁·축 계산은 그대로 동작한다.
    return FadeTransition(
      key: const ValueKey('market-chart-fade'),
      opacity: _chartOpacity,
      child: ExchangeRateLineChart(
        history: shownHistory,
        period: widget.period,
        maxXAxisLabels: widget.maxXAxisLabels,
      ),
    );
  }

  @override
  void dispose() {
    _chart
      ..removeListener(_onChartChanged)
      ..dispose();
    _chartFade.dispose();
    super.dispose();
  }
}
