import 'package:flutter/material.dart';

import '../../models/place_model.dart';
import '../../providers/map/map_provider.dart';
import '../../utils/map/place_category_labels.dart';

/// 검색 결과나 지도의 장소 아이콘을 골랐을 때 지도 아래에 열리는 장소 카드.
///
/// 기기 위치에서의 거리([distanceLabel])는 조회 없이 분류 옆에 바로 보여준다("카페 · 350m").
/// 평점·영업 여부는 "평점·영업 정보" 버튼을 눌러 조회를 마친 뒤에만 보여준다.
/// 조회 전에는 값이 없어도 "정보 없음"으로 단정하지 않는다.
/// 받은 지 30분이 지난 값은 지우지 않고 받은 시각과 함께 "오래된 정보"로 보여주며,
/// 새로 고침하는 동안과 새로 고침이 실패했을 때도 그대로 둔다.
/// 부모가 높이를 제한하면 카드 안을 스크롤해 모든 버튼에 닿을 수 있다.
///
/// 바로 위의 결과 목록과 같은 모양(화면 폭 전체, 단색 표면, 위쪽 경계선)으로 붙여
/// 하단 영역을 한 덩어리로 보이게 한다.
///
/// 조회 상태가 바뀌어 카드 높이가 달라질 때 애니메이션은 넣지 않는다. 카드 높이가
/// 바뀌면 위의 결과 목록과 지도 위 버튼도 함께 움직여, 높이를 애니메이션하면 하단
/// 영역 전체가 흔들린다. 누른 버튼 자리에 진행 표시와 결과가 나타나 변화는 충분히
/// 드러난다.
class PlaceDetailCard extends StatelessWidget {
  const PlaceDetailCard({
    super.key,
    required this.place,
    required this.detailsStatus,
    required this.detailsLoaded,
    required this.onClose,
    required this.onDetailPressed,
    this.detailsStale = false,
    this.detailsFetchedAt,
    this.detailsErrorMessage,
    this.onRoutePressed,
    this.distanceLabel,
    this.now = DateTime.now,
  });

  static const String detailButtonLabel = '평점·영업 정보';
  static const String loadingLabel = '불러오는 중';
  static const String retryLabel = '다시 시도';
  static const String routeLabel = '길찾기';
  static const String noRatingLabel = '평점 정보 없음';
  static const String noOpenNowLabel = '영업 정보 없음';
  static const String defaultErrorMessage = '장소 상세 정보를 불러오지 못했습니다.';
  static const String refreshLabel = '새로 고침';
  static const String staleLabel = '오래된 정보';

  /// 길찾기 버튼의 낭독 문구. 누르면 Tripbler를 떠나 Google 지도(앱 또는 브라우저)로
  /// 넘어간다는 것을 미리 알린다. 화면에는 아이콘이 길찾기를 나타내므로 글자는 짧게 둔다.
  static const String routeSemanticsLabel = '길찾기, Google 지도에서 열기';

  /// 길찾기를 열지 못했을 때 화면이 띄우는 안내.
  static const String routeFailedMessage = '길찾기를 열 수 없습니다';

  /// 버튼 두 개를 한 줄에 놓을 최소 폭(글자 배율 1 기준). 좁으면 세로로 쌓는다.
  static const double _buttonRowMinWidth = 320;

  final PlaceModel place;

  /// 상세 조회 상태(조회 중·실패). 조회를 마쳤는지는 [detailsLoaded]로 받는다.
  final PlaceDetailsStatus detailsStatus;

  /// 이 장소의 상세 결과를 받아 둔 적이 있는지(오래된 결과 포함).
  /// true면 평점·영업 여부를 표시한다.
  final bool detailsLoaded;

  /// 받아 둔 결과가 30분이 지나 오래됐는지. true면 받은 시각과 새로 고침 버튼을 보인다.
  final bool detailsStale;

  /// 결과를 받은 시각(기기 현지 시간).
  final DateTime? detailsFetchedAt;

