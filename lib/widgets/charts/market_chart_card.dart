import 'package:flutter/material.dart';

import '../../models/chart_point.dart';
import '../../models/exchange_rate_history_model.dart';
import '../../presentation/charts/chart_data_source.dart';
import '../../presentation/charts/chart_inversion.dart';
import '../../presentation/charts/chart_load_state.dart';
import '../../presentation/charts/chart_snapshot_store.dart';
import '../../presentation/charts/market_chart_provider.dart';
import '../../presentation/exchange/display_currency.dart';
import 'chart_amount_converter.dart';
import 'currency_swap_pair.dart';
import 'market_chart_body.dart';
import 'market_chart_delete_mode.dart';
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
  // 그래프는 0.5초에 걸쳐 서서히 나타나게 해, 이동이 끝난 뒤에도 새 그래프가
  // 잠시 더 자리 잡는 것처럼 보이게 한다.
  static const _chartFadeDuration = Duration(milliseconds: 500);
  static const _cardRadius = 4.0;

  late final AnimationController _chartFade;
  late final Animation<double> _chartOpacity;
  late final MarketChartProvider _chart;

  // 로딩·실패 화면에서 그래프로 바뀌는 순간을 알기 위해 직전 상태를 기억한다.
  bool _hadHistory = false;

  // 그래프에서 선택한 날짜. 드래그 중에는 카드 전체가 아니라 환산 줄만 다시 그린다.
  // 값은 이 날짜로 기록에서 찾아, 스왑해도 같은 날짜를 가리키고 마커와 어긋나지 않는다.
  final _selectedDate = ValueNotifier<DateTime?>(null);

  final _refreshFocus = FocusNode(debugLabel: 'market-chart-refresh');
  final _retryFocus = FocusNode(debugLabel: 'market-chart-retry');

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
    // 양 끝만 부드럽고 가운데는 거의 일정하게 밝아지는 곡선이라 0.5초 내내
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

  // '다시 시도'는 누르면 로딩 표시로 바뀌어 사라진다. 초점이 전에 쓴 입력칸으로 돌아가지 않게
  // 카드에 남는 새로고침 버튼으로 옮긴다. 입력칸에 초점을 둔 채 터치했으면 그대로 둔다.
  void _retry() {
    if (_retryFocus.hasPrimaryFocus) _refreshFocus.requestFocus();
    _chart.reload();
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

    return MarketChartDeleteMode(
      onRemove: widget.onRemove,
      shouldLoad: widget.shouldLoad,
      borderRadius: _cardRadius,
      builder: (context, controls) =>
          _buildCard(context, _chart.state, controls),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ChartLoadState state,
    ChartDeleteControls controls,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final onPick = widget.onPickCurrency;
    final unavailable = widget.unavailableText != null;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(_cardRadius),
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
            // 제목 줄 버튼(48dp)이 위·오른쪽 여백을 품고 있어 그만큼 줄인다.
            // 아이콘의 위·오른쪽 끝은 카드 안쪽 여백 16에 맞는다.
            padding: const EdgeInsetsDirectional.fromSTEB(
              16,
              16 - MarketChartHeader.contentEndInset,
              16 - MarketChartHeader.contentEndInset,
              0,
            ),
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
              converterBuilder: (status) => ChartAmountConverter(
                rate: widget.swapped
                    ? ChartInversion.rate(state.currentRate)
                    : state.currentRate,
                baseCode: _shownBase.code,
                targetCode: _shownTarget.code,
                historicalRate: state.historicalRate,
                staleRate: !unavailable && state.showsOldData,
                history: _shownHistory(state.history),
                selectedDate: _selectedDate,
                selectionKey: widget.swapped,
                status: status,
                message:
                    widget.unavailableText ??
                    (!widget.shouldLoad && !state.hasLoaded
                        ? '차트를 넘기면 데이터를 불러옵니다'
                        : null),
              ),
              onMore: controls.open,
              moreFocusNode: controls.moreFocusNode,
              refreshFocusNode: _refreshFocus,
              isLoading: !unavailable && state.isLoading,
              showsOldData: !unavailable && state.showsOldData,
              fetchedAt: unavailable ? null : state.fetchedAt,
              onRefresh: unavailable ? null : _chart.reload,
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: MarketChartBody(
                state: state,
                shownHistory: _shownHistory(state.history),
                unavailable: unavailable,
                unavailableHint: widget.unavailableHint,
                shouldLoad: widget.shouldLoad,
                errorText: widget.errorText,
                retryFocusNode: _retryFocus,
                onRetry: _retry,
                chartOpacity: _chartOpacity,
                period: widget.period,
                maxXAxisLabels: widget.maxXAxisLabels,
                interactive: !controls.active,
                onSelectionChanged: _onSelectionChanged,
                selectionKey: widget.swapped,
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _onSelectionChanged(DateTime? date) {
    if (mounted) _selectedDate.value = date;
  }

  @override
  void dispose() {
    _selectedDate.dispose();
    _chart
      ..removeListener(_onChartChanged)
      ..dispose();
    _refreshFocus.dispose();
    _retryFocus.dispose();
    _chartFade.dispose();
    super.dispose();
  }
}
