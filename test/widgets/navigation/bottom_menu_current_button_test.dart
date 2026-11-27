import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/tab_item.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';
import 'package:tripbler/widgets/navigation/bottom_menu_capture_marks.dart';

// 현재 화면 버튼 상태: 반투명 바깥 원(74) 위의 불투명 안쪽 버튼(55).
// 설계: docs/mockups/bottom-nav-current-button.md
// 촬영 화면 꼬리표("눌러서 촬영"/"찍는 중")는 2026-11-27 사용자 요청으로 없앴다. 없음을 확인한다.

const _tabs = [
  TabItem(label: '환율', icon: Icons.attach_money),
  TabItem(label: '지도', icon: Icons.map),
  TabItem(label: '번역', icon: Icons.translate),
];
final _current = find.byKey(const ValueKey('bottom-menu-current'));
final _background = find.byKey(const ValueKey('bottom-menu-background'));
final _button = find.byKey(const ValueKey('bottom-menu-current-button'));
final _tag = find.byKey(const ValueKey('bottom-menu-tag'));
final _ring = find.byKey(const ValueKey('bottom-menu-capturing'));

/// 꼬리표와 그 문구가 어디에도 없다.
void _expectNoTag() {
  expect(_tag, findsNothing);
  expect(find.text('눌러서 촬영'), findsNothing);
  expect(find.text('찍는 중'), findsNothing);
}

