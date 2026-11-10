import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'place_search_results_panel.dart';

/// 지도 위 요소의 세로 배치.
///
/// 위에서부터 검색창, 빈 영역, 하단 영역(지도 위 버튼 → 결과 목록 → 상세 카드)을
/// 세로로 놓는다. 하단 영역은 검색창 아래 남은 높이 안에서만 자라므로, 검색창이
/// 안내 문구나 큰 글자로 높아져도 결과 목록과 카드가 검색창을 가리지 않는다.
/// 공간이 모자라면 결과 목록([resultsPanel])이 줄어든다.
///
/// 키보드가 열려 있으면 하단 영역에는 결과 목록만 남기고 지도 위 버튼과 상세 카드는
/// 숨긴다(선택 상태는 그대로라 키보드를 닫으면 다시 보인다). 남은 높이가 목록 손잡이도
/// 담지 못할 만큼 작으면 목록도 숨긴다. 키보드가 열린 동안은 입력이 우선이고, 검색창
/// 아래 남은 높이가 작은 화면에서는 카드·버튼을 함께 둘 수 없기 때문이다.
/// 숨기고 다시 보일 때 애니메이션은 넣지 않는다. 키보드가 올라오고 내려가는 움직임이
/// 이미 변화를 보여주고, 검색할 때마다 반복되며, 그동안 하단 영역 높이가 매 프레임
/// 바뀌어 페이드를 더하면 화면이 흔들린다.
///
/// 이 위젯 자체는 터치를 받지 않아 빈 영역의 터치는 아래 지도로 간다.
class MapOverlayLayout extends StatelessWidget {
  const MapOverlayLayout({
    super.key,
    required this.searchBar,
    required this.mapControls,
    this.resultsPanel,
    this.detailCard,
  });

  /// 화면 가장자리와 검색창 사이 여백
  static const EdgeInsets searchBarPadding = EdgeInsets.fromLTRB(16, 12, 16, 8);

  final Widget searchBar;

  /// 축척 표시·현재 위치 버튼. 목록·카드 바로 위에 놓인다.
  final Widget mapControls;

  /// 결과 목록. 남은 높이에 맞춰 줄어들 수 있어야 한다.
  final Widget? resultsPanel;

  final Widget? detailCard;

  /// 키보드가 열려 있는지.
  ///
  /// 탭을 감싸는 Scaffold가 키보드 높이만큼 본문을 줄이면서 본문의 MediaQuery에서
  /// viewInsets를 지우므로, 화면(View)의 값을 직접 읽는다. 키보드가 열리고 닫히면
  /// 본문 높이가 바뀌어 아래 LayoutBuilder가 다시 그린다.
  static bool _isKeyboardOpen(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return true;
    }

    final view = View.maybeOf(context);
    return view != null && view.viewInsets.bottom > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: searchBarPadding, child: searchBar),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _buildBottomArea(context, constraints.maxHeight),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomArea(BuildContext context, double availableHeight) {
    final panel = resultsPanel;
    final card = detailCard;
    final keyboardOpen = _isKeyboardOpen(context);

    // 손잡이 최소 높이를 글자 배율로 키운 값. 실제 손잡이 높이보다 작지 않다.
    final panelMinHeight = math.max(
      PlaceSearchResultsPanel.handleHeight,
      MediaQuery.textScalerOf(
        context,
      ).scale(PlaceSearchResultsPanel.handleHeight),
    );
    final showPanel =
        panel != null && (!keyboardOpen || availableHeight >= panelMinHeight);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!keyboardOpen) mapControls,
        if (showPanel) Flexible(child: panel),
        if (!keyboardOpen && card != null) card,
      ],
    );
  }
}
