import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/widgets/translation/photo/photo_consent_dialog.dart';

// 사진 전송 동의 대화상자: 안내 문구, 동의는 한 번만 알리고 취소·뒤로가기·바깥 누르기는 취소로 본다.
void main() {
  late int accepted;
  late int cancelled;

  Future<void> openDialog(WidgetTester tester) async {
    accepted = 0;
    cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPhotoConsentDialog(
                context,
                onAccept: () => accepted++,
                onCancel: () => cancelled++,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('정확한 안내 문구와 두 버튼을 보여 준다', (tester) async {
    await openDialog(tester);

    expect(
      find.text('번역을 위해 촬영한 사진과 인식된 글자를 Tripbler 서버 및 AI 제공업체에 전송합니다.'),
      findsOneWidget,
    );
    expect(find.text('동의하고 번역'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
  });

  testWidgets('동의하고 번역을 누르면 동의 콜백을 한 번 부르고 닫는다', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('동의하고 번역'));
    await tester.pumpAndSettle();

    expect(accepted, 1);
    expect(cancelled, 0);
    expect(find.byType(PhotoConsentDialog), findsNothing);
  });

  testWidgets('취소를 누르면 취소 콜백을 부른다', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(accepted, 0);
    expect(cancelled, 1);
  });

  testWidgets('뒤로가기도 취소로 본다', (tester) async {
    await openDialog(tester);

    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(accepted, 0);
    expect(cancelled, 1);
  });

  testWidgets('바깥을 눌러도 취소로 본다', (tester) async {
    await openDialog(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(accepted, 0);
    expect(cancelled, 1);
  });

  testWidgets('작은 화면·글자 배율 2에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await openDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('동의하고 번역'), findsOneWidget);
  });
}