  /// 받은 시각이 오늘인지 판단할 현재 시각. 테스트에서 바꿔 넣는다.
  final DateTime Function() now;

  final String? detailsErrorMessage;
  final VoidCallback onClose;

  /// 상세 조회와 다시 시도에 쓴다.
  final VoidCallback onDetailPressed;

  /// 길찾기 열기. null이면 버튼이 꺼진다.
  final VoidCallback? onRoutePressed;

  /// 기기 위치(검색할 때의 위치)에서 이 장소까지의 거리 문구(예: "350m").
  /// 위치나 장소 좌표를 몰라 계산할 수 없으면 null이고, 거리를 표시하지 않는다.
  final String? distanceLabel;

  bool get _isLoading => detailsStatus == PlaceDetailsStatus.loading;
  bool get _isFailure =>
      !_isLoading && detailsStatus == PlaceDetailsStatus.failure;

  /// 평점·영업 값을 보여줄지. 받아 둔 값은 새로 고침 중이나 실패에도 유지한다.
  bool get _showDetails => detailsLoaded;

  /// 받아 둔 값이 아직 유효해 다시 조회할 필요가 없는지.
  bool get _isFresh =>
      detailsLoaded && !detailsStale && !_isLoading && !_isFailure;

  /// 조회 시각 문구. 같은 날이면 "14:05 기준", 날짜가 다르면 "11월 10일 23:55 기준".
  static String fetchedAtLabel(DateTime fetchedAt, {required DateTime now}) {
    final local = fetchedAt.toLocal();
    final today = now.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final sameDay =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;

    return sameDay ? '$time 기준' : '${local.month}월 ${local.day}일 $time 기준';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final categoryLabel = PlaceCategoryLabels.labelFor(place.category);
    final distance = distanceLabel;
    // 분류와 거리를 한 줄에 둔다. 거리는 조회 값이 아니라서 평점·영업 묶음과 떼어 놓아,
    // 오래된 정보 안내가 거리에 붙어 보이지 않게 한다.
    final summaryParts = [?categoryLabel, ?distance];
    // 가운뎃점은 낭독기에서 어색하게 읽히므로 쉼표로 끊고, 거리는 기준을 밝혀 읽힌다.
    final summarySemantics = [
      ?categoryLabel,
      if (distance != null) '현재 위치에서 $distance',
    ].join(', ');

    return Material(
      color: colorScheme.surface,
      elevation: 4,
      // 결과 목록과 같이, 다크 모드에서 잘 보이지 않는 그림자 대신 경계선으로 구분한다.
      shape: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      // 장소명 첫 줄을 닫기 버튼(48dp)의 가운데에 맞춘다.
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        place.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                    tooltip: '닫기',
                  ),
                ],
              ),
              // 닫기 버튼 자리(오른쪽 여백 4)를 뺀 본문은 오른쪽 여백 16을 맞춘다.
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (summaryParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        summaryParts.join(' · '),
                        semanticsLabel: summarySemantics,
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (place.address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        place.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_showDetails) ...[
                      const SizedBox(height: 12),
                      // 값과 오래된 정보 안내를 한 묶음으로 읽혀, 어느 값이 언제
                      // 받은 것인지 함께 전달한다.
                      MergeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDetails(context),
                            if (detailsStale) ...[
                              const SizedBox(height: 8),
                              _buildStaleNotice(context),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_isFailure) ...[
                      const SizedBox(height: 12),
                      _buildError(context),
                    ],
                    const SizedBox(height: 16),
                    _buildButtons(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 조회한 평점과 영업 여부. 칩 대신 아이콘과 글자로 본문과 같은 결에 둔다.
  Widget _buildDetails(BuildContext context) {
    final rating = place.rating;
    final openNow = place.openNow;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _DetailItem(
          icon: Icons.star_outline,
          label: rating != null
              ? '평점 ${rating.toStringAsFixed(1)}'
              : noRatingLabel,
        ),
        _DetailItem(
          icon: switch (openNow) {
            true => Icons.check_circle_outline,
            false => Icons.highlight_off_outlined,
            null => Icons.schedule_outlined,
          },
          label: switch (openNow) {
            true => '영업 중',
            false => '영업 종료',
            null => noOpenNowLabel,
          },
        ),
      ],
    );
  }

  /// 오래된 정보 안내: 언제 받은 값인지 함께 보여준다.
  ///
  /// 값보다 한 단계 낮은 위계(작은 글자, 보조색)로 두되, 시계 아이콘을 값 아이콘과
  /// 같은 열에 놓아 값에 딸린 안내로 보이게 한다. 실패가 아니므로 강조색은 쓰지 않는다.
  Widget _buildStaleNotice(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fetchedAt = detailsFetchedAt;
    final time = fetchedAt == null
        ? null
        : fetchedAtLabel(fetchedAt, now: now());
    final label = time == null ? staleLabel : '$staleLabel · $time';
    // 가운뎃점은 낭독기에서 어색하게 읽히므로 쉼표로 끊어 읽힌다.
    final semanticsLabel = time == null ? staleLabel : '$staleLabel, $time';
    // 값 아이콘(20)과 같은 폭의 자리에 작은 아이콘을 두어 글자 시작을 값과 맞춘다.
    final iconSlot = MediaQuery.textScalerOf(context).scale(20);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: iconSlot,
          child: Icon(
            Icons.history,
            size: 16,
            applyTextScaling: true,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            semanticsLabel: semanticsLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// 조회 실패 안내. 결과 목록의 실패 안내처럼 오류색 아이콘으로 구분한다.
  Widget _buildError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline,
          size: 20,
          applyTextScaling: true,
          color: colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          // 실패로 바뀌면 화면 낭독기가 바로 읽도록 한다.
          child: Semantics(
            liveRegion: true,
            child: Text(
              detailsErrorMessage ?? defaultErrorMessage,
              style: textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );

    final routeButton = FilledButton.icon(
      onPressed: onRoutePressed,
      style: style,
      icon: const Icon(Icons.directions_outlined),
      label: const Text(routeLabel, semanticsLabel: routeSemanticsLabel),
    );

    // 유효한 값을 받아 두었으면 상세 버튼을 숨기고 길찾기만 남긴다.
    if (_isFresh) {
      return routeButton;
    }

    final Widget detailButton;

    if (_isLoading) {
      // 조회 중에는 버튼을 꺼 같은 요청을 다시 보내지 않는다.
      // 진행 표시는 버튼 문구("불러오는 중")와 같은 뜻이라 낭독에서 뺀다.
      detailButton = OutlinedButton.icon(
        onPressed: null,
        style: style,
        icon: const ExcludeSemantics(
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        label: const Text(loadingLabel),
      );
    } else if (_isFailure) {
      detailButton = OutlinedButton.icon(
        onPressed: onDetailPressed,
        style: style,
        icon: const Icon(Icons.refresh),
        label: const Text(retryLabel),
      );
    } else if (detailsLoaded) {
      // 받아 둔 값이 오래됐다.
      detailButton = OutlinedButton.icon(
        onPressed: onDetailPressed,
        style: style,
        icon: const Icon(Icons.refresh),
        label: const Text(refreshLabel),
      );
    } else {
      detailButton = OutlinedButton.icon(
        onPressed: onDetailPressed,
        style: style,
        icon: const Icon(Icons.info_outline),
        label: const Text(detailButtonLabel),
      );
    }

    final rowMinWidth = MediaQuery.textScalerOf(
      context,
    ).scale(_buttonRowMinWidth);

    // 폭이 넉넉하면 나란히, 좁거나 글자가 크면 같은 폭으로 세로로 쌓는다.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= rowMinWidth) {
          return Row(
            children: [
              Expanded(child: detailButton),
              const SizedBox(width: 8),
              Expanded(child: routeButton),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [detailButton, const SizedBox(height: 8), routeButton],
        );
      },
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          applyTextScaling: true,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}
