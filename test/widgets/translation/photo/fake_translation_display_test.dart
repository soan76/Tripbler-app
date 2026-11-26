import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/providers/translation/photo_translation_state.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show TranslationState;
import 'package:tripbler/services/photo_normalizer.dart';
import 'package:tripbler/widgets/translation/photo/fake_translation_banner.dart';
import 'package:tripbler/widgets/translation/photo/paragraph_detail_sheet.dart';
import 'package:tripbler/widgets/translation/photo/photo_capture_view.dart';
import 'package:tripbler/widgets/translation/photo/photo_result_view.dart';
import 'package:tripbler/widgets/translation/translation_box_overlay.dart';

// 개발용 가짜 번역 표시: 촬영·결과·상세 화면에 가짜임을 알리고, 실제 결과에는 보이지 않는다.
void main() {
  const paragraph = TranslatedParagraph(
    id: 'p1',
    original: 'ラーメン',
    translated: '[가짜] p1 번역',
    uncertain: false,
    source: PhotoTranslationSource.ai,
  );

  PhotoTranslationState completed({required bool simulated}) {
    return PhotoTranslationState(
      status: PhotoTranslationStatus.completed,
      photo: const NormalizedPhoto(
        path: 'tmp/p.jpg',
        width: 1000,
        height: 1500,
      ),
      paragraphs: const [
        OcrParagraph(
          id: 'p1',
          text: 'ラーメン',
          box: Rect.fromLTWH(200, 300, 400, 100),
          lineCount: 1,
        ),
      ],
      result: PhotoTranslationResult(
        sourceLanguageCode: 'ja',
        targetLanguageCode: 'ko',
        paragraphs: const [paragraph],
        simulated: simulated,
      ),
    );
  }

  Offset boxCenter(WidgetTester tester) => tester
      .renderObject<RenderBox>(find.byType(TranslationBoxOverlay))
      .localToGlobal(debugTranslationBoxes.single.center);

  Future<void> pumpResult(
    WidgetTester tester,
    PhotoTranslationState state,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: PhotoResultView(
            state: state,
            onRetake: () {},
            onRetry: () {},
            onToggleOriginal: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('simulatedResult_showsFakeBanner_andDetailSheetBanner', (
    tester,
  ) async {
    await pumpResult(tester, completed(simulated: true));

    expect(find.text(FakeTranslationBanner.resultMessage), findsOneWidget);
    expect(
      find.bySemanticsLabel(FakeTranslationBanner.resultMessage),
      findsOneWidget,
    );

    await tester.tapAt(boxCenter(tester));
    await tester.pumpAndSettle();

    expect(find.byType(ParagraphDetailSheet), findsOneWidget);
    expect(find.text(FakeTranslationBanner.detailMessage), findsOneWidget);
  });

  testWidgets('serverResult_hasNoFakeBanner', (tester) async {
    await pumpResult(tester, completed(simulated: false));

    expect(find.byType(FakeTranslationBanner), findsNothing);

    await tester.tapAt(boxCenter(tester));
    await tester.pumpAndSettle();

    expect(find.byType(ParagraphDetailSheet), findsOneWidget);
    expect(find.byType(FakeTranslationBanner), findsNothing);
  });

  testWidgets('captureView_fakeMode_replacesUploadNotice', (tester) async {
    Future<void> pump({required bool fakeMode}) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: PhotoCaptureView(
              cameraController: null,
              isCameraReady: true,
              isFlashOn: false,
              isCapturing: false,
              sourceLanguageCode: 'auto',
              targetLanguageCode: 'ko',
              languages: const TranslationState().languages,
              onSourceLanguageChanged: (_) {},
              onTargetLanguageChanged: (_) {},
              onToggleFlash: () {},
              onCapture: () {},
              onPickFromGallery: () {},
              fakeMode: fakeMode,
            ),
          ),
        ),
      );
    }

    await pump(fakeMode: true);
    expect(find.text(FakeTranslationBanner.captureMessage), findsOneWidget);
    expect(find.text(PhotoCaptureView.notice), findsNothing);

    await pump(fakeMode: false);
    expect(find.byType(FakeTranslationBanner), findsNothing);
    expect(find.text(PhotoCaptureView.notice), findsOneWidget);
  });

  testWidgets('banner_smallScreenLargeText_noOverflow_inDarkAndLight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: Column(
              children: [
                FakeTranslationBanner(
                  message: FakeTranslationBanner.captureMessage,
                ),
                FakeTranslationBanner(
                  message: FakeTranslationBanner.resultMessage,
                ),
                FakeTranslationBanner(
                  message: FakeTranslationBanner.detailMessage,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
