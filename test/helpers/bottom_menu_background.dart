import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';

/// 하단 메뉴의 배경(하나의 원). bottom-nav.md 10-3절.
final bottomMenuBackground = find.byKey(
  const ValueKey('bottom-menu-background'),
);

/// 펼친 배경 원이 하단 메뉴 영역(메인 화면처럼 화면 전체를 받으면 화면 전체)의 네 모서리를 모두 덮는지.
bool bottomMenuBackgroundCoversArea(WidgetTester tester) {
  final circle = tester.getRect(bottomMenuBackground);
  final area = tester.getRect(find.byType(BottomTabBar));
  final radius = circle.width / 2;
  return [
    area.topLeft,
    area.topRight,
    area.bottomLeft,
    area.bottomRight,
  ].every((corner) => (corner - circle.center).distance <= radius);
}

/// 배경이 원(가로·세로 같음)이고 메뉴 영역 네 모서리를 덮는지 확인한다.
void expectBottomMenuBackgroundCoversArea(WidgetTester tester) {
  final size = tester.getSize(bottomMenuBackground);
  expect(size.width, closeTo(size.height, .01));
  expect(
    bottomMenuBackgroundCoversArea(tester),
    isTrue,
    reason: '펼친 배경이 메뉴 영역 네 모서리를 덮어야 한다',
  );
}
