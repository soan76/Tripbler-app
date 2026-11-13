import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/map/place_search_bar.dart';

class _Harness {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();
  final List<String> submitted = <String>[];
  int clearedCount = 0;
  int unavailableCount = 0;

  Widget build({
    PlaceSearchAvailability availability = PlaceSearchAvailability.ready,
    bool isSearching = false,
    double width = 400,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: PlaceSearchBar(
              controller: controller,
              focusNode: focusNode,
              availability: availability,
              isSearching: isSearching,
              onSubmitted: submitted.add,
              onCleared: () {
                clearedCount++;
                controller.clear();
              },
              onUnavailable: () => unavailableCount++,
            ),
          ),
        ),
      ),
    );
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

IconButton _searchButton(WidgetTester tester) {
  return tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.search),
  );
}

void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  testWidgets('검색어가 비었거나 공백뿐이면 검색 버튼이 꺼진다', (tester) async {
    await tester.pumpWidget(harness.build());

    expect(_searchButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(_searchButton(tester).onPressed, isNull);
  });

  testWidgets('검색 버튼과 키보드 검색 키로 제출한다', (tester) async {
    await tester.pumpWidget(harness.build());

    await tester.enterText(find.byType(TextField), '경복궁');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
    expect(harness.submitted, ['경복궁']);

    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(harness.submitted, ['경복궁', '경복궁']);
  });

  testWidgets('100자를 넘으면 안내를 보이고 버튼과 키보드 검색 키 모두 제출하지 않는다', (tester) async {
    await tester.pumpWidget(harness.build());

    // 입력과 수정은 막지 않는다.
    await tester.enterText(find.byType(TextField), '가' * 101);
    await tester.pump();

    expect(harness.controller.text, '가' * 101);
    expect(find.text(PlaceSearchBar.tooLongMessage), findsOneWidget);
    expect(_searchButton(tester).onPressed, isNull);

    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(harness.submitted, isEmpty);

    // 앞뒤 공백은 길이에 넣지 않는다(MapNotifier와 같은 기준).
    await tester.enterText(find.byType(TextField), '  ${'가' * 100}  ');
    await tester.pump();
    expect(find.text(PlaceSearchBar.tooLongMessage), findsNothing);
    expect(_searchButton(tester).onPressed, isNotNull);
  });

  testWidgets('X 버튼은 글자가 있을 때만 보이고 누르면 지운다', (tester) async {
    await tester.pumpWidget(harness.build());
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.enterText(find.byType(TextField), '경복궁');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(harness.clearedCount, 1);
    expect(harness.controller.text, isEmpty);
  });

  testWidgets('비로그인이면 검색창을 눌렀을 때 안내를 부르고 입력을 받지 않는다', (tester) async {
    await tester.pumpWidget(
      harness.build(availability: PlaceSearchAvailability.signedOut),
    );

    expect(find.text(PlaceSearchBar.signedOutHint), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(harness.unavailableCount, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(harness.submitted, isEmpty);
  });

  testWidgets('세션 복구 대기 중이면 입력은 받되 제출하면 검색하지 않고 안내를 부른다', (tester) async {
    await tester.pumpWidget(
      harness.build(availability: PlaceSearchAvailability.restorePending),
    );

    await tester.enterText(find.byType(TextField), '경복궁');
    await tester.pump();
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.search);

    expect(harness.submitted, isEmpty);
    expect(harness.unavailableCount, 1);
    expect(harness.controller.text, '경복궁');
  });

  testWidgets('검색 중에는 진행 표시를 보여준다', (tester) async {
    harness.controller.text = '경복궁';
    await tester.pumpWidget(harness.build(isSearching: true));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('폭 320에서 긴 입력과 안내 문구가 넘치지 않는다', (tester) async {
    harness.controller.text = '가' * 120;
    await tester.pumpWidget(harness.build(width: 320));

    expect(tester.takeException(), isNull);
  });

  testWidgets('둥근 채움 검색창: 테두리 없이 그림자, 검색 버튼은 강조색', (tester) async {
    await tester.pumpWidget(harness.build());
    await tester.enterText(find.byType(TextField), '라멘');
    await tester.pump();

    final colors = Theme.of(
      tester.element(find.byType(PlaceSearchBar)),
    ).colorScheme;
    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PlaceSearchBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.color, colors.surfaceContainerHighest);
    expect(surface.elevation, greaterThan(0));
    final shape = surface.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(28));
    expect(shape.side, BorderSide.none);
    // 한 줄 높이의 절반이 둥글기라 양 끝이 반원이다.
    expect(tester.getSize(find.byType(PlaceSearchBar)).height, 56);

    expect(_searchButton(tester).color, colors.primary);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
          .color,
      colors.onSurfaceVariant,
    );
  });
}
