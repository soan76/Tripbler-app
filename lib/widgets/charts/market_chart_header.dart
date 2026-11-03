import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../exchange/exchange_chart_axis_helper.dart';

/// 차트 카드 위쪽의 제목, 통화쌍, 갱신 상태, 새로고침·더보기 버튼.
/// 통화쌍은 카드 폭을 모두 쓰고, 버튼은 갱신 시각 줄 끝에 둔다.
class MarketChartHeader extends StatelessWidget {
  const MarketChartHeader({
    super.key,
    required this.title,
    required this.pair,
    required this.isLoading,
    required this.showsOldData,
    required this.fetchedAt,
    required this.onRefresh,
    this.onRemove,
  });

  final String title;
  final Widget pair;
  final bool isLoading;

  /// 저장값이나 마지막 성공값을 보여 주는 중인지.
  final bool showsOldData;
  final DateTime? fetchedAt;

  /// 새로고침. null이면(조회할 수 없는 카드) 버튼을 끈다.
  final VoidCallback? onRefresh;

  /// 카드를 지울 때. null이면 더보기 메뉴(차트 삭제)를 두지 않는다.
  final VoidCallback? onRemove;

  static final _fetchedAtFormat = DateFormat('yyyy.MM.dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = colorScheme.onSurfaceVariant;
    final fetchedAt = this.fetchedAt;
    final onRemove = this.onRemove;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: mutedColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        pair,
        // 새로고침은 그 결과가 바뀌는 갱신 시각 옆에 둔다. 화면 낭독기도
        // 제목 → 통화쌍 → 갱신 상태 → 버튼 순서로 읽는다.
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showsOldData)
                    Text(
                      isLoading ? '저장된 데이터 · 갱신 중' : '마지막 성공 데이터 · 갱신 지연',
                      style: TextStyle(fontSize: 11, color: mutedColor),
                    ),
                  if (fetchedAt != null)
                    Text(
                      '업데이트: ${_fetchedAtFormat.format(fetchedAt.toLocal())}',
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: isLoading ? null : '새로고침',
              onPressed: isLoading ? null : onRefresh,
              color: mutedColor,
              icon: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
            // 삭제는 자주 쓰지 않고 되돌릴 수 없어, 실수로 누르지 않도록
            // 더보기 메뉴 안에 이름과 함께 둔다.
            if (onRemove != null)
              PopupMenuButton<void>(
                key: const ValueKey('market-chart-menu'),
                tooltip: '차트 메뉴',
                iconColor: mutedColor,
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  PopupMenuItem<void>(
                    key: const ValueKey('market-chart-remove'),
                    onTap: onRemove,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Text(
                          '차트 삭제',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// "1 기준 코드 = 환율 대상 코드" 형태의 현재 환율.
/// [message]가 있으면 환율 대신 안내 문구를 보여 준다.
class MarketChartCurrentRate extends StatelessWidget {
  const MarketChartCurrentRate({
    super.key,
    required this.rate,
    required this.baseCode,
    required this.targetCode,
    required this.historicalRate,
    this.message,
  });

  final double? rate;
  final String baseCode;
  final String targetCode;

  /// 현재 시세를 받지 못해 기록의 마지막 값을 보여 주는지.
  final bool historicalRate;
  final String? message;

  static final _rateFormatter = NumberFormat('#,##0.######');

  // 1 미만 값은 반전된 코인 환율처럼 아주 작을 수 있어 유효숫자 기준으로 표시한다.
  static String _formatRate(double value) {
    if (value.abs() < 1) return ExchangeChartAxisHelper.formatRate(value);

    return _rateFormatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rate = this.rate;
    if (message != null || rate == null) {
      return Text(
        message ?? '현재 환율 정보 없음',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            '${historicalRate ? '최근 기록 · ' : ''}1 $baseCode',
            style: TextStyle(
              fontSize: 15,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Flexible(
          flex: 2,
          child: Text(
            '${_formatRate(rate)} $targetCode',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
