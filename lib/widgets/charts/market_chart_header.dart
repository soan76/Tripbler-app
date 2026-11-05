import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 차트 카드 위쪽의 제목, 통화쌍, 금액 환산, 갱신 상태, 새로고침·더보기 버튼.
/// 버튼은 제목 줄 오른쪽 끝에 두고, 통화쌍은 그 아래에서 카드 폭을 모두 쓴다.
class MarketChartHeader extends StatelessWidget {
  const MarketChartHeader({
    super.key,
    required this.title,
    required this.pair,
    this.converter,
    required this.isLoading,
    required this.showsOldData,
    required this.fetchedAt,
    required this.onRefresh,
    this.onMore,
    this.moreFocusNode,
    this.refreshFocusNode,
  });

  final String title;
  final Widget pair;

  /// 통화쌍과 갱신 상태 사이의 금액 환산 줄.
  final Widget? converter;
  final bool isLoading;

  /// 저장값이나 마지막 성공값을 보여 주는 중인지.
  final bool showsOldData;
  final DateTime? fetchedAt;

  /// 새로고침. null이면(조회할 수 없는 카드) 버튼을 끈다.
  /// 조회 중에는 끄지 않고 눌러도 무시한다. 끄면 버튼에 있던 초점이 전에 쓴 입력칸으로
  /// 돌아가 키보드가 뜨고 화면이 올라간다.
  final VoidCallback? onRefresh;

  /// 더보기 버튼을 눌렀을 때. null이면 더보기 버튼을 두지 않는다.
  final VoidCallback? onMore;

  /// 더보기 버튼의 포커스. 삭제 모드를 닫으면 이 버튼으로 초점을 돌려준다.
  final FocusNode? moreFocusNode;

  /// 새로고침 버튼의 포커스.
  final FocusNode? refreshFocusNode;

  /// 48dp 버튼 칸에서 24dp 아이콘 바깥의 여백. 버튼 칸은 카드 안쪽 여백까지 나가고,
  /// 제목 줄 아래 내용은 이만큼 들여 아이콘의 오른쪽 끝과 맞춘다. 버튼을 옮기는 변환으로
  /// 맞추면 부모 밖으로 나간 터치 영역이 눌리지 않는다.
  static const contentEndInset = 12.0;

  // 조회 중 버튼을 눌러도 눌린 표시와 포인터 모양이 바뀌지 않게 한다(꺼진 버튼과 같다).
  // 초점 표시는 남겨 키보드 사용자가 자기 위치를 볼 수 있게 한다. 초점이 있는 채 누르거나
  // 마우스를 올려도 그 표시가 생기지 않게, 초점만 있을 때만 기본색을 쓴다.
  static final _busyRefreshStyle = ButtonStyle(
    overlayColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.focused) &&
              !states.contains(WidgetState.pressed) &&
              !states.contains(WidgetState.hovered)
          ? null
          : Colors.transparent,
    ),
    splashFactory: NoSplash.splashFactory,
    mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
    enableFeedback: false,
  );

  static void _ignorePress() {}

  static final _fetchedAtFormat = DateFormat('yyyy.MM.dd HH:mm');

  /// 갱신 상태 안내 중 가장 긴 문구. 안내 줄의 자리도 이 문구로 잡는다.
  static const _staleFailedText = '마지막 성공 데이터 · 갱신 지연';

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final fetchedAt = this.fetchedAt;
    // 초점을 지키려고 켜 둔 채 조회 중인 상태. 끈 버튼은 원래 꺼진 것으로 읽힌다.
    final busy = isLoading && onRefresh != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 포커스는 제목 줄 버튼 → 통화쌍 순서로 지나간다. 화면 낭독기는 다르다. 캐러셀에서
        // 제목과 갱신 상태 같은 글자는 한 노드로 합쳐져 버튼보다 먼저 읽힌다.
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: mutedColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 화면 낭독기에는 조회 중에 라벨 없이 꺼진 버튼으로 읽힌다.
            Semantics(
              container: busy,
              button: busy ? true : null,
              enabled: busy ? false : null,
              excludeSemantics: busy,
              // 조회 중에는 눌러도 툴팁이 뜨지 않게 하되 트리는 그대로 둔다. tooltip을 비우거나
              // TooltipVisibility로 끄면 Tooltip 층이 바뀌어 안쪽 InkWell이 새로 만들어지고,
              // 초점 표시와 눌림 해제 타이머를 잃는다. 초점을 지키는 것은 onPressed를 두는 쪽이다.
              child: TooltipTheme(
                data: busy
                    ? TooltipTheme.of(
                        context,
                      ).copyWith(triggerMode: TooltipTriggerMode.manual)
                    : TooltipTheme.of(context),
                child: IconButton(
                  tooltip: '새로고침',
                  focusNode: refreshFocusNode,
                  onPressed: busy ? _ignorePress : onRefresh,
                  style: busy ? _busyRefreshStyle : null,
                  color: mutedColor,
                  icon: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ),
            ),
            // 삭제는 자주 쓰지 않고 되돌릴 수 없어, 실수로 누르지 않도록
            // 더보기를 눌러 삭제 모드를 연 뒤에만 지울 수 있다.
            if (onMore != null)
              IconButton(
                key: const ValueKey('market-chart-menu'),
                tooltip: '차트 메뉴',
                focusNode: moreFocusNode,
                onPressed: onMore,
                color: mutedColor,
                icon: const Icon(Icons.more_vert),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: contentEndInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pair,
              ?converter,
              const SizedBox(height: 8),
              // 두 줄 자리를 늘 두어 상태가 바뀌어도 아래의 차트가 움직이지 않는다.
              // 시각을 위에 두어, 안내 문구가 없는 평상시에 통화쌍과 시각 사이가 비지 않게 한다.
              _StatusLine(
                text: fetchedAt == null
                    ? null
                    : '업데이트: ${_fetchedAtFormat.format(fetchedAt.toLocal())}',
                reserved: '업데이트: 0000.00.00 00:00',
                style: TextStyle(fontSize: 12, color: mutedColor),
              ),
              _StatusLine(
                text: !showsOldData
                    ? null
                    : isLoading
                    ? '저장된 데이터 · 갱신 중'
                    : _staleFailedText,
                reserved: _staleFailedText,
                style: TextStyle(fontSize: 11, color: mutedColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// [text]가 없어도 [reserved]를 그렸을 때만큼의 자리를 차지하는 상태 줄.
/// 고정 높이와 달리 글자 배율과 줄바꿈을 따라 자리가 커져 문구가 잘리지 않는다.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    required this.reserved,
    required this.style,
  });

  final String? text;

  /// 이 줄에 올 수 있는 가장 긴 문구.
  final String reserved;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    // 보이는 Text와 같은 굵기로 재야 굵은 글씨 설정에서도 같은 곳에서 줄바꿈된다.
    final reservedStyle = DefaultTextStyle.of(context).style.merge(style);

    return Stack(
      children: [
        // 투명도 0은 그리지 않고 화면 낭독기에서도 빠진다. 자리만 잡는 글자이므로
        // 보이는 문구로 찾히지 않게 Text 대신 RichText를 쓴다.
        Opacity(
          opacity: 0,
          child: RichText(
            textScaler: MediaQuery.textScalerOf(context),
            text: TextSpan(
              text: reserved,
              style: MediaQuery.boldTextOf(context)
                  ? reservedStyle.merge(
                      const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : reservedStyle,
            ),
          ),
        ),
        if (text != null) Text(text, style: style),
      ],
    );
  }
}
