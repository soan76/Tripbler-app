import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/providers/translation/photo_translation_state.dart';
import 'package:tripbler/services/photo_normalizer.dart';
import 'package:tripbler/widgets/translation/photo/paragraph_detail_sheet.dart';
import 'package:tripbler/widgets/translation/photo/photo_result_view.dart';
import 'package:tripbler/widgets/translation/translation_box_overlay.dart';

// 사진 번역 결과 화면: 사진과 상자가 함께 움직이기, 상자 누르기, 원문 보기, 안내 줄, 진행·실패.
void main() {
  const portrait = NormalizedPhoto(
    path: 'tmp/p.jpg',
    width: 1000,
    height: 1500,
  );
  const landscape = NormalizedPhoto(
    path: 'tmp/l.jpg',
    width: 1600,
    height: 900,
  );

  TranslatedParagraph translated(
    String id,
    String text, {
    bool uncertain = false,
    PhotoTranslationSource source = PhotoTranslationSource.ai,
    String? pronunciation,
    List<PhotoPrice> prices = const [],
  }) {
    return TranslatedParagraph(
      id: id,
      original: '원문 $id',
      translated: text,
      uncertain: uncertain,
      source: source,
      pronunciation: pronunciation,
      prices: prices,
    );
  }

  PhotoTranslationState completed({
    NormalizedPhoto photo = portrait,
    List<OcrParagraph>? paragraphs,
    List<TranslatedParagraph>? results,
    int omittedCount = 0,
    bool showOriginal = false,
  }) {
    final ocr =
        paragraphs ??
        const [
          OcrParagraph(
            id: 'p1',
            text: 'ラーメン',
            box: Rect.fromLTWH(200, 300, 400, 100),
          ),
        ];
    return PhotoTranslationState(
      status: PhotoTranslationStatus.completed,
      photo: photo,
      paragraphs: ocr,
      omittedCount: omittedCount,
      showOriginal: showOriginal,
      result: PhotoTranslationResult(
        sourceLanguageCode: 'ja',
        targetLanguageCode: 'ko',
        paragraphs: results ?? [translated('p1', '라멘')],
      ),
    );
  }

  late int retakes;
  late int retries;
  late int toggles;

  Future<void> pumpView(
    WidgetTester tester,
    PhotoTranslationState state, {
    TransformationController? controller,
    Size size = const Size(400, 800),
    double textScale = 1,
  }) async {
    retakes = 0;
    retries = 0;
    toggles = 0;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: PhotoResultView(
            state: state,
            transformationController: controller,
            onRetake: () => retakes++,
            onRetry: () => retries++,
            onToggleOriginal: () => toggles++,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 사진 속 원문 사각형의 중심이 화면에서 놓일 전역 위치(맞춘 배율 → 확대·이동 행렬 → 전역).
  Offset expectedGlobalCenter(
    WidgetTester tester,
    NormalizedPhoto photo,
    Rect photoRect,
    Matrix4 matrix,
  ) {
    final viewer = tester.renderObject<RenderBox>(
      find.byType(InteractiveViewer),
    );
    final view = viewer.size;
    final fit = [
      view.width / photo.width,
      view.height / photo.height,
    ].reduce((a, b) => a < b ? a : b);
    final fitted = Size(photo.width * fit, photo.height * fit);
    final origin = Offset(
      (view.width - fitted.width) / 2,
      (view.height - fitted.height) / 2,
    );
    final inViewer = origin + photoRect.center * fit;
    return viewer.localToGlobal(MatrixUtils.transformPoint(matrix, inViewer));
  }

  Offset placedBoxGlobalCenter(WidgetTester tester, int index) {
    final overlay = tester.renderObject<RenderBox>(
      find.byType(TranslationBoxOverlay),
    );
    return overlay.localToGlobal(debugTranslationBoxes[index].center);
  }

  Future<void> expectBoxesFollowPhoto(
    WidgetTester tester,
    NormalizedPhoto photo,
    Rect photoRect,
  ) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    await pumpView(
      tester,
      completed(
        photo: photo,
        paragraphs: [OcrParagraph(id: 'p1', text: 'ラーメン', box: photoRect)],
      ),
      controller: controller,
    );

    final matrix = Matrix4.translationValues(-60, -90, 0)
      ..multiply(Matrix4.diagonal3Values(2, 2, 1));
    controller.value = matrix;
    await tester.pump();

    final expected = expectedGlobalCenter(tester, photo, photoRect, matrix);
    final actual = placedBoxGlobalCenter(tester, 0);
    expect((actual - expected).distance, lessThanOrEqualTo(1));
  }

  testWidgets('boxesMoveWithPhotoOnZoom', (tester) async {
    await expectBoxesFollowPhoto(
      tester,
      portrait,
      const Rect.fromLTWH(200, 300, 400, 100),
    );
  });

  testWidgets('landscapePhotoBoxesAligned', (tester) async {
    await expectBoxesFollowPhoto(
      tester,
      landscape,
      const Rect.fromLTWH(500, 300, 600, 160),
    );
  });

  testWidgets('tapBox_opensDetailWithPronunciationAndPrices', (tester) async {
    await pumpView(
      tester,
      completed(
        results: [
          translated(
            'p1',
            '라멘',
            pronunciation: '라멘',
            prices: const [
              PhotoPrice(
                text: '980円',
                amount: 980,
                currency: 'JPY',
                confirmed: true,
                krwAmount: 8930,
              ),
            ],
          ),
        ],
      ),
    );

    await tester.tapAt(placedBoxGlobalCenter(tester, 0));
    await tester.pumpAndSettle();

    expect(find.byType(ParagraphDetailSheet), findsOneWidget);
    expect(find.text('원문 p1'), findsOneWidget);
    expect(find.textContaining('8,930원'), findsOneWidget);
  });

  testWidgets('toggleOriginal_hidesBoxes', (tester) async {
    await pumpView(tester, completed());
    expect(find.byType(TranslationBoxOverlay), findsOneWidget);

    await tester.tap(find.text(PhotoResultView.showOriginalLabel));
    expect(toggles, 1);

    await pumpView(tester, completed(showOriginal: true));
    expect(find.byType(TranslationBoxOverlay), findsNothing);
    expect(find.text(PhotoResultView.showTranslationLabel), findsOneWidget);
  });

  testWidgets('fallbackParagraph_showsNotice', (tester) async {
    await pumpView(
      tester,
      completed(
        results: [
          translated('p1', '라멘', source: PhotoTranslationSource.ocrText),
        ],
      ),
    );

    expect(find.text(PhotoResultView.fallbackNotice), findsOneWidget);
  });

  testWidgets('uncertainMarker_rendered', (tester) async {
    await pumpView(
      tester,
      completed(
        results: [translated('p1', '매주 [읽을 수 없음] 휴무', uncertain: true)],
      ),
    );

    expect(
      find.bySemanticsLabel(RegExp(TranslationBoxOverlay.uncertainLabel)),
      findsOneWidget,
    );
  });

  testWidgets('unconfirmedPrice_noKrwShown', (tester) async {
    await pumpView(
      tester,
      completed(
        results: [
          translated(
            'p1',
            '라멘',
            prices: const [
              PhotoPrice(
                text: '98O円',
                amount: null,
                currency: null,
                confirmed: false,
              ),
            ],
          ),
        ],
      ),
    );

    await tester.tapAt(placedBoxGlobalCenter(tester, 0));
    await tester.pumpAndSettle();

    expect(
      find.text(ParagraphDetailSheet.unconfirmedPriceLabel),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'[0-9]원')), findsNothing);
  });

  testWidgets('응답에 없는 문단은 그리지 않고 번역하지 못한 문단으로 센다, 일부만 번역도 알린다', (tester) async {
    await pumpView(
      tester,
      completed(
        paragraphs: const [
          OcrParagraph(
            id: 'p1',
            text: 'a',
            box: Rect.fromLTWH(100, 100, 400, 100),
          ),
          OcrParagraph(
            id: 'p2',
            text: 'b',
            box: Rect.fromLTWH(100, 600, 400, 100),
          ),
        ],
        omittedCount: 3,
      ),
    );

    expect(debugTranslationBoxes, hasLength(1));
    expect(find.text(PhotoResultView.missingNotice(1)), findsOneWidget);
    expect(find.text(PhotoResultView.omittedNotice), findsOneWidget);
  });

  testWidgets('uploading_showsProgressAndRetakeEnabled', (tester) async {
    await pumpView(
      tester,
      const PhotoTranslationState(
        status: PhotoTranslationStatus.uploading,
        photo: portrait,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(PhotoResultView.uploadingLabel), findsOneWidget);
    expect(find.byType(TranslationBoxOverlay), findsNothing);

    await tester.tap(find.text(PhotoResultView.retakeLabel));
    expect(retakes, 1);
  });

  testWidgets('failed_showsRetry', (tester) async {
    await pumpView(
      tester,
      const PhotoTranslationState(
        status: PhotoTranslationStatus.failed,
        photo: portrait,
        errorMessage: '번역 중 문제가 발생했습니다.',
      ),
    );

    expect(find.text(PhotoResultView.failedTitle), findsOneWidget);
    expect(find.text('번역 중 문제가 발생했습니다.'), findsOneWidget);
    await tester.tap(find.text(PhotoResultView.retryLabel));
    expect(retries, 1);
  });

  testWidgets('사진 없이 실패하면 다시 시도 없이 재촬영만 보인다', (tester) async {
    await pumpView(
      tester,
      const PhotoTranslationState(
        status: PhotoTranslationStatus.failed,
        errorMessage: '사진을 준비하는 중 문제가 발생했습니다.',
      ),
    );

    expect(find.text(PhotoResultView.retryLabel), findsNothing);
    // 위 막대와 실패 안내 아래(엄지가 닿는 곳) 두 곳에서 재촬영할 수 있다.
    expect(find.text(PhotoResultView.retakeLabel), findsNWidgets(2));
    await tester.tap(
      find.widgetWithText(FilledButton, PhotoResultView.retakeLabel),
    );
    expect(retakes, 1);
  });

  testWidgets('글자를 찾지 못하면 안내와 재촬영만 보인다', (tester) async {
    await pumpView(
      tester,
      const PhotoTranslationState(
        status: PhotoTranslationStatus.noText,
        errorMessage: '사진에서 번역할 글자를 찾지 못했습니다.',
      ),
    );

    expect(find.text('사진에서 번역할 글자를 찾지 못했습니다.'), findsOneWidget);
    expect(find.text(PhotoResultView.retryLabel), findsNothing);
    expect(
      find.widgetWithText(FilledButton, PhotoResultView.retakeLabel),
      findsOneWidget,
    );
  });

  testWidgets('작은 화면(320폭)·글자 배율 2에서 넘치지 않는다', (tester) async {
    const small = Size(320, 568);
    await pumpView(
      tester,
      completed(
        results: [
          translated(
            'p1',
            '아주 긴 번역 ' * 20,
            source: PhotoTranslationSource.ocrText,
          ),
        ],
        omittedCount: 2,
        paragraphs: const [
          OcrParagraph(
            id: 'p1',
            text: 'a',
            box: Rect.fromLTWH(100, 100, 400, 100),
          ),
          OcrParagraph(
            id: 'p2',
            text: 'b',
            box: Rect.fromLTWH(100, 600, 400, 100),
          ),
        ],
      ),
      size: small,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    await pumpView(
      tester,
      const PhotoTranslationState(
        status: PhotoTranslationStatus.failed,
        photo: portrait,
        errorMessage: '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.',
      ),
      size: small,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
