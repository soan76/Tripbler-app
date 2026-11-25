import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/widgets/translation/translation_box_overlay.dart';

// 번역 상자 덮어 그리기: 넘침 없이 그리기, 낭독기 안내, 문단 배치, 다시 배치 조건.
void main() {
  Future<void> pumpOverlay(
    WidgetTester tester,
    List<TranslationBox> boxes, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 1000),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 400,
                child: TranslationBoxOverlay(boxes: boxes),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('아주 작은 상자·긴 번역·가장자리 상자도 오류 없이 그리고 낭독기에 번역을 알린다', (tester) async {
    await pumpOverlay(tester, [
      (box: const Rect.fromLTWH(10, 10, 40, 4), lineCount: 1, translated: '라멘'),
      (
        box: const Rect.fromLTWH(250, 380, 48, 8),
        lineCount: 1,
        translated: '아주 긴 번역 문장이 작은 상자에 들어가지 않는 경우',
      ),
      (
        box: const Rect.fromLTWH(20, 100, 200, 40),
        lineCount: 2,
        translated: '영업 중',
      ),
    ], textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(RegExp('번역\n라멘\n아주 긴 번역')), findsOneWidget);
  });

  testWidgets('번역이 없으면 아무것도 그리지 않는다', (tester) async {
    await pumpOverlay(tester, const []);

    expect(
      find.descendant(
        of: find.byType(TranslationBoxOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('문단 번역은 원문 영역 폭 안에서 줄바꿈해 그 영역을 덮는다', (tester) async {
    const area = Rect.fromLTWH(20, 40, 200, 60);
    await pumpOverlay(tester, [
      (box: area, lineCount: 3, translated: '이것은 세 줄짜리 문단을 한국어로 옮긴 번역입니다.'),
    ]);

    final box = debugTranslationBoxes.single;
    expect(box.left, lessThanOrEqualTo(area.left));
    expect(box.top, lessThanOrEqualTo(area.top));
    expect(box.right, greaterThanOrEqualTo(area.right));
    expect(box.bottom, greaterThanOrEqualTo(area.bottom));
    // 영역에 들어가므로 넓히지 않는다(테두리 1만 둔다).
    expect(box.width, lessThanOrEqualTo(area.width + 2));
    expect(box.height, lessThanOrEqualTo(area.height + 2));
  });

  testWidgets('번역이 영역에 들어가지 않으면 빈 곳까지만 넓히고, 아래 상자를 가리지 않게 말줄임한다', (
    tester,
  ) async {
    const upper = Rect.fromLTWH(20, 40, 120, 16);
    const lower = Rect.fromLTWH(20, 70, 120, 16);
    const right = Rect.fromLTWH(150, 40, 100, 16);
    await pumpOverlay(tester, [
      (
        box: upper,
        lineCount: 1,
        translated: '아주 길게 늘어진 번역 문장이 원문 영역에 도저히 들어가지 않는 경우를 확인합니다',
      ),
      (box: right, lineCount: 1, translated: '옆'),
      (box: lower, lineCount: 1, translated: '아래'),
    ]);

    expect(tester.takeException(), isNull);
    final boxes = debugTranslationBoxes;
    expect(boxes, hasLength(3));
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        final overlap = boxes[i].intersect(boxes[j]);
        expect(
          overlap.width <= 0 || overlap.height <= 0,
          isTrue,
          reason: '${boxes[i]}와 ${boxes[j]}가 겹친다',
        );
      }
    }
    // 위 상자는 아래로 넓어졌지만 아래 상자 위에서 멈춘다.
    expect(boxes[0].height, greaterThan(upper.height));
    expect(boxes[0].bottom, lessThanOrEqualTo(lower.top));
  });

  testWidgets('같은 번역 목록이면 다시 배치하지 않고, 목록이 바뀌면 다시 배치한다', (tester) async {
    final boxes = <TranslationBox>[
      (
        box: const Rect.fromLTWH(20, 40, 200, 20),
        lineCount: 1,
        translated: '라멘',
      ),
    ];
    await pumpOverlay(tester, boxes);
    final afterFirst = debugTranslationBoxLayoutCount;

    await pumpOverlay(tester, boxes);
    expect(debugTranslationBoxLayoutCount, afterFirst);

    await pumpOverlay(tester, [...boxes]);
    expect(debugTranslationBoxLayoutCount, afterFirst + 1);
  });
}
