import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/translation/translation_provider.dart';
import 'package:tripbler/widgets/navigation/bottom_menu_capture_marks.dart';
import 'package:tripbler/widgets/navigation/navigation_capture_controller.dart';
import 'package:tripbler/widgets/translation/initial_camera_permission_view.dart';
import 'package:tripbler/widgets/translation/photo/photo_capture_view.dart';
import 'package:tripbler/widgets/translation/photo/photo_language_pill.dart';
import 'package:tripbler/widgets/translation/translation_camera_preview_card.dart';
import 'package:tripbler/widgets/translation/translation_camera_view.dart';
import 'package:tripbler/widgets/translation/translation_state_views.dart';

// 카메라 대기 화면(TranslationCameraView)과 권한·준비 안내(TranslationCameraStatusView) 위젯 테스트.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  group('TranslationCameraStatusView', () {
    late List<String> calls;

    Widget statusView(TranslationStatus status, {String? errorMessage}) {
      return TranslationCameraStatusView(
        status: status,
        errorMessage: errorMessage,
        onRequestPermission: () async => calls.add('request'),
        onOpenSettings: () async => calls.add('settings'),
        onRetry: () async => calls.add('retry'),
      );
    }

    setUp(() => calls = <String>[]);

    testWidgets('권한 확인 중이면 확인 중 안내', (tester) async {
      await pump(tester, statusView(TranslationStatus.checkingPermission));

      expect(find.text('카메라 권한을 확인하고 있습니다.'), findsOneWidget);
    });

    testWidgets('권한 요청 전이면 첫 권한 안내, 버튼은 권한 요청', (tester) async {
      await pump(tester, statusView(TranslationStatus.permissionRequired));

      expect(find.byType(InitialCameraPermissionView), findsOneWidget);
      await tester.tap(find.text('접근 권한 허용'));
      expect(calls, ['request']);
    });

    testWidgets('권한 거부면 거부 안내, 버튼은 권한 요청', (tester) async {
      await pump(tester, statusView(TranslationStatus.permissionDenied));

      expect(find.text('카메라 권한이 허용되지 않았습니다'), findsOneWidget);
      expect(find.text('카메라 번역을 사용하려면 카메라 권한을 허용해야 합니다.'), findsOneWidget);
      await tester.tap(find.text('다시 권한 요청'));
      expect(calls, ['request']);
    });

    testWidgets('영구 거부면 설정 안내, 버튼은 설정 열기', (tester) async {
      await pump(
        tester,
        statusView(TranslationStatus.permissionPermanentlyDenied),
      );

      expect(find.text('설정에서 카메라 권한을 허용해 주세요'), findsOneWidget);
      await tester.tap(find.text('앱 설정 열기'));
      expect(calls, ['settings']);
    });

    testWidgets('카메라 준비 중이면 준비 중 안내', (tester) async {
      await pump(tester, statusView(TranslationStatus.initializingCamera));

      expect(find.text('카메라를 준비하고 있습니다.'), findsOneWidget);
    });

    testWidgets('카메라를 쓸 수 없으면 받은 오류 문구와 다시 시도', (tester) async {
      await pump(
        tester,
        statusView(
          TranslationStatus.cameraUnavailable,
          errorMessage: '사용 가능한 후면 카메라가 없습니다.',
        ),
      );

      expect(find.text('사용 가능한 후면 카메라가 없습니다.'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      expect(calls, ['retry']);
    });

    testWidgets('카메라를 쓸 수 없는데 오류 문구가 없으면 기본 문구', (tester) async {
      await pump(tester, statusView(TranslationStatus.cameraUnavailable));

      expect(
        find.text('카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
    });
  });

  group('TranslationCameraView', () {
    late List<String> calls;

    Widget cameraView({
      TranslationStatus status = TranslationStatus.cameraReady,
      bool isCameraReady = true,
      bool isFlashOn = false,
      bool isCaptureInFlight = false,
      String sourceLanguageCode = 'auto',
      NavigationCaptureController? navigationCapture,
    }) {
      return TranslationCameraView(
        navigationCapture: navigationCapture,
        state: TranslationState(
          status: status,
          sourceLanguageCode: sourceLanguageCode,
        ),
        // 컨트롤러 없이도 미리보기 자리를 비우고 안내와 버튼을 그린다.
        cameraController: null,
        isCameraReady: isCameraReady,
        isFlashOn: isFlashOn,
        isCaptureInFlight: isCaptureInFlight,
        onSourceLanguageChanged: (_) {},
        onTargetLanguageChanged: (_) {},
        onSwapLanguages: () => calls.add('swap'),
        onToggleFlash: () async => calls.add('flash'),
        onCapture: () async => calls.add('capture'),
        onPickFromGallery: () async => calls.add('gallery'),
      );
    }

    IconButton iconButtonWithTooltip(WidgetTester tester, String tooltip) {
      return tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
    }

    setUp(() => calls = <String>[]);

    testWidgets('전체 화면 촬영 배치: 위 Tripbler와 언어 막대만 있고 안내 문구는 없다', (tester) async {
      await pump(tester, cameraView());

      expect(find.byType(PhotoCaptureView), findsOneWidget);
      expect(find.text(PhotoCaptureView.brand), findsOneWidget);
      expect(find.byType(PhotoLanguagePill), findsOneWidget);
      expect(
        tester.getRect(find.text(PhotoCaptureView.brand)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(PhotoLanguagePill)).top),
      );
      // 촬영 안내·기기 안 읽기 안내·전송 안내는 2026-11-27 사용자 요청으로 없앴다.
      expect(find.textContaining('촬영해요'), findsNothing);
      expect(find.textContaining('기기에서'), findsNothing);
      expect(find.textContaining('전송'), findsNothing);
      // 예전 흰 프레임 카드는 쓰지 않는다.
      expect(find.byType(TranslationCameraPreviewCard), findsNothing);
      expect(find.text(TranslationCameraPreviewCard.guideText), findsNothing);
    });

    testWidgets('메뉴로 촬영하면 셔터가 없고, 안내 문구 없이 언어 막대가 하단 메뉴 여백 위에 있다', (
      tester,
    ) async {
      final capture = NavigationCaptureController();
      addTearDown(capture.dispose);
      for (final textScale in [1.0, 1.3, 2.0]) {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(body: cameraView(navigationCapture: capture)),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        // 촬영은 하단 메뉴의 현재 화면 버튼이 맡는다. 갤러리·플래시는 메뉴 원 양옆에 남는다.
        expect(find.byTooltip(PhotoCaptureView.shutterTooltip), findsNothing);
        expect(find.byTooltip(PhotoCaptureView.galleryTooltip), findsOneWidget);
        expect(find.byTooltip(PhotoCaptureView.flashOnTooltip), findsOneWidget);

        expect(find.textContaining('기기에서'), findsNothing);
        expect(find.textContaining('촬영해요'), findsNothing);
        final pill = tester.getRect(find.byType(PhotoLanguagePill));
        expect(
          pill.bottom,
          lessThanOrEqualTo(640 - BottomMenuMetrics.contentClearance),
        );
        expect(pill.left, greaterThanOrEqualTo(0));
        expect(pill.right, lessThanOrEqualTo(320));
      }
    });

    testWidgets('메뉴가 없으면 가운데 아래 셔터를 보이고, 버튼이 각 콜백을 부른다', (tester) async {
      await pump(tester, cameraView(sourceLanguageCode: 'en'));

      await tester.tap(find.byTooltip(PhotoCaptureView.flashOnTooltip));
      await tester.tap(find.byTooltip(PhotoCaptureView.galleryTooltip));
      await tester.tap(find.byTooltip(PhotoCaptureView.shutterTooltip));
      await tester.tap(find.byTooltip(PhotoLanguagePill.swapTooltip));

      expect(calls, ['flash', 'gallery', 'capture', 'swap']);
    });

    testWidgets('원문 언어가 자동 감지면 언어 바꾸기를 누를 수 없다', (tester) async {
      await pump(tester, cameraView());

      expect(
        iconButtonWithTooltip(tester, PhotoLanguagePill.swapTooltip).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip(PhotoLanguagePill.swapTooltip));
      expect(calls, isEmpty);
    });

    testWidgets('플래시가 켜져 있으면 끄기 툴팁', (tester) async {
      await pump(tester, cameraView(isFlashOn: true));

      expect(find.byTooltip(PhotoCaptureView.flashOffTooltip), findsOneWidget);
      expect(find.byIcon(Icons.flash_on), findsOneWidget);
    });

    for (final (name, view) in [
      ('촬영 중', () => cameraView(status: TranslationStatus.capturing)),
      ('앞 촬영이 기기에서 끝나지 않음', () => cameraView(isCaptureInFlight: true)),
    ]) {
      testWidgets('$name이면 셔터는 진행 표시와 함께 비활성, 갤러리도 막힌다', (tester) async {
        await pump(tester, view());

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          iconButtonWithTooltip(
            tester,
            PhotoCaptureView.shutterTooltip,
          ).onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip(PhotoCaptureView.shutterTooltip));
        await tester.tap(find.byTooltip(PhotoCaptureView.galleryTooltip));
        // 플래시는 촬영 중에도 바꿀 수 있다.
        await tester.tap(find.byTooltip(PhotoCaptureView.flashOnTooltip));
        expect(calls, ['flash']);
      });
    }

    testWidgets('카메라가 준비되지 않았으면 갤러리만 누를 수 있다', (tester) async {
      await pump(tester, cameraView(isCameraReady: false));

      await tester.tap(find.byTooltip(PhotoCaptureView.flashOnTooltip));
      await tester.tap(find.byTooltip(PhotoCaptureView.galleryTooltip));
      await tester.tap(find.byTooltip(PhotoCaptureView.shutterTooltip));

      expect(calls, ['gallery']);
    });
  });
}
