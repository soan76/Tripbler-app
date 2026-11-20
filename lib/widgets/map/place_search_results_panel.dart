import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/place_model.dart';
import '../../providers/map/map_provider.dart';
import '../../utils/map/place_category_labels.dart';
import '../../utils/map/place_distance.dart';

/// 지도 하단의 접을 수 있는 장소 검색 결과 목록.
///
/// 접힌 상태에서는 요약 손잡이만, 펼친 상태에서는 [expandedHeight] 높이(부모가
/// 더 작게 제한하면 그 높이) 안에
/// 상태별 내용(검색 중, 결과 없음, 실패, 결과 목록)을 보여준다. 실패했지만 이전
/// 결과가 남아 있으면 오류 안내 아래에 이전 결과를 함께 보여준다.
///
/// 펼치고 접을 때 애니메이션은 넣지 않는다. 결과를 고를 때마다 반복하는 동작이고,
/// 지도 카메라 이동이 이미 변화를 보여주며, 높이가 바뀌는 동안 지도 위 버튼도 함께
/// 움직여 화면이 흔들리기 때문이다.
class PlaceSearchResultsPanel extends StatelessWidget {
  const PlaceSearchResultsPanel({
    super.key,
    required this.status,
    required this.results,
    this.distanceOrigin,
    required this.error,
    required this.canRetry,
    required this.expanded,
    required this.expandedHeight,
    required this.selectedPlaceId,
    required this.onToggleExpanded,
    required this.onSelect,
    required this.onRetry,
  });

  /// 접힌 손잡이의 최소 높이. 글자를 키우면 내용에 맞춰 늘어난다.
  static const double handleHeight = 56;

  final MapSearchStatus status;
  final List<PlaceModel> results;

  /// 거리 표시 기준인 기기 위치(검색할 때의 위치). null이면 거리를 표시하지 않는다.
  final LatLng? distanceOrigin;
  final MapSearchError? error;
  final bool canRetry;
  final bool expanded;
  final double expandedHeight;
  final String? selectedPlaceId;
  final VoidCallback onToggleExpanded;
  final ValueChanged<PlaceModel> onSelect;
  final VoidCallback onRetry;

