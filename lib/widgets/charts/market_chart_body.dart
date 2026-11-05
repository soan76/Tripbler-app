import 'package:flutter/material.dart';

import '../../models/chart_point.dart';
import '../../models/exchange_rate_history_model.dart';
import '../../presentation/charts/chart_load_state.dart';
import '../exchange/exchange_rate_line_chart.dart';
import 'chart_swap_motion.dart';

/// 차트 카드의 본문. 조회 상태에 따라 안내·로딩·실패·빈 결과·그래프 중 하나를 보여 준다.
/// 표시만 맡고, 조회와 다시 시도, 페이드 진행은 카드가 맡는다.
class MarketChartBody extends StatelessWidget {
  const MarketChartBody({
    super.key,
    required this.state,
    required this.shownHistory,
    required this.unavailable,
    required this.unavailableHint,
    required this.shouldLoad,
    required this.errorText,
    required this.retryFocusNode,
    required this.onRetry,
    required this.chartOpacity,
    required this.period,
    required this.maxXAxisLabels,
    required this.interactive,
  });

  final ChartLoadState state;

  /// 화면 방향에 맞춘 기록. 로딩·실패 판단은 [state]의 원본 기록으로 한다.
  final List<ChartPoint> shownHistory;

  /// 조회할 수 없는 카드인지.
  final bool unavailable;
  final String? unavailableHint;
  final bool shouldLoad;
  final String errorText;
  final FocusNode retryFocusNode;
  final VoidCallback onRetry;
  final Animation<double> chartOpacity;
  final ChartPeriod period;
  final int? maxXAxisLabels;

  /// 그래프를 터치로 조작할 수 있는지.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final mutedStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    if (unavailable) {
      final hint = unavailableHint;
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

    if (!shouldLoad && !state.hasLoaded) {
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
            Text(errorText, style: mutedStyle),
            const SizedBox(height: 10),
            OutlinedButton(
              focusNode: retryFocusNode,
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (shownHistory.isEmpty) {
      return Center(child: Text('표시할 차트 데이터가 없습니다.', style: mutedStyle));
    }

    // 방향을 바꾸거나 처음 그려질 때 새 그래프를 서서히 보여 준다.
    // 투명도만 바뀌므로 터치 선택·툴팁·축 계산은 그대로 동작한다.
    return FadeTransition(
      key: const ValueKey('market-chart-fade'),
      opacity: chartOpacity,
      child: ExchangeRateLineChart(
        history: shownHistory,
        period: period,
        maxXAxisLabels: maxXAxisLabels,
        animateDataChange: !InstantSwapScope.of(context),
        interactive: interactive,
      ),
    );
  }
}
