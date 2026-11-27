import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/screens/main_screen.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';

import '../../helpers/bottom_menu_background.dart';

// 확장 메뉴(면세·일정 추가): docs/mockups/bottom-nav.md 10-8절 완료 조건.
// 번역 카메라 화면과 겹침은 bottom_menu_expanded_capture_test.dart, 메인 화면 연결은
// test/screens/main_screen_coming_soon_test.dart에 있다.

const _exchange = 0, _map = 1, _translation = 2, _schedule = 3, _dutyFree = 4;

final _current = find.byKey(const ValueKey('bottom-menu-current'));
Finder _tab(int index) => find.byKey(ValueKey('bottom-menu-tab-$index'));

// 버튼 중심(하단 가운데 기준)과 지름. 기존 네 버튼은 그대로, 새 버튼은 지도 위 양옆(10-2절).
const _design = {
  _exchange: (Offset(-93, 72), 64.0),
  _map: (Offset(0, 122), 64.0),
  _translation: (Offset(93, 72), 64.0),
  -1: (Offset(0, 42), 76.0),
  _schedule: (Offset(93, 172), 64.0),
  _dutyFree: (Offset(-93, 172), 64.0),
};

Future<void> _mount(
  WidgetTester tester, {
  double width = 320,
  double height = 640,
  int selectedIndex = _exchange,
  bool alwaysShowIcon = false,
  List<int>? selections,
  List<int>? homes,
  ValueChanged<double>? expansion,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Stack(
            children: [
              // 메인 화면처럼 메뉴가 화면 전체를 받는다.
              Positioned.fill(
                child: BottomTabBar(
                  tabs: MainScreen.tabs,
                  selectedIndex: selectedIndex,
                  isHomeSelected: false,
                  onTabTap: (index) => selections?.add(index),
                  onHomeTap: () => homes?.add(-1),
                  alwaysShowIcon: alwaysShowIcon,
                  onExpansionChanged: expansion,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _icon(WidgetTester tester) async {
  if (tester.getSize(bottomMenuBackground).width < 74) {
    await tester.tap(_current);
    await tester.pumpAndSettle();
  }
}

/// 한 번 끌어(완전히 펼치는 거리 150) 펼친다.
Future<void> _open(WidgetTester tester) async {
  await _icon(tester);
  await tester.drag(_current, const Offset(0, -150));
  await tester.pumpAndSettle();
}

double _opacity(WidgetTester tester, int index) => tester
    .widget<Opacity>(
      find.ancestor(of: _tab(index), matching: find.byType(Opacity)).first,
    )
    .opacity;

bool _ignoring(WidgetTester tester, int index) => tester
    .widget<IgnorePointer>(
      find
          .ancestor(of: _tab(index), matching: find.byType(IgnorePointer))
          .first,
    )
    .ignoring;

double _width(WidgetTester tester) =>
    tester.getSize(bottomMenuBackground).width;

void main() {
  testWidgets('1. 한 번 끌어 6개가 모두 퍼지고, 기존 네 버튼 자리·크기는 그대로다', (tester) async {
    final selections = <int>[];
    await _mount(tester, selections: selections);
    await _open(tester);

    final origin = tester.getRect(find.byType(BottomTabBar)).bottomCenter;
    for (final MapEntry(key: index, value: (center, size)) in _design.entries) {
      expect(_tab(index), findsOneWidget, reason: '$index');
      final rect = tester.getRect(_tab(index));
      expect(
        rect.center - origin,
        within(distance: .01, from: center.scale(1, -1)),
        reason: '$index',
      );
      expect(rect.size, Size.square(size), reason: '$index');
      expect(_opacity(tester, index), closeTo(1, .001), reason: '$index');
      expect(_ignoring(tester, index), isFalse, reason: '$index');
    }
    // 새 버튼은 이름·아이콘을 그린다.
    for (final (index, label, icon) in [
      (_schedule, '일정', Icons.event_note),
      (_dutyFree, '면세', Icons.shopping_bag),
    ]) {
      expect(
        find.descendant(of: _tab(index), matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tab(index), matching: find.byIcon(icon)),
        findsOneWidget,
      );
    }
    // 더 끌거나 두 번째 끌기 없이 이미 누를 수 있다.
    await tester.tap(_tab(_dutyFree));
    await tester.pumpAndSettle();
    expect(selections, [_dutyFree]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('1. 새 버튼은 p 0.3부터 나타나 기존 버튼보다 늦게 퍼진다', (tester) async {
    await _mount(tester);
    await _icon(tester);
    final gesture = await tester.startGesture(tester.getCenter(_current));
    await gesture.moveBy(const Offset(0, -45)); // p 0.3
    await tester.pump();
    expect(_opacity(tester, _schedule), closeTo(0, .001));
    expect(_opacity(tester, _dutyFree), closeTo(0, .001));
    expect(_opacity(tester, _map), greaterThan(0));
    await gesture.moveBy(const Offset(0, -30)); // p 0.5
    await tester.pump();
    expect(_opacity(tester, _schedule), closeTo(.2 / .7, .001));
    expect(_opacity(tester, _map), closeTo(.35 / .85, .001));
    // 다 펼치기 전(p ≤ 0.9)에는 누를 수 없다.
    for (final index in _design.keys) {
      expect(_ignoring(tester, index), isTrue, reason: '$index');
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('2. 배경은 하나의 원이 화면 전체로 이어서 커지고, 접을 때는 버튼 모임 → 원 → 점 순서다', (
    tester,
  ) async {
    var progress = 0.0;
    await _mount(
      tester,
      selections: [],
      expansion: (value) => progress = value,
    );
    await _icon(tester);
    expect(_width(tester), 74);

    final gesture = await tester.startGesture(tester.getCenter(_current));
    var previous = _width(tester);
    final reach = math.sqrt(160 * 160 + math.pow(640 - 49, 2)) + 2;
    for (final step in [1, 2, 3, 4]) {
      await gesture.moveBy(const Offset(0, -37.5));
      await tester.pump();
      expect(progress, closeTo(step * .25, .001));
      final rect = tester.getRect(bottomMenuBackground);
      // 같은 원이 현재 화면 버튼 중심(아래 49)을 중심으로 커진다.
      expect(rect.width, closeTo(rect.height, .01));
      expect(rect.center, within(distance: .01, from: const Offset(160, 591)));
      expect(rect.width, greaterThan(previous));
      final eased = progress * progress * (3 - 2 * progress);
      expect(rect.width / 2, closeTo(37 + (reach - 37) * eased, .01));
      previous = rect.width;
      // 중간에는 아직 원이고(화면 위 모서리는 덮지 않는다), 끝에서 화면 네 모서리를 덮는다.
      expect(bottomMenuBackgroundCoversArea(tester), step == 4);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expectBottomMenuBackgroundCoversArea(tester);

    // 다른 화면을 고르면 접는다. 프레임마다 진행률과 배경 지름을 기록한다.
    await tester.tap(_tab(_map));
    final frames = <(double, double)>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames.add((progress, _width(tester)));
    }
    await tester.pumpAndSettle();
    // 버튼이 가운데로 모이는 동안(p > 0) 진행률은 줄기만 하고, 배경은 원(74)보다 작아지지 않는다.
    for (var i = 1; i < frames.length; i++) {
      expect(frames[i].$1, lessThanOrEqualTo(frames[i - 1].$1));
    }
    for (final (p, width) in frames) {
      if (p > 0) expect(width, greaterThanOrEqualTo(74 - .01));
      // 원이 점으로 줄어드는 것은 버튼이 다 모인 뒤다.
      if (width < 74 - .01) expect(p, 0);
    }
    expect(frames.any((f) => f.$1 == 0 && f.$2 > 10 && f.$2 < 74), isTrue);
    expect(_width(tester), 10);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('2. 새 버튼 이름표는 지도 버튼과 겹치지 않는다(글자 배율 1·1.3·2.0, 폭 320·300)', (
    tester,
  ) async {
    for (final width in [320.0, 300.0]) {
      for (final textScale in [1.0, 1.3, 2.0]) {
        await _mount(tester, width: width, textScale: textScale);
        await _open(tester);
        final map = tester.getRect(_tab(_map));
        for (final (index, label) in [(_schedule, '일정'), (_dutyFree, '면세')]) {
          final text = tester.getRect(
            find.descendant(of: _tab(index), matching: find.text(label)),
          );
          final reason = '$label $width $textScale';
          expect(text.overlaps(map), isFalse, reason: reason);
          // 이름표는 자기 버튼 원 안에 줄여 맞춘다.
          final own = tester.getRect(_tab(index)).inflate(.01);
          expect(own.contains(text.topLeft), isTrue, reason: reason);
          expect(own.contains(text.bottomRight), isTrue, reason: reason);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('3. 펼친 상태에서 빈 곳을 누르면 이동 없이 점으로 접힌다', (tester) async {
    final selections = <int>[], homes = <int>[];
    await _mount(tester, selections: selections, homes: homes);
    // 화면 위쪽·가운데·버튼 사이 빈 곳.
    for (final spot in const [
      Offset(20, 40),
      Offset(300, 300),
      Offset(160, 400),
    ]) {
      await _open(tester);
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
      expect(_width(tester), 10, reason: '$spot');
    }
    expect(selections, isEmpty);
    expect(homes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('3. 펼친 상태에서 화면 위쪽 어디서든 아래로 끌면 접힌다', (tester) async {
    var progress = 0.0;
    final selections = <int>[];
    await _mount(
      tester,
      selections: selections,
      expansion: (value) => progress = value,
    );
    for (final start in const [
      Offset(6, 6),
      Offset(160, 60),
      Offset(300, 200),
    ]) {
      await _open(tester);
      expect(progress, 1);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      // 손가락을 따라 진행률이 줄어든다(150에 1).
      expect(progress, closeTo(.6, .001), reason: '$start');
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump();
      expect(progress, 0, reason: '$start');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(progress, 0, reason: '$start');
      expect(_width(tester), 74, reason: '$start');
    }
    expect(selections, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('3. 번역 화면에서 빈 곳을 누르면 현재 화면 버튼 상태로 돌아온다', (tester) async {
    final selections = <int>[];
    await _mount(
      tester,
      selectedIndex: _translation,
      alwaysShowIcon: true,
      selections: selections,
    );
    await tester.pump();
    expect(_width(tester), 74);
    await _open(tester);
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(_width(tester), 74);
    expect(_tab(_schedule), findsNothing);
    expect(selections, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('4. 폭 320·300에서 모든 버튼이 화면 안이다', (tester) async {
    for (final width in [320.0, 300.0]) {
      await _mount(tester, width: width);
      await _open(tester);
      final scale = math.min(1.0, width / 320);
      final origin = Offset(width / 2, 640);
      for (final MapEntry(key: index, value: (center, _)) in _design.entries) {
        final rect = tester.getRect(_tab(index));
        final reason = '$index $width';
        expect(rect.left, greaterThanOrEqualTo(0), reason: reason);
        expect(rect.right, lessThanOrEqualTo(width), reason: reason);
        expect(rect.top, greaterThanOrEqualTo(0), reason: reason);
        expect(rect.bottom, lessThanOrEqualTo(640), reason: reason);
        // 좁은 화면에서는 가로 간격만 폭에 맞춰 줄인다.
        expect(
          rect.center - origin,
          within(distance: .01, from: Offset(center.dx * scale, -center.dy)),
          reason: reason,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('5. 면세·일정 버튼은 각 탭(4·3)으로 이동하며 점으로 접힌다', (tester) async {
    for (final index in [_dutyFree, _schedule]) {
      final selections = <int>[];
      await _mount(tester, selections: selections);
      await _open(tester);
      await tester.tap(_tab(index));
      await tester.pumpAndSettle();
      expect(selections, [index]);
      expect(_width(tester), 10);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('5. 면세·일정 화면에서 같은 버튼을 다시 고르면 이동 없이 접기만 한다', (tester) async {
    final selections = <int>[];
    await _mount(tester, selectedIndex: _dutyFree, selections: selections);
    await _open(tester);
    // 현재 화면(면세) 버튼은 옮겨 온 안쪽 버튼이 그리므로 부채꼴 쪽에는 모양이 없다.
    expect(
      find.descendant(of: _tab(_dutyFree), matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    await tester.tap(_tab(_dutyFree));
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(_width(tester), 10);
    await tester.pumpWidget(const SizedBox());
  });
}
