import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show TranslationState;
import 'package:tripbler/widgets/navigation/bottom_menu_capture_marks.dart';
import 'package:tripbler/widgets/navigation/navigation_capture_controller.dart';
import 'package:tripbler/widgets/translation/photo/fake_translation_banner.dart';
import 'package:tripbler/widgets/translation/photo/photo_capture_view.dart';
import 'package:tripbler/widgets/translation/photo/photo_language_pill.dart';

// 사진 번역 촬영 화면의 목업(docs/mockups/translation-camera.html) 배치:
// 위 "Tripbler"·언어 막대, 하단 메뉴 원 양옆의 사진 고르기·플래시. 촬영 안내·전송 안내 문구는
// 2026-11-27 사용자 요청으로 없앴고, 가짜 모드면 가짜 띠만 메뉴 원 위에 보인다.
void main() {
  final languages = const TranslationState().languages;
  const screen = Size(320, 640);

  Future<({List<String> sources, List<String> targets})> pumpView(
    WidgetTester tester, {
    String source = 'auto',
    String target = 'ko',
    double textScale = 1,
    bool fakeMode = false,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final capture = NavigationCaptureController();
    addTearDown(capture.dispose);
    final sources = <String>[], targets = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: PhotoCaptureView(
            navigationCapture: capture,
            cameraController: null,
            isCameraReady: true,
            isFlashOn: false,
            isCapturing: false,
            sourceLanguageCode: source,
            targetLanguageCode: target,
            languages: languages,
            onSourceLanguageChanged: sources.add,
            onTargetLanguageChanged: targets.add,
            onToggleFlash: () {},
            onCapture: () {},
            onPickFromGallery: () {},
            fakeMode: fakeMode,
          ),
        ),
      ),
    );
    return (sources: sources, targets: targets);
  }

  testWidgets('위에 Tripbler와 언어 막대가 있고, 안내 문구와 셔터는 없다', (tester) async {
    await pumpView(tester);

    expect(find.text(PhotoCaptureView.brand), findsOneWidget);
    expect(find.text('자동 감지'), findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);
    expect(find.textContaining('촬영해요'), findsNothing);
    expect(find.textContaining('전송'), findsNothing);
    expect(find.textContaining('기기에서'), findsNothing);
    expect(find.byType(FakeTranslationBanner), findsNothing);
    // 촬영은 하단 메뉴가 맡는다.
    expect(find.byTooltip(PhotoCaptureView.shutterTooltip), findsNothing);
  });

  testWidgets('가짜 모드 띠는 하단 메뉴 원 위(화면 내용 여백)에 있고 글자 배율 2에서도 넘치지 않는다', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await pumpView(tester, fakeMode: true, textScale: scale);
      expect(tester.takeException(), isNull);

      final banner = tester.getRect(find.byType(FakeTranslationBanner));
      final menuTop =
          screen.height -
          BottomMenuMetrics.outerBottom -
          BottomMenuMetrics.outerSize;
      expect(
        screen.height - banner.bottom,
        closeTo(BottomMenuMetrics.contentClearance, .01),
      );
      expect(banner.bottom, lessThan(menuTop));
      expect(banner.left, greaterThanOrEqualTo(0));
      expect(banner.right, lessThanOrEqualTo(screen.width));
      // 띠는 위의 언어 막대와 겹치지 않는다.
      final pill = tester.getRect(find.byType(PhotoLanguagePill));
      expect(pill.bottom, lessThanOrEqualTo(banner.top));
    }
  });

  testWidgets('사진 고르기와 플래시는 하단 메뉴 원과 같은 높이의 양옆에 있고 원과 겹치지 않는다', (tester) async {
    await pumpView(tester);

    final gallery = tester.getRect(
      find.byTooltip(PhotoCaptureView.galleryTooltip),
    );
    final flash = tester.getRect(
      find.byTooltip(PhotoCaptureView.flashOnTooltip),
    );
    final menuCenterY = screen.height - BottomMenuMetrics.iconCenter.dy;
    expect(gallery.center.dy, closeTo(menuCenterY, .01));
    expect(flash.center.dy, closeTo(menuCenterY, .01));
    expect(gallery.size, const Size(48, 48));

    final menu = Rect.fromCircle(
      center: Offset(screen.width / 2, menuCenterY),
      radius: BottomMenuMetrics.outerSize / 2,
    );
    expect(gallery.right, lessThan(menu.left));
    expect(flash.left, greaterThan(menu.right));
    expect(gallery.left, greaterThanOrEqualTo(0));
    expect(flash.right, lessThanOrEqualTo(screen.width));
  });

  testWidgets('언어 막대 양쪽을 누르면 언어 목록이 올라오고 고른 언어를 알린다', (tester) async {
    final calls = await pumpView(tester);

    await tester.tap(
      find.bySemanticsLabel('${PhotoLanguagePill.sourceLabel}: 자동 감지'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '일본어'));
    await tester.pumpAndSettle();
    expect(calls.sources, ['ja']);

    await tester.tap(
      find.bySemanticsLabel('${PhotoLanguagePill.targetLabel}: 한국어'),
    );
    await tester.pumpAndSettle();
    // 번역 언어 목록에는 자동 감지가 없다.
    expect(find.widgetWithText(ListTile, '자동 감지'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '영어'));
    await tester.pumpAndSettle();
    expect(calls.targets, ['en']);
  });

  testWidgets('원문이 자동 감지면 바꾸기를 막고, 아니면 두 언어를 바꾼다', (tester) async {
    await pumpView(tester);
    final swap = find.byTooltip(PhotoLanguagePill.swapTooltip);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: swap, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );

    final calls = await pumpView(tester, source: 'ja', target: 'ko');
    await tester.tap(swap);
    await tester.pump();
    expect(calls.sources, ['ko']);
    expect(calls.targets, ['ja']);
  });

  testWidgets('폭 320에서 글자 배율 1.3·2.0이어도 넘치지 않고 언어 막대는 화면 안에 있다', (
    tester,
  ) async {
    for (final scale in [1.3, 2.0]) {
      await pumpView(tester, textScale: scale);
      expect(tester.takeException(), isNull);
      final pill = tester.getRect(find.byType(PhotoLanguagePill));
      expect(pill.left, greaterThanOrEqualTo(0));
      expect(pill.right, lessThanOrEqualTo(screen.width));
    }
  });

  testWidgets('언어 목록은 앱 테마의 밝은 판(모서리 4)이고 고른 언어에 체크가 있다', (tester) async {
    await pumpView(tester, source: 'ja');
    await tester.tap(
      find.bySemanticsLabel('${PhotoLanguagePill.sourceLabel}: 일본어'),
    );
    await tester.pumpAndSettle();

    final light = AppTheme.lightTheme.colorScheme;
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, light.surface);
    expect(
      sheet.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.cornerRadius),
        ),
      ),
    );
    final selected = find.widgetWithText(ListTile, '일본어');
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('일본어').last).style?.color,
      light.primary,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '영어'),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
  });

  testWidgets('글자 배율이 커져도 Tripbler와 언어 막대가 겹치지 않는다', (tester) async {
    for (final scale in [1.0, 2.0]) {
      await pumpView(tester, textScale: scale);
      final brand = tester.getRect(find.text(PhotoCaptureView.brand));
      final pill = tester.getRect(find.byType(PhotoLanguagePill));
      expect(brand.bottom, lessThanOrEqualTo(pill.top));
    }
  });
}
