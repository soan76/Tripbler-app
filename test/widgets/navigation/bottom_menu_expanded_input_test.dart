import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/screens/main_screen.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';
import 'package:tripbler/widgets/navigation/bottom_menu_capture_marks.dart';

import '../../helpers/bottom_menu_background.dart';

// 확장 메뉴(bottom-nav.md 10절)의 입력 통과, 일정·면세 현재 화면 버튼 이어짐, 받은 높이가 작을 때
// (키보드·가로 화면) 펼치지 않는 동작. 배치·접기는 bottom_menu_expanded_test.dart에 있다.

const _schedule = 3, _dutyFree = 4;

final _current = find.byKey(const ValueKey('bottom-menu-current'));
final _currentButton = find.byKey(const ValueKey('bottom-menu-current-button'));
Finder _tab(int index) => find.byKey(ValueKey('bottom-menu-tab-$index'));

double _width(WidgetTester tester) =>
    tester.getSize(bottomMenuBackground).width;

/// 메인 화면처럼 `Stack` + `Positioned.fill(BottomTabBar)`로 띄우고, 아래에 스크롤 목록을 둔다.
/// [height]를 바꾸면 메뉴가 받는 높이가 바뀐다(키보드가 본문을 줄이는 경우).
Future<void> _mount(
  WidgetTester tester, {
  int selectedIndex = 0,
  bool alwaysShowIcon = false,
  ScrollController? scroll,
  VoidCallback? onBelowTap,
  VoidCallback? capture,
  ValueNotifier<double>? height,
  ValueChanged<double>? expansion,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final area = height ?? ValueNotifier<double>(640);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 640)),
        child: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: area,
            builder: (context, value, _) => Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: value,
                child: Stack(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onBelowTap,
                      child: ListView.builder(
                        controller: scroll,
                        itemExtent: 50,
                        itemCount: 100,
                        itemBuilder: (context, i) => Text('row $i'),
                      ),
                    ),
                    Positioned.fill(
                      child: BottomTabBar(
                        tabs: MainScreen.tabs,
                        selectedIndex: selectedIndex,
                        isHomeSelected: false,
                        onTabTap: (_) {},
                        onHomeTap: () {},
                        onCurrentScreenTap: capture,
                        alwaysShowIcon: alwaysShowIcon,
                        onExpansionChanged: expansion,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _icon(WidgetTester tester) async {
  if (_width(tester) < 74) {
    await tester.tap(_current);
    await tester.pumpAndSettle();
  }
}

Future<void> _open(WidgetTester tester) async {
  await _icon(tester);
  await tester.drag(_current, const Offset(0, -150));
  await tester.pumpAndSettle();
}

bool _canExpandBySemantics(WidgetTester tester) {
  final actions = tester
      .widget<Semantics>(_current)
      .properties
      .customSemanticsActions;
  return actions != null &&
      actions.keys.any((action) => action.label == '메뉴 펼치기');
}

void main() {
  group('입력 통과', () {
    // 버튼·원 밖의 메뉴 빈 영역.
    const spot = Offset(160, 300);

    testWidgets('점·현재 화면 버튼 상태에서는 빈 영역의 끌기·누르기가 아래 화면에 닿는다', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var belowTaps = 0;
      await _mount(tester, scroll: scroll, onBelowTap: () => belowTaps++);

      for (final icon in [false, true]) {
        if (icon) await _icon(tester);
        expect(_width(tester), icon ? 74 : 10);
        final before = scroll.offset;
        await tester.dragFrom(spot, const Offset(0, -120));
        await tester.pump();
        expect(scroll.offset, greaterThan(before), reason: 'icon $icon');
        // 끌기는 메뉴를 펼치지 않는다.
        expect(_tab(_schedule), findsNothing, reason: 'icon $icon');
        await tester.pumpAndSettle();
        // 아이콘 상태는 빈 곳 누르기로 점으로 접히지만, 누르기는 아래 화면에도 닿는다.
        if (icon) await _icon(tester);
        final taps = belowTaps;
        await tester.tapAt(spot);
        await tester.pumpAndSettle();
        expect(belowTaps, taps + 1, reason: 'icon $icon');
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('펼친 상태에서는 빈 영역의 끌기·누르기가 아래 화면에 닿지 않는다', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var belowTaps = 0;
      await _mount(tester, scroll: scroll, onBelowTap: () => belowTaps++);

      await _open(tester);
      expectBottomMenuBackgroundCoversArea(tester);
      // 위로 끌어도(이미 다 펼침) 아래 목록은 움직이지 않는다.
      await tester.dragFrom(spot, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expectBottomMenuBackgroundCoversArea(tester);
      // 빈 곳 누르기는 메뉴만 접고 아래 화면에는 닿지 않는다.
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
      expect(belowTaps, 0);
      expect(_width(tester), 10);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('일정·면세가 현재 탭이면 현재 화면 버튼이 펼치며 그 자리(±93, 172)로 이어진다', (
    tester,
  ) async {
    for (final (index, target) in [
      (_schedule, const Offset(93, 172)),
      (_dutyFree, const Offset(-93, 172)),
    ]) {
      await _mount(tester, selectedIndex: index);
      await _icon(tester);
      final origin = tester.getRect(find.byType(BottomTabBar)).bottomCenter;
      Offset center() => tester.getCenter(_currentButton) - origin;

      const start = BottomMenuMetrics.iconCenter;
      expect(
        center(),
        within(distance: .01, from: start.scale(1, -1)),
        reason: '$index',
      );
      final gesture = await tester.startGesture(tester.getCenter(_current));
      await gesture.moveBy(const Offset(0, -75)); // p 0.5
      await tester.pump();
      expect(
        center(),
        within(
          distance: .01,
          from: Offset.lerp(start, target, .5)!.scale(1, -1),
        ),
        reason: '$index p .5',
      );
      expect(
        tester.getSize(_currentButton).width,
        closeTo((BottomMenuMetrics.innerSize + 64) / 2, .01),
        reason: '$index p .5',
      );
      await gesture.moveBy(const Offset(0, -75)); // p 1
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        center(),
        within(distance: .01, from: target.scale(1, -1)),
        reason: '$index',
      );
      expect(tester.getSize(_currentButton), const Size.square(64));
      // 부채꼴 쪽 같은 자리 버튼과 겹친다.
      expect(
        tester.getCenter(_tab(index)) - origin,
        within(distance: .01, from: target.scale(1, -1)),
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  group('받은 높이가 버튼이 들어갈 높이(212)보다 작을 때(키보드·가로 화면)', () {
    testWidgets('펼치지 않고, 점↔현재 화면 버튼과 누르기(촬영)는 된다', (tester) async {
      final height = ValueNotifier<double>(180);
      addTearDown(height.dispose);
      var progress = 0.0, captures = 0;
      await _mount(
        tester,
        height: height,
        capture: () => captures++,
        expansion: (value) => progress = value,
      );
      await _icon(tester);
      expect(_width(tester), 74);
      expect(_canExpandBySemantics(tester), isFalse);

      final gesture = await tester.startGesture(tester.getCenter(_current));
      await gesture.moveBy(const Offset(0, -75));
      await tester.pump();
      expect(progress, 0);
      expect(_tab(_schedule), findsNothing);
      await gesture.moveBy(const Offset(0, -75));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(progress, 0);
      expect(_width(tester), 74);

      await tester.tap(_current);
      await tester.pumpAndSettle();
      expect(captures, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    for (final alwaysShowIcon in [false, true]) {
      testWidgets(
        '펼친 채 높이가 줄면 접고, 다시 늘면 펼칠 수 있다(alwaysShowIcon $alwaysShowIcon)',
        (tester) async {
          final height = ValueNotifier<double>(640);
          addTearDown(height.dispose);
          var progress = 0.0;
          await _mount(
            tester,
            selectedIndex: alwaysShowIcon ? 2 : 0,
            alwaysShowIcon: alwaysShowIcon,
            height: height,
            expansion: (value) => progress = value,
          );
          await tester.pump();
          await _open(tester);
          expect(progress, 1);

          height.value = 180;
          await tester.pumpAndSettle();
          expect(progress, 0);
          expect(_tab(_schedule), findsNothing);
          expect(_width(tester), alwaysShowIcon ? 74 : 10);

          height.value = 640;
          await tester.pumpAndSettle();
          await _icon(tester);
          expect(_canExpandBySemantics(tester), isTrue);
          await tester.drag(_current, const Offset(0, -150));
          await tester.pumpAndSettle();
          expect(progress, 1);
          expectBottomMenuBackgroundCoversArea(tester);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    // 버그 수정: 키보드가 프레임마다 높이를 바꾸며 올라오는 동안 접기를 매 프레임 처음부터 다시 걸어
    // 접힘이 늘어졌다. 높이가 계속 바뀌어도 한 번 시작한 접기는 제 시간(약 180+160ms)에 끝난다.
    testWidgets('키보드처럼 높이가 여러 프레임에 걸쳐 줄어도 접기는 한 번만 걸려 제 시간에 끝난다', (
      tester,
    ) async {
      final height = ValueNotifier<double>(640);
      addTearDown(height.dispose);
      var progress = 0.0;
      await _mount(
        tester,
        height: height,
        expansion: (value) => progress = value,
      );
      await tester.pump();
      await _open(tester);
      expect(progress, 1);

      // 16ms마다 높이를 20씩 줄이며 25프레임(400ms) 동안 키보드가 올라오는 것처럼 바꾼다.
      for (var frame = 0; frame < 25; frame++) {
        height.value = 200 - frame * 4.0;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(progress, 0);
      expect(_width(tester), 10);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
