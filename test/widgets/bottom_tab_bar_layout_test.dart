import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/tab_item.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';

// 폭 320 화면에서 부채꼴 버튼 자리와 큰 글자 배치. 메뉴 동작은 bottom_tab_bar_test.dart에 있다.

const _tabs = [
  TabItem(label: '환율', icon: Icons.attach_money),
  TabItem(label: '지도', icon: Icons.map),
  TabItem(label: '번역', icon: Icons.translate),
];
final _current = find.byKey(const ValueKey('bottom-menu-current'));
final _currentButton = find.byKey(const ValueKey('bottom-menu-current-button'));

Future<void> _mount(
  WidgetTester tester, {
  VoidCallback? capture,
  bool captureScreen = false,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 640),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomTabBar(
                  tabs: _tabs,
                  selectedIndex: 2,
                  isHomeSelected: false,
                  onTabTap: (_) {},
                  onHomeTap: () {},
                  onCurrentScreenTap: capture,
                  isCaptureScreen: captureScreen,
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
  testWidgets('320 폭 부채꼴: 설계 자리·크기에 놓이고 화면 안이며, 지도와 AI는 겹치지 않는다', (
    tester,
  ) async {
    // 버튼 중심(하단 가운데 기준): 환율(-93, 72) 지도(0, 122) 번역(+93, 72) AI(0, 42).
    // 펼친 배경은 화면 전체로 커지므로(bottom-nav.md 10-3절) 기준점은 메뉴 영역의 하단 가운데다.
    const expected = {
      0: Offset(-93, 72),
      1: Offset(0, 122),
      2: Offset(93, 72),
      -1: Offset(0, 42),
    };
    for (final textScale in [1.0, 1.3, 2.0]) {
      await _mount(tester, textScale: textScale);
      await _open(tester);
      final origin = tester.getRect(find.byType(BottomTabBar)).bottomCenter;
      final tabs = <int, Rect>{}, labels = <int, Rect>{};
      for (final MapEntry(key: index, value: center) in expected.entries) {
        final key = find.byKey(ValueKey('bottom-menu-tab-$index'));
        final rect = tabs[index] = tester.getRect(key);
        expect(
          rect.center - origin,
          within(distance: .01, from: center.scale(1, -1)),
        );
        expect(rect.size, Size.square(index == -1 ? 76 : 64), reason: '$index');
        // 버튼 원은 320×640 화면 안이다.
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$index');
        expect(rect.right, lessThanOrEqualTo(320), reason: '$index');
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$index');
        expect(rect.bottom, lessThanOrEqualTo(640), reason: '$index');
        // 현재 화면(번역) 버튼의 이름은 아이콘 상태에서 옮겨 온 안쪽 버튼이 그린다.
        final label = labels[index] = tester.getRect(
          find.descendant(
            of: index == 2 ? _currentButton : key,
            matching: find.text(index == -1 ? 'AI' : _tabs[index].label),
          ),
        );
        // 이름표는 자기 버튼 원의 테두리 상자 안에 들어간다(큰 글자에서도 줄여 맞춘다).
        expect(rect.inflate(.01).contains(label.topLeft), isTrue);
        expect(rect.inflate(.01).contains(label.bottomRight), isTrue);
      }
      // 지도 원과 이름표는 AI 원과 겹치지 않는다.
      final distance = (tabs[1]!.center - tabs[-1]!.center).distance;
      expect(distance, greaterThanOrEqualTo(32 + 38));
      expect(labels[1]!.bottom, lessThanOrEqualTo(tabs[-1]!.top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('320 폭 글자 배율 1.3에서 넘치거나 잘리지 않는다', (tester) async {
    await _mount(tester, capture: () {}, captureScreen: true, textScale: 1.3);
    await _icon(tester);
    expect(tester.takeException(), isNull);
    // 촬영 화면 아이콘은 보이고, 꼬리표("눌러서 촬영")는 2026-11-27 사용자 요청으로 없앴다.
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    expect(find.text('눌러서 촬영'), findsNothing);
    final button = tester.getRect(_current);
    expect(button.left, greaterThanOrEqualTo(0));
    expect(button.right, lessThanOrEqualTo(320));
    expect(button.bottom, lessThanOrEqualTo(640));
    await tester.drag(_current, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final index in [-1, 0, 1, 2]) {
      final rect = tester.getRect(
        find.byKey(ValueKey('bottom-menu-tab-$index')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    await tester.pumpWidget(const SizedBox());
  });
}