Future<void> _mount(
  WidgetTester tester, {
  int selectedIndex = 2,
  VoidCallback? capture,
  bool capturing = false,
  bool captureScreen = false,
  ThemeData? theme,
  bool reduced = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(
        // 메인 화면처럼 메뉴에 화면 폭을 그대로 준다.
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: double.infinity,
            child: BottomTabBar(
              tabs: _tabs,
              selectedIndex: selectedIndex,
              isHomeSelected: false,
              onTabTap: (_) {},
              onHomeTap: () {},
              onCurrentScreenTap: capture,
              isCapturing: capturing,
              isCaptureScreen: captureScreen,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 점을 눌러 아이콘 상태로 키운다(촬영 중이면 고리가 돌아 정해진 시간만 그린다).
Future<void> _icon(WidgetTester tester) async {
  await tester.tap(_current);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

BoxDecoration _buttonDecoration(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find.descendant(of: _button, matching: find.byType(DecoratedBox)),
            )
            .decoration
        as BoxDecoration;

double _buttonScale(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(of: _button, matching: find.byType(Transform)).first,
    )
    .transform
    .storage[0];

/// 안쪽 버튼의 카메라 아이콘이 실제로 보이는 정도(감싼 투명도의 곱).
double _cameraOpacity(WidgetTester tester) {
  final icon = find.descendant(
    of: _button,
    matching: find.byIcon(Icons.photo_camera),
  );
  expect(icon, findsOneWidget);
  return tester
      .widgetList<Opacity>(
        find.ancestor(of: icon, matching: find.byType(Opacity)),
      )
      .fold(1.0, (value, opacity) => value * opacity.opacity);
}

void main() {
  testWidgets('반투명 바깥 원 74 정가운데에 불투명 안쪽 버튼 55가 놓이고 이름 글자는 없다', (tester) async {
    await _mount(tester, selectedIndex: 0);
    await _icon(tester);

    final outer = tester.getRect(_background);
    final inner = tester.getRect(_button);
    expect(outer.size, const Size(74, 74));
    expect(inner.size, const Size(55, 55));
    expect(inner.center, within(distance: .01, from: outer.center));

    final colors = Theme.of(tester.element(_button)).colorScheme;
    expect(_buttonDecoration(tester).color, colors.primary);
    final background =
        tester.widget<DecoratedBox>(_background).decoration as BoxDecoration;
    expect(background.color!.a, lessThan(1));

    // 촬영 화면이 아니면 탭 아이콘이고, 이름 글자와 꼬리표는 보이지 않는다.
    expect(
      find.descendant(of: _button, matching: find.byIcon(Icons.attach_money)),
      findsOneWidget,
    );
    expect(find.text('환율'), findsNothing);
    expect(_tag, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('번역 촬영 화면은 카메라 아이콘만 보이고 꼬리표가 없으며, 화면 내용 여백은 원 위 8이다', (
    tester,
  ) async {
    await _mount(tester, capture: () {}, captureScreen: true);
    await _icon(tester);

    expect(
      find.descendant(of: _button, matching: find.byIcon(Icons.photo_camera)),
      findsOneWidget,
    );
    _expectNoTag();
    // 바깥 원은 아래 12~86에 있고, 화면 내용(가짜 모드 띠 등)은 그 위 8을 띄운 94부터 둔다.
    final outer = tester.getRect(_background);
    expect(640 - outer.bottom, closeTo(12, .01));
    expect(640 - outer.top, closeTo(86, .01));
    expect(BottomMenuMetrics.contentClearance, closeTo(94, .01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('카메라가 준비되기 전에는 안쪽 버튼을 흐리게 하고 꼬리표를 숨긴다', (tester) async {
    await _mount(tester, captureScreen: true);
    await _icon(tester);

    expect(_buttonDecoration(tester).color!.a, closeTo(.38, .01));
    expect(_buttonDecoration(tester).boxShadow, isNull);
    expect(
      find.descendant(of: _button, matching: find.byIcon(Icons.photo_camera)),
      findsOneWidget,
    );
    expect(_tag, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('촬영 중에는 지름 63 고리가 안쪽 버튼을 두르고 꼬리표는 없다', (tester) async {
    await _mount(tester, capture: () {}, capturing: true, captureScreen: true);
    await _icon(tester);

    final ring = tester.getRect(_ring);
    expect(ring.size, const Size(63, 63));
    expect(
      ring.center,
      within(distance: .01, from: tester.getRect(_button).center),
    );
    expect(
      find.descendant(of: _button, matching: find.byType(Icon)),
      findsNothing,
    );
    _expectNoTag();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('누르는 동안 안쪽 버튼이 0.92배로 줄고 그림자가 사라지며, 놓으면 돌아온다', (tester) async {
    await _mount(tester, capture: () {});
    await _icon(tester);
    double scale() => tester
        .widget<Transform>(
          find.descendant(of: _button, matching: find.byType(Transform)).first,
        )
        .transform
        .storage[0];

    expect(scale(), closeTo(1, .001));
    expect(_buttonDecoration(tester).boxShadow, isNotNull);
    final gesture = await tester.startGesture(tester.getCenter(_current));
    await tester.pump();
    expect(scale(), closeTo(.92, .001));
    expect(_buttonDecoration(tester).boxShadow, isNull);
    await gesture.up();
    await tester.pump();
    expect(scale(), closeTo(1, .001));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('바깥 원의 고리 부분을 눌러도 촬영한다(터치 영역 74)', (tester) async {
    var captures = 0;
    await _mount(tester, capture: () => captures++, captureScreen: true);
    await _icon(tester);

    // 안쪽 버튼(반지름 27.5) 밖, 바깥 원(반지름 37) 안.
    await tester.tapAt(tester.getCenter(_current) + const Offset(32, 0));
    await tester.pump();
    expect(captures, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('펼치면 안쪽 버튼이 부채꼴의 현재 화면 버튼 자리로 옮겨 가 그 버튼이 된다', (tester) async {
    await _mount(tester, capture: () {}, captureScreen: true);
    await tester.tap(_current);
    await tester.pumpAndSettle();
    await tester.drag(_current, const Offset(0, -150));
    await tester.pumpAndSettle();

    final tab = find.byKey(const ValueKey('bottom-menu-tab-2'));
    expect(
      tester.getRect(_button),
      within(distance: .01, from: tester.getRect(tab)),
    );
    expect(tester.getSize(_button), const Size(64, 64));
    // 부채꼴의 번역 버튼은 따로 그리지 않아 두 개가 겹쳐 보이지 않는다.
    expect(
      find.descendant(of: tab, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(
      find.descendant(of: _button, matching: find.text('번역')),
      findsOneWidget,
    );
    expect(_tag, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('끌기 시작하면 누름이 바로 풀리고 그림자는 옅어지며 테두리가 짙어진다', (tester) async {
    await _mount(tester, capture: () {}, capturing: true, captureScreen: true);
    await _icon(tester);

    final gesture = await tester.startGesture(tester.getCenter(_current));
    await tester.pump();
    // 기준 8을 넘겨 15 올린다(p 0.1, 완전히 펼치는 거리 150).
    await gesture.moveBy(const Offset(0, -15));
    await tester.pump();

    final scale = tester
        .widget<Transform>(
          find.descendant(of: _button, matching: find.byType(Transform)).first,
        )
        .transform
        .storage[0];
    expect(scale, closeTo(1, .001));
    final decoration = _buttonDecoration(tester);
    expect(decoration.boxShadow!.single.color.a, closeTo(.12, .02));
    expect(decoration.border!.top.color.a, closeTo(.125, .02));
    // 촬영 고리는 옮겨 가는 안쪽 버튼을 따라가며 둘레 4의 간격을 유지한다.
    final button = tester.getRect(_button);
    final ring = tester.getRect(_ring);
    expect(ring.center, within(distance: .01, from: button.center));
    expect(ring.width - button.width, closeTo(8, .01));

    await gesture.up();
    // 촬영 고리가 계속 돌아 pumpAndSettle 대신 정해진 시간만 그린다.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('카메라 준비 전 흐린 버튼도 다 펼치면 부채꼴 선택 버튼과 같은 색이 된다', (tester) async {
    await _mount(tester, captureScreen: true);
    await tester.tap(_current);
    await tester.pumpAndSettle();
    await tester.drag(_current, const Offset(0, -150));
    await tester.pumpAndSettle();

    final decoration = _buttonDecoration(tester);
    expect(decoration.color!.a, closeTo(1, .001));
    expect(decoration.boxShadow, isNull);
    expect(decoration.border!.top.color.a, closeTo(.25, .001));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('글자 배율 1.3·2.0에서도 꼬리표가 없고 메뉴 원은 화면 내용 여백 아래에서 넘치지 않는다', (
    tester,
  ) async {
    for (final factor in [1.3, 2.0]) {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(factor),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: BottomTabBar(
                  tabs: _tabs,
                  selectedIndex: 2,
                  isHomeSelected: false,
                  onTabTap: (_) {},
                  onHomeTap: () {},
                  onCurrentScreenTap: () {},
                  isCaptureScreen: true,
                ),
              ),
            ),
          ),
        ),
      );
      await _icon(tester);
      _expectNoTag();
      final outer = tester.getRect(_background);
      expect(
        640 - outer.top,
        lessThanOrEqualTo(BottomMenuMetrics.contentClearance - 8),
      );
      expect(outer.left, greaterThanOrEqualTo(0));
      expect(outer.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('다크 테마는 바깥 원을 더 투명하게 하고 넘치지 않는다', (tester) async {
    for (final (theme, alpha) in [
      (ThemeData.light(), .72),
      (ThemeData.dark(), .60),
    ]) {
      await _mount(tester, capture: () {}, captureScreen: true, theme: theme);
      await _icon(tester);
      final background =
          tester.widget<DecoratedBox>(_background).decoration as BoxDecoration;
      expect(background.color!.a, closeTo(alpha, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('애니메이션 줄이기면 촬영 중에 고리 없이 멈춘 카메라 아이콘을 보인다', (tester) async {
    await _mount(
      tester,
      capture: () {},
      capturing: true,
      captureScreen: true,
      reduced: true,
    );
    await _icon(tester);

    // 촬영 중 표시 키는 고리 대신 안쪽 버튼의 카메라 아이콘이 쓴다.
    final shown = find.descendant(of: _button, matching: _ring);
    expect(shown, findsOneWidget);
    expect(tester.widget<Icon>(shown).icon, Icons.photo_camera);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    _expectNoTag();
    expect(_cameraOpacity(tester), closeTo(1, .001));
    await tester.pumpWidget(const SizedBox());
  });

  // 버그 수정: 애니메이션 줄이기 + 촬영 중이면 위치 없는 빈 위젯이 Stack에 들어가, 폭이 정해지지 않은
  // 부모(Align) 안에서 메뉴 전체가 크기 0으로 밀려났다.
  testWidgets('애니메이션 줄이기 + 촬영 중에도 폭이 정해지지 않은 부모 안에서 메뉴가 화면 가운데에 남는다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BottomTabBar(
              tabs: _tabs,
              selectedIndex: 2,
              isHomeSelected: false,
              onTabTap: (_) {},
              onHomeTap: () {},
              onCurrentScreenTap: () {},
              isCapturing: true,
              isCaptureScreen: true,
            ),
          ),
        ),
      ),
    );
    await _icon(tester);

    expect(tester.getRect(_background).center.dx, closeTo(160, .01));
    expect(tester.getSize(_background), const Size(74, 74));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // 버그 수정: 촬영 중에 끌면 p 0.2~0.4에서 고리도 아이콘도 없는 빈 원이 보였다.
  testWidgets('촬영 중에 끌면 고리가 사라지는 동안 카메라 아이콘이 나타나 빈 원이 되지 않는다', (tester) async {
    await _mount(tester, capture: () {}, capturing: true, captureScreen: true);
    await _icon(tester);

    final gesture = await tester.startGesture(tester.getCenter(_current));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -15)); // p 0.1: 고리 절반, 아이콘 절반
    await tester.pump();
    expect(_cameraOpacity(tester), closeTo(.5, .01));
    await gesture.moveBy(const Offset(0, -30)); // p 0.3: 고리 없음, 아이콘 전부
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_cameraOpacity(tester), closeTo(1, .01));

    await gesture.up();
    // 촬영 고리가 계속 돌아 pumpAndSettle 대신 정해진 시간만 그린다.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox());
  });

  // 버그 수정: 점으로 접히는 중에 누르면 촬영은 막지만 0.92배 누름 표시가 나왔다.
  testWidgets('점으로 접히는 중에 누르면 누름 표시를 하지 않는다', (tester) async {
    await _mount(tester, capture: () {}, captureScreen: true);
    await _icon(tester);
    await tester.tapAt(const Offset(20, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(_background).width, lessThan(74));
    expect(_button, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(_current));
    await tester.pump();
    final circle = (tester.getSize(_background).width - 10) / 64;
    final appear = ((circle - .6) / .4).clamp(0.0, 1.0);
    expect(_buttonScale(tester), closeTo(lerpDouble(.6, 1, appear)!, .001));
    expect(_buttonDecoration(tester).boxShadow, isNotNull);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
