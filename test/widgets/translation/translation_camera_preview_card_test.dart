import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/domain/translation/capture_frame.dart';
import 'package:tripbler/widgets/translation/translation_camera_preview_card.dart';

import '../../helpers/fake_camera_platform.dart';

// 실제 카메라는 테스트에서 쓸 수 없어 카메라 준비 전 상태(controller null)나, 초기화하지 않은 컨트롤러에
// 값만 넣은 상태로 그린다.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    bool isCapturing = false,
    double width = 360,
    double? cardWidth,
    double textScale = 1,
    VoidCallback? onRetry,
    CameraController? controller,
  }) async {
    final card = TranslationCameraPreviewCard(
      cameraController: controller,
      isCameraReady: controller != null,
      isCapturing: isCapturing,
      isFlashOn: false,
      onToggleFlash: () async {},
      onCapture: () async {},
      onPickFromGallery: () async {},
      onRetry: () async => onRetry?.call(),
    );

    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: cardWidth == null
                  ? card
                  : Center(
                      child: SizedBox(width: cardWidth, child: card),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Rect cardRect(WidgetTester tester) {
    return tester.getRect(find.byType(TranslationCameraPreviewCard));
  }

  Rect frameRectOf(Rect card) {
    return Rect.fromCenter(
      center: card.center,
      width: card.width * CaptureFrame.widthFactor,
      height: card.height * CaptureFrame.heightFactor,
    );
  }

  testWidgets('방향이 연속으로 바뀌어도 미리보기의 원래 비율을 유지한다', (tester) async {
    final originalPlatform = CameraPlatform.instance;
    CameraPlatform.instance = FakeCameraPlatform();
    final controller = CameraController(
      FakeCameraPlatform.backCamera,
      ResolutionPreset.high,
    );
    addTearDown(() async {
      await controller.dispose();
      CameraPlatform.instance = originalPlatform;
    });
    controller.value = controller.value.copyWith(
      isInitialized: true,
      previewSize: const Size(1920, 1080),
    );
    await pumpCard(tester, controller: controller);

    for (final orientation in [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitDown,
      DeviceOrientation.portraitUp,
    ]) {
      controller.value = controller.value.copyWith(
        deviceOrientation: orientation,
      );
      await tester.pump();
      final size = tester.getSize(find.byType(CameraPreview));
      final landscape =
          orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight;
      expect(size.aspectRatio, closeTo(landscape ? 16 / 9 : 9 / 16, 0.0001));
      expect(tester.takeException(), isNull);
    }

    controller.value = controller.value.copyWith(
      deviceOrientation: DeviceOrientation.landscapeLeft,
      lockedCaptureOrientation: const Optional.of(DeviceOrientation.portraitUp),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byType(CameraPreview)).aspectRatio,
      closeTo(9 / 16, 0.0001),
    );

    controller.value = controller.value.copyWith(
      isPreviewPaused: true,
      previewPauseOrientation: const Optional.of(
        DeviceOrientation.landscapeRight,
      ),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byType(CameraPreview)).aspectRatio,
      closeTo(16 / 9, 0.0001),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('안내 문구와 카메라 준비 중 표시를 보여준다', (tester) async {
    await pumpCard(tester);

    expect(find.text(TranslationCameraPreviewCard.guideText), findsOneWidget);
    expect(find.bySemanticsLabel('카메라 준비 중'), findsOneWidget);
  });

  testWidgets('버튼마다 낭독기 라벨이 있고 촬영 버튼은 버튼 역할이다', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester);

    expect(find.byTooltip('플래시 켜기'), findsOneWidget);
    expect(find.byTooltip('갤러리에서 사진 고르기'), findsOneWidget);
    expect(find.byTooltip('카메라 다시 켜기'), findsOneWidget);

    final shutter = find.bySemanticsLabel('사진 찍기');
    expect(shutter, findsOneWidget);
    expect(
      tester.getSemantics(shutter),
      isSemantics(label: '사진 찍기', isButton: true, hasEnabledState: true),
    );

    handle.dispose();
  });

  testWidgets('촬영 버튼 터치 영역은 48dp 이상이다', (tester) async {
    await pumpCard(tester);

    final size = tester.getSize(find.byTooltip('사진 찍기'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('다시 시도는 카메라 준비 전에도 누를 수 있다', (tester) async {
    var retried = 0;
    await pumpCard(tester, onRetry: () => retried++);

    await tester.tap(find.byTooltip('카메라 다시 켜기'));
    await tester.pump();

    expect(retried, 1);
  });

  testWidgets('촬영 중이면 진행 표시와 촬영 중 라벨을 보여준다', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester, isCapturing: true);

    expect(find.bySemanticsLabel('사진 찍는 중'), findsOneWidget);
    // 카메라 준비 중 표시 + 촬영 버튼 안의 진행 표시
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    handle.dispose();
  });

  testWidgets('폭 320, 글자 2배에서도 넘침 없이 안내·버튼이 프레임을 가리지 않는다', (tester) async {
    await pumpCard(tester, width: 320, textScale: 2);

    expect(tester.takeException(), isNull);

    final card = cardRect(tester);
    final frame = frameRectOf(card);

    final guide = tester.getRect(
      find.text(TranslationCameraPreviewCard.guideText),
    );
    final flash = tester.getRect(find.byTooltip('플래시 켜기'));
    final gallery = tester.getRect(find.byTooltip('갤러리에서 사진 고르기'));
    final retry = tester.getRect(find.byTooltip('카메라 다시 켜기'));
    final shutter = tester.getRect(find.byTooltip('사진 찍기'));

    // 안내와 플래시는 서로 겹치지 않고 프레임 위에 있다.
    expect(guide.overlaps(flash), isFalse);
    expect(guide.bottom, lessThanOrEqualTo(frame.top));
    expect(flash.bottom, lessThanOrEqualTo(frame.top));
    expect(guide.left, greaterThanOrEqualTo(card.left));
    expect(flash.right, lessThanOrEqualTo(card.right));

    // 아래 버튼은 프레임 아래, 카드 안에 있다.
    for (final rect in [gallery, shutter, retry]) {
      expect(rect.top, greaterThanOrEqualTo(frame.bottom));
      expect(rect.bottom, lessThanOrEqualTo(card.bottom));
    }
  });

  testWidgets('아주 작은 카드(150x200)에서도 위·아래 막대가 넘치지 않는다', (tester) async {
    await pumpCard(tester, width: 200, cardWidth: 150);

    expect(tester.takeException(), isNull);

    final card = cardRect(tester);
    expect(card.width, 150);
    expect(card.height, 200);

    final frame = frameRectOf(card);
    final gallery = tester.getRect(find.byTooltip('갤러리에서 사진 고르기'));
    final retry = tester.getRect(find.byTooltip('카메라 다시 켜기'));
    final shutter = tester.getRect(find.byTooltip('사진 찍기'));

    for (final rect in [gallery, shutter, retry]) {
      expect(rect.top, greaterThanOrEqualTo(frame.bottom - 0.01));
      expect(rect.bottom, lessThanOrEqualTo(card.bottom + 0.01));
      expect(rect.left, greaterThanOrEqualTo(card.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(card.right + 0.01));
    }
    expect(gallery.overlaps(shutter), isFalse);
    expect(shutter.overlaps(retry), isFalse);

    final flash = tester.getRect(find.byTooltip('플래시 켜기'));
    expect(flash.right, lessThanOrEqualTo(card.right + 0.01));
    expect(flash.bottom, lessThanOrEqualTo(frame.top + 0.01));
  });

  testWidgets('더 작은 카드(120 폭)와 큰 글자에서도 넘치지 않는다', (tester) async {
    await pumpCard(tester, width: 200, cardWidth: 120, textScale: 2);

    expect(tester.takeException(), isNull);
  });

  testWidgets('보통 크기 카드는 아래 버튼을 줄이지 않는다', (tester) async {
    await pumpCard(tester);

    final shutter = tester.getSize(find.byTooltip('사진 찍기'));
    expect(shutter.width, 72);
    expect(shutter.height, 72);
  });

  testWidgets('미리보기 크기를 모르면 카메라 화면을 그리지 않고 오류 없이 프레임·버튼만 보여 준다', (
    tester,
  ) async {
    final controller = CameraController(
      const CameraDescription(
        name: 'test',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
      ResolutionPreset.high,
    );
    // 초기화하지 않아 플랫폼을 부르지 않는다. 값만 '초기화됨, 미리보기 크기 모름'으로 둔다.
    controller.value = controller.value.copyWith(isInitialized: true);
    expect(controller.value.previewSize, isNull);

    await pumpCard(tester, controller: controller);

    expect(tester.takeException(), isNull);
    expect(find.byType(CameraPreview), findsNothing);
    expect(find.byTooltip('사진 찍기'), findsOneWidget);
    expect(find.text(TranslationCameraPreviewCard.guideText), findsOneWidget);
  });
}
