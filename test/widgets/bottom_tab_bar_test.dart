import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/tab_item.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';

import '../helpers/bottom_menu_background.dart';

const _tabs = [
  TabItem(label: '환율', icon: Icons.attach_money),
  TabItem(label: '지도', icon: Icons.map),
  TabItem(label: '번역', icon: Icons.translate),
];
final _current = find.byKey(const ValueKey('bottom-menu-current'));
final _background = find.byKey(const ValueKey('bottom-menu-background'));

Future<void> _mount(
  WidgetTester tester, {
  VoidCallback? capture,
  bool capturing = false,
  bool captureScreen = false,
  ValueChanged<int>? select,
  VoidCallback? home,
  ValueChanged<double>? expansion,
  bool reduced = false,
  double textScale = 1,
  double width = 320,
  GestureDragUpdateCallback? underlyingDrag,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          disableAnimations: reduced,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: underlyingDrag,
                  child: const SizedBox.expand(),
                ),
              ),
              // 메인 화면처럼 메뉴가 화면 전체를 받는다(펼친 배경이 화면 전체로 커진다).
              Positioned.fill(
                child: BottomTabBar(
                  tabs: _tabs,
                  selectedIndex: 2,
                  isHomeSelected: false,
                  onTabTap: select ?? (_) {},
                  onHomeTap: home ?? () {},
                  onCurrentScreenTap: capture,
                  isCapturing: capturing,
                  isCaptureScreen: captureScreen,
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
  await tester.tap(_current);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await _icon(tester);
  await tester.drag(_current, const Offset(0, -150));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('점 누르기는 촬영하지 않고 아이콘 누르기만 촬영한다', (tester) async {
    var captures = 0;
    await _mount(tester, capture: () => captures++);
    expect(tester.getSize(_background).width, 10);
    await _icon(tester);
    expect(captures, 0);
    expect(tester.getSize(_background).width, 74);
    await tester.tap(_current);
    await tester.pump();
    expect(captures, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('8px 이상 수평 이동도 촬영하지 않는다', (tester) async {
    var captures = 0;
    await _mount(tester, capture: () => captures++);
    await _icon(tester);
    await tester.drag(_current, const Offset(12, 0));
    await tester.pumpAndSettle();
    expect(captures, 0);
    expect(tester.getSize(_background).width, 74);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('드래그 진행률에 맞춰 같은 배경이 변하고 촬영하지 않는다', (tester) async {
    var captures = 0;
    var progress = 0.0;
    await _mount(
      tester,
      capture: () => captures++,
      expansion: (p) => progress = p,
    );
    await _icon(tester);
    final gesture = await tester.startGesture(tester.getCenter(_current));
    // 완전히 펼치는 거리 150의 절반.
    await gesture.moveBy(const Offset(0, -75));
    await tester.pump();
    expect(progress, closeTo(.5, .001));
    // 반지름은 바깥 원 37에서 화면 모서리까지 거리(중심 아래 49 기준 +2)로 smoothstep(0.5)=0.5만큼 커진다.
    final reach = math.sqrt(160 * 160 + math.pow(640 - 49, 2)) + 2;
    expect(tester.getSize(_background).width, closeTo(37 + reach, .1));
    expect(tester.getSize(_background).height, closeTo(37 + reach, .1));
    expect(bottomMenuBackgroundCoversArea(tester), isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expectBottomMenuBackgroundCoversArea(tester);
    expect(captures, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('짧고 느린 드래그는 원형, 빠른 드래그는 부채꼴', (tester) async {
    await _mount(tester);
    await _icon(tester);
    await tester.timedDrag(
      _current,
      const Offset(0, -24),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(_background).width, 74);
    await tester.fling(_current, const Offset(0, -30), 1000);
    await tester.pumpAndSettle();
    expectBottomMenuBackgroundCoversArea(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('현재 탭은 접기만 하고 다른 탭과 AI는 명시적으로 이동한다', (tester) async {
    final selections = <int>[];
    var home = 0;
    await _mount(tester, select: selections.add, home: () => home++);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('bottom-menu-tab-2')));
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(home, 0);
    expect(tester.getSize(_background).width, 10);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('bottom-menu-tab-0')));
    await tester.pumpAndSettle();
    expect(selections, [0]);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('bottom-menu-tab--1')));
    await tester.pumpAndSettle();
    expect(home, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('4초 무입력과 바깥 누르기는 점으로 접는다', (tester) async {
    await _mount(tester);
    await _icon(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.getSize(_background).width, 10);
    await _open(tester);
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(tester.getSize(_background).width, 10);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320 폭 큰 글자와 애니메이션 줄이기 및 접근성 펼치기', (tester) async {
    // 테스트 프레임워크가 tearDown 전에 SemanticsHandle 정리를 검사하므로 본문 끝에서 닫는다.
    final semantics = tester.ensureSemantics();
    await _mount(tester, reduced: true, textScale: 2);
    await _icon(tester);
    final node = tester.getSemantics(_current);
    final actions = node.getSemanticsData().customSemanticsActionIds!;
    final expand = actions.firstWhere(
      (id) => CustomSemanticsAction.getAction(id)?.label == '메뉴 펼치기',
    );
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      expand,
    );
    await tester.pump();
    expectBottomMenuBackgroundCoversArea(tester);
    expect(tester.takeException(), isNull);
    for (final index in [-1, 0, 1, 2]) {
      final rect = tester.getRect(
        find.byKey(ValueKey('bottom-menu-tab-$index')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('메뉴 밖 드래그는 사진에 전달하고 안쪽은 메뉴만 움직인다', (tester) async {
    var underlying = 0;
    await _mount(tester, underlyingDrag: (_) => underlying++);
    await _icon(tester);
    await tester.dragFrom(const Offset(20, 600), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(underlying, greaterThan(0));
    underlying = 0;
    await _open(tester);
    await tester.dragFrom(const Offset(160, 540), const Offset(0, 110));
    await tester.pumpAndSettle();
    expect(underlying, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('점으로 접히는 도중 아이콘 자리를 눌러도 촬영하지 않고 아이콘으로 돌아온다', (tester) async {
    var captures = 0;
    await _mount(tester, capture: () => captures++);
    await _icon(tester);
    // 바깥 누르기로 접기 시작(원형이 점으로 줄어드는 약 160ms 안).
    await tester.tapAt(const Offset(20, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(_background).width, lessThan(74));
    await tester.tap(_current);
    await tester.pumpAndSettle();
    expect(captures, 0);
    expect(tester.getSize(_background).width, 74);
    // 아이콘 상태가 된 뒤의 누르기는 촬영한다.
    await tester.tap(_current);
    await tester.pump();
    expect(captures, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('촬영 중이면 아이콘 자리에 진행 표시를 보이고 낭독 문구가 바뀐다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester, capture: () {}, capturing: true, captureScreen: true);
    // 진행 표시가 계속 움직이므로 pumpAndSettle 대신 정해진 시간만 그린다.
    await tester.tap(_current);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('bottom-menu-capturing')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 꼬리표("눌러서 촬영"/"찍는 중")는 2026-11-27 사용자 요청으로 없앴다. 촬영 중은 고리와 낭독으로 알린다.
    expect(find.text('눌러서 촬영'), findsNothing);
    expect(find.text('찍는 중'), findsNothing);
    final data = tester.getSemantics(_current).getSemanticsData();
    expect(data.label, '현재 화면: 번역, 사진 찍는 중');
    expect(data.hint, isNot(contains('촬영')));

    await _mount(tester, capture: () {}, captureScreen: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('bottom-menu-capturing')), findsNothing);
    expect(tester.getSemantics(_current).getSemanticsData().label, '현재 화면: 번역');
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('애니메이션 줄이기면 촬영 중 표시가 돌지 않는 아이콘이다', (tester) async {
    await _mount(
      tester,
      capture: () {},
      capturing: true,
      captureScreen: true,
      reduced: true,
    );
    await tester.tap(_current);
    await tester.pump();
    expect(find.byKey(const ValueKey('bottom-menu-capturing')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    expect(find.text('찍는 중'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('촬영 중에는 4초 무입력으로 접지 않고, 끝나면 그때부터 4초를 센다', (tester) async {
    await _mount(tester, capture: () {}, capturing: true);
    await tester.tap(_current);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(_background).width, 74);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getSize(_background).width, 74);

    await _mount(tester, capture: () {});
    await tester.pump(const Duration(milliseconds: 3900));
    expect(tester.getSize(_background).width, 74);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(tester.getSize(_background).width, 10);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('아이콘 상태에서 촬영이 시작되면 남은 무입력 타이머를 멈춘다', (tester) async {
    await _mount(tester, capture: () {});
    await _icon(tester);
    await tester.pump(const Duration(seconds: 3));
    await _mount(tester, capture: () {}, capturing: true);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getSize(_background).width, 74);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('펼치는 애니메이션 도중 다시 잡아 반대로 끌면 그 자리에서 이어진다', (tester) async {
    var progress = 0.0;
    await _mount(tester, expansion: (p) => progress = p);
    await _icon(tester);
    final first = await tester.startGesture(tester.getCenter(_current));
    await first.moveBy(const Offset(0, -75));
    await tester.pump();
    await first.up();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final settling = progress;
    expect(settling, inExclusiveRange(.5, .9));

    // 버튼은 아직 눌리지 않는 진행률이라 배경 안의 화면 아래쪽 가운데를 잡는다
    // (배경 원은 이미 화면 아래 끝보다 커져 있다).
    final second = await tester.startGesture(const Offset(160, 637));
    await tester.pump(const Duration(milliseconds: 16));
    expect(progress, closeTo(settling, .0001));
    await second.moveBy(const Offset(0, 12));
    await tester.pump();
    expect(progress, closeTo(settling - 12 / 150, .0001));
    await second.moveBy(const Offset(0, 24));
    await tester.pump();
    expect(progress, closeTo(settling - 36 / 150, .0001));
    await second.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('천천히 놓을 때 진행률 0.35부터 펼치고 그 아래는 원형으로 돌아온다', (tester) async {
    await _mount(tester);
    await _icon(tester);
    await tester.timedDrag(
      _current,
      // 0.35 × 150 = 52.5. 52는 0.347, 53은 0.353이다.
      const Offset(0, -52),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(_background).width, 74);

    await tester.timedDrag(
      _current,
      const Offset(0, -53),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expectBottomMenuBackgroundCoversArea(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('점·아이콘·메뉴 버튼의 터치 영역은 48dp 이상이다', (tester) async {
    await _mount(tester);
    final dot = tester.getSize(_current);
    expect(dot.width, greaterThanOrEqualTo(48));
    expect(dot.height, greaterThanOrEqualTo(48));
    await _icon(tester);
    expect(tester.getSize(_current).shortestSide, greaterThanOrEqualTo(48));
    await tester.drag(_current, const Offset(0, -150));
    await tester.pumpAndSettle();
    for (final index in [-1, 0, 1, 2]) {
      final size = tester.getSize(
        find.byKey(ValueKey('bottom-menu-tab-$index')),
      );
      expect(size.shortestSide, greaterThanOrEqualTo(48));
    }
    await tester.pumpWidget(const SizedBox());
  });
}
