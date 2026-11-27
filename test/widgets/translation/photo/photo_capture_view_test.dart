import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show TranslationState;
import 'package:tripbler/widgets/translation/photo/photo_capture_view.dart';

// 촬영 화면 배치: 작은 화면·큰 글자·다크 모드에서 넘치지 않고, 촬영 중·플래시 상태가 구분된다.
void main() {
  final languages = const TranslationState().languages;

  Future<void> pumpView(
    WidgetTester tester, {
    bool isCapturing = false,
    bool isFlashOn = false,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: Scaffold(
          body: PhotoCaptureView(
            cameraController: null,
            isCameraReady: true,
            isFlashOn: isFlashOn,
            isCapturing: isCapturing,
            sourceLanguageCode: 'auto',
            targetLanguageCode: 'ko',
            languages: languages,
            onSourceLanguageChanged: (_) {},
            onTargetLanguageChanged: (_) {},
            onToggleFlash: () {},
            onCapture: () {},
            onPickFromGallery: () {},
          ),
        ),
      ),
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('320폭·글자 배율 2에서 넘치지 않는다 ($mode)', (tester) async {
      await pumpView(tester, themeMode: mode);

      expect(tester.takeException(), isNull);
      expect(find.text(PhotoCaptureView.brand), findsOneWidget);
      expect(find.byTooltip(PhotoCaptureView.shutterTooltip), findsOneWidget);
      // 촬영 안내·전송 안내 문구는 2026-11-27 사용자 요청으로 없앴다.
      expect(find.textContaining('전송'), findsNothing);
      expect(find.textContaining('촬영해요'), findsNothing);
    });
  }

  testWidgets('촬영 중이면 셔터 자리에 진행 표시를 두고 누를 수 없다', (tester) async {
    await pumpView(tester, isCapturing: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final shutter = tester.widget<IconButton>(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(IconButton),
      ),
    );
    expect(shutter.onPressed, isNull);
  });

  testWidgets('플래시가 켜져 있으면 선택된 상태로 끄기 안내를 보인다', (tester) async {
    await pumpView(tester, isFlashOn: true);

    expect(find.byTooltip(PhotoCaptureView.flashOffTooltip), findsOneWidget);
    expect(find.byIcon(Icons.flash_on), findsOneWidget);
  });
}
