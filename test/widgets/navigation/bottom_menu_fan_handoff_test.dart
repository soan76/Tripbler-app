import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/tab_item.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';

import '../../helpers/bottom_menu_background.dart';

// 끄는 동안 안쪽 버튼이 부채꼴의 현재 화면 버튼이 되는 이어받기와 부채꼴 다른 버튼의 모양,
// 그리고 이어받기 전 아이콘 상태의 안쪽 아이콘 그림 크기·자리.
// 설계: docs/mockups/bottom-nav-current-button.md 6절

const _tabs = [
  TabItem(label: '환율', icon: Icons.attach_money),
  TabItem(label: '지도', icon: Icons.map),
  TabItem(label: '번역', icon: Icons.translate),
];
final _current = find.byKey(const ValueKey('bottom-menu-current'));
final _background = find.byKey(const ValueKey('bottom-menu-background'));
final _button = find.byKey(const ValueKey('bottom-menu-current-button'));

/// [selectedIndex]가 -1이면 AI 홈이다.
Future<void> _mount(
  WidgetTester tester, {
  required int selectedIndex,
  double width = 320,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: BottomTabBar(
            tabs: _tabs,
            selectedIndex: selectedIndex,
            isHomeSelected: selectedIndex == -1,
            onTabTap: (_) {},
            onHomeTap: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('홈·지도와 폭 300에서도 안쪽 버튼이 부채꼴 현재 화면 버튼 자리로 옮겨 가 그 버튼이 된다', (
    tester,
  ) async {
    // (선택 탭, 폭, p=1 중심(하단 가운데 기준), p=1 지름). 폭 320 미만은 좌우 자리만 줄인다.
    for (final (index, width, target, size) in [
      (-1, 320.0, const Offset(0, 42), 76.0),
      (1, 320.0, const Offset(0, 122), 64.0),
      (2, 300.0, const Offset(93 * 300 / 320, 72), 64.0),
    ]) {
      await _mount(tester, selectedIndex: index, width: width);
      await tester.tap(_current);
      await tester.pumpAndSettle();
      // 버튼 자리는 메뉴 영역 하단 가운데 기준이다(p<1에서는 배경 아래 끝이 아직 떠 있다).
      final origin = Offset(width / 2, 640);

      // 중간(p 0.5)에는 (0, 49)와 설계 자리 사이, 지름 55와 최종 지름 사이에 있다.
      final gesture = await tester.startGesture(tester.getCenter(_current));
      await gesture.moveBy(const Offset(0, -75)); // 완전히 펼치는 거리 150의 절반
      await tester.pump();
      final half = Offset.lerp(const Offset(0, 49), target, .5)!;
      expect(
        tester.getRect(_button).center - origin,
        within(distance: .01, from: half.scale(1, -1)),
        reason: '$index',
      );
      expect(tester.getSize(_button).width, closeTo((55 + size) / 2, .01));
      await gesture.up();
      await tester.pumpAndSettle();

      final tab = find.byKey(ValueKey('bottom-menu-tab-$index'));
      expectBottomMenuBackgroundCoversArea(tester);
      expect(
        tester.getRect(_button),
        within(distance: .01, from: tester.getRect(tab)),
      );
      expect(tester.getSize(_button), Size(size, size));
      expect(
        tester.getRect(_button).center - origin,
        within(distance: .01, from: target.scale(1, -1)),
      );
      expect(
        find.descendant(
          of: _button,
          matching: find.text(index == -1 ? 'AI' : _tabs[index].label),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('부채꼴의 다른 버튼은 옅은 바탕 원에 아이콘과 이름을 그린다', (tester) async {
    await _mount(tester, selectedIndex: 0);
    await tester.tap(_current);
    await tester.pumpAndSettle();
    await tester.drag(_current, const Offset(0, -150));
    await tester.pumpAndSettle();

    final colors = Theme.of(tester.element(_button)).colorScheme;
    for (final (index, label, icon) in [
      (1, '지도', Icons.map),
      (2, '번역', Icons.translate),
      (-1, 'AI', Icons.auto_awesome),
    ]) {
      final tab = find.byKey(ValueKey('bottom-menu-tab-$index'));
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: tab,
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, colors.surfaceContainerHighest);
      expect(
        decoration.border!.top.color,
        colors.primary.withValues(alpha: .25),
      );
      final drawn = tester.widget<Icon>(
        find.descendant(of: tab, matching: find.byIcon(icon)),
      );
      expect(drawn.color, colors.onSurfaceVariant);
      expect(
        find.descendant(of: tab, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // 선택된 환율 버튼은 안쪽 버튼이 그려 부채꼴 쪽에는 모양이 없다.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-menu-tab-0')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('아이콘 상태의 안쪽 아이콘 그림은 22이고 안쪽 버튼 55와 바깥 원 74의 정가운데에 있다', (
    tester,
  ) async {
    await _mount(tester, selectedIndex: 0);
    await tester.tap(_current);
    await tester.pumpAndSettle();

    expect(tester.getSize(_background), const Size(74, 74));
    expect(tester.getSize(_button), const Size(55, 55));
    final glyph = find.descendant(
      of: _button,
      matching: find.byIcon(Icons.attach_money),
    );
    expect(tester.widget<Icon>(glyph).size, 22);
    expect(
      tester.getCenter(glyph),
      within(distance: .01, from: tester.getCenter(_button)),
    );
    expect(
      tester.getCenter(glyph),
      within(distance: .01, from: tester.getCenter(_background)),
    );

    // 누르는 동안과 끌어 버튼이 옮겨 가며 커지는 동안에도 그림은 버튼 가운데에 있다.
    final gesture = await tester.startGesture(tester.getCenter(_current));
    await tester.pump();
    expect(
      tester.getCenter(glyph),
      within(distance: .01, from: tester.getCenter(_button)),
    );
    await gesture.moveBy(const Offset(0, -45)); // p 0.3, 이름으로 바뀌기 전
    await tester.pump();
    expect(
      tester.getCenter(glyph),
      within(distance: .01, from: tester.getCenter(_button)),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