  String get _summary {
    switch (status) {
      case MapSearchStatus.loading:
        return '검색 중';
      case MapSearchStatus.failure:
        return results.isEmpty
            ? '검색하지 못했습니다'
            : '검색하지 못했습니다 · 이전 결과 ${results.length}개';
      case MapSearchStatus.success:
        return results.isEmpty ? '검색 결과가 없습니다' : '검색 결과 ${results.length}개';
      case MapSearchStatus.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 4,
      // 다크 모드에서는 그림자가 잘 보이지 않아 위쪽 경계선으로 지도와 구분한다.
      shape: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHandle(context),
          if (expanded) ...[
            const Divider(height: 1),
            // 부모가 높이를 제한하면(상세 카드와 함께 있는 작은 화면 등) 목록이 줄어든다.
            Flexible(
              child: SizedBox(
                height: expandedHeight,
                child: _buildBody(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      expanded: expanded,
      onTapHint: expanded ? '결과 목록 접기' : '결과 목록 펼치기',
      child: InkWell(
        onTap: onToggleExpanded,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: handleHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              children: [
                if (status == MapSearchStatus.loading) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Icon(
                    expanded ? Icons.expand_more : Icons.expand_less,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (status) {
      case MapSearchStatus.loading:
        // 진행 표시는 손잡이와 검색창에 이미 있어 본문에는 문구만 둔다.
        return _buildMessage(context, title: '장소를 찾고 있습니다');
      case MapSearchStatus.failure:
        return _buildFailure(context);
      case MapSearchStatus.success:
        if (results.isEmpty) {
          return _buildMessage(
            context,
            title: '검색 결과가 없습니다',
            detail: '다른 검색어로 찾아보거나, 지도를 옮긴 뒤 다시 검색해 보세요.',
          );
        }

        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: results.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (context, index) => _buildItem(context, results[index]),
        );
      case MapSearchStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildItem(BuildContext context, PlaceModel place) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final category = PlaceCategoryLabels.labelFor(place.category);
    final isSelected = place.id == selectedPlaceId;
    final meters = PlaceDistance.metersTo(distanceOrigin, place);
    final distance = meters == null ? null : PlaceDistance.format(meters);

    // 선택한 항목은 배경색과 글자색으로 구분한다.
    final nameColor = isSelected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    final secondaryColor = isSelected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Semantics(
      selected: isSelected,
      button: true,
      child: Ink(
        color: isSelected ? colorScheme.secondaryContainer : null,
        child: InkWell(
          onTap: () => onSelect(place),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // 현지어 장소명은 길어서 두 줄까지 보여준다.
                      child: Text(
                        place.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: nameColor,
                        ),
                      ),
                    ),
                    if (category != null) ...[
                      const SizedBox(width: 12),
                      Padding(
                        // 장소명 첫 줄과 높이를 맞춘다.
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          category,
                          style: textTheme.labelMedium?.copyWith(
                            color: secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (place.address.isNotEmpty || distance != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          place.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: secondaryColor,
                          ),
                        ),
                      ),
                      // 기기 위치에서의 직선거리. 항목 오른쪽 아래(주소 마지막 줄)에 둔다.
                      // 분류 라벨과 같은 크기로 오른쪽 열을 맞추되, 고를 때 비교하는
                      // 값이라 장소명과 같은 진한 색으로 분류보다 한 단계 앞세운다.
                      // 숫자 폭을 고정해 목록을 내려가며 거리를 비교하기 쉽게 한다.
                      if (distance != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          distance,
                          semanticsLabel: '현재 위치에서 $distance',
                          maxLines: 1,
                          softWrap: false,
                          style: textTheme.labelMedium?.copyWith(
                            color: nameColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFailure(BuildContext context) {
    final message = _buildFailureMessage(context);

    if (results.isEmpty) {
      return SingleChildScrollView(padding: _messagePadding, child: message);
    }

    // 같은 조건으로 다시 검색하다 실패하면 Provider가 이전 결과를 유지한다.
    // 오류와 다시 시도 아래에 이전 결과를 함께 스크롤해 계속 고를 수 있게 한다.
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: message,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    '이전 검색 결과',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final itemIndex = index - 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (itemIndex > 0)
              const Divider(height: 1, indent: 16, endIndent: 16),
            _buildItem(context, results[itemIndex]),
          ],
        );
      },
    );
  }

  Widget _buildFailureMessage(BuildContext context) {
    final searchError = error;

    if (searchError?.type == MapSearchErrorType.invalidQuery) {
      // 같은 검색어로 다시 보내도 결과가 같으므로 다시 시도 대신 검색어 수정을 안내한다.
      return _buildMessageContent(
        context,
        title: searchError!.message,
        detail: '검색어를 고친 뒤 다시 검색해 주세요.',
        isError: true,
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return _buildMessageContent(
      context,
      title: searchError?.message ?? '장소를 검색하지 못했습니다.',
      isError: true,
      detail: searchError?.type == MapSearchErrorType.network
          ? '인터넷 연결을 확인한 뒤 다시 시도해 주세요.'
          : null,
      action: canRetry
          ? OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 48),
                textStyle: textTheme.labelLarge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text('다시 시도'),
            )
          : null,
    );
  }

  static const EdgeInsets _messagePadding = EdgeInsets.fromLTRB(16, 16, 16, 24);

  Widget _buildMessage(
    BuildContext context, {
    required String title,
    String? detail,
  }) {
    return SingleChildScrollView(
      padding: _messagePadding,
      child: _buildMessageContent(context, title: title, detail: detail),
    );
  }

  Widget _buildMessageContent(
    BuildContext context, {
    required String title,
    String? detail,
    Widget? action,
    bool isError = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final titleText = Text(title, style: textTheme.titleSmall);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isError)
          // 실패는 오류색 아이콘으로 구분한다. 이전 결과와 함께 보일 때도 위의 안내가
          // 지금 검색의 실패이고 아래 목록은 그 전 결과임을 한눈에 나눈다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.error_outline,
                  size: 20,
                  applyTextScaling: true,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: titleText),
            ],
          )
        else
          titleText,
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    );
  }
}
