import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/translation/translation_provider.dart';
import 'package:tripbler/widgets/translation/initial_camera_permission_view.dart';
import 'package:tripbler/widgets/translation/translation_camera_preview_card.dart';
import 'package:tripbler/widgets/translation/translation_camera_view.dart';
import 'package:tripbler/widgets/translation/translation_header.dart';
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
    }) {
      return TranslationCameraView(
        state: TranslationState(status: status),
        // 컨트롤러 없이도 카드는 미리보기 자리를 비우고 버튼을 그린다.
        cameraController: null,
        isCameraReady: isCameraReady,
        isFlashOn: isFlashOn,
        onSourceLanguageChanged: (_) {},
        onTargetLanguageChanged: (_) {},
        onSwapLanguages: () {},
        onToggleFlash: () async => calls.add('flash'),
        onCapture: () async => calls.add('capture'),
        onPickFromGallery: () async => calls.add('gallery'),
        onRetry: () async => calls.add('retry'),
      );
    }

    setUp(() => calls = <String>[]);

    testWidgets('언어 막대·미리보기 카드·안내 문구를 순서대로 보여 준다', (tester) async {
      await pump(tester, cameraView());

      expect(find.byType(TranslationHeader), findsOneWidget);
      expect(find.byType(TranslationCameraPreviewCard), findsOneWidget);
      expect(find.text(TranslationCameraPreviewCard.guideText), findsOneWidget);
      expect(find.text(TranslationCameraView.privacyNote), findsOneWidget);

      final headerTop = tester.getTopLeft(find.byType(TranslationHeader)).dy;
      final cardTop = tester
          .getTopLeft(find.byType(TranslationCameraPreviewCard))
          .dy;
      final noteTop = tester
          .getTopLeft(find.text(TranslationCameraView.privacyNote))
          .dy;
      expect(headerTop, lessThan(cardTop));
      expect(cardTop, lessThan(noteTop));
    });

    testWidgets('버튼이 각 콜백을 부른다', (tester) async {
      await pump(tester, cameraView());

      await tester.tap(find.byTooltip('플래시 켜기'));
      await tester.tap(find.byTooltip('갤러리에서 사진 고르기'));
      await tester.tap(find.byTooltip('사진 찍기'));
      await tester.tap(find.byTooltip('카메라 다시 켜기'));

      expect(calls, ['flash', 'gallery', 'capture', 'retry']);
    });

    testWidgets('플래시가 켜져 있으면 끄기 툴팁', (tester) async {
      await pump(tester, cameraView(isFlashOn: true));

      expect(find.byTooltip('플래시 끄기'), findsOneWidget);
    });

    testWidgets('촬영 중이면 촬영 버튼을 누를 수 없다', (tester) async {
      await pump(tester, cameraView(status: TranslationStatus.capturing));

      await tester.tap(find.byTooltip('사진 찍기'));
      expect(calls, isEmpty);
    });

    testWidgets('카메라가 준비되지 않았으면 다시 켜기만 누를 수 있다', (tester) async {
      await pump(tester, cameraView(isCameraReady: false));

      await tester.tap(find.byTooltip('플래시 켜기'));
      await tester.tap(find.byTooltip('갤러리에서 사진 고르기'));
      await tester.tap(find.byTooltip('사진 찍기'));
      await tester.tap(find.byTooltip('카메라 다시 켜기'));

      expect(calls, ['retry']);
    });
  });
}
