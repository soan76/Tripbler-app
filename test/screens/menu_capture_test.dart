import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/capture_frame.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/tab_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/providers/translation/translation_provider.dart';
import 'package:tripbler/screens/photo_translation_screen.dart';
import 'package:tripbler/screens/translation_screen.dart';
import 'package:tripbler/services/ocr_service.dart';
import 'package:tripbler/services/photo_normalizer.dart';
import 'package:tripbler/services/translation_service.dart';
import 'package:tripbler/widgets/navigation/navigation_capture_controller.dart';
import 'package:tripbler/widgets/translation/photo/photo_capture_view.dart';
import 'package:tripbler/widgets/translation/translation_result_view.dart';
import 'package:tripbler/widgets/translation/translation_state_views.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_camera_platform.dart';

// 하단 메뉴 촬영 연결: 두 번역 화면이 촬영할 수 있을 때만 메뉴에 촬영 동작을 등록하고,
// 촬영 중에는 동작 대신 촬영 중 표시를 알린다. 촬영 화면 여부(메뉴의 카메라 아이콘)도 알린다.

// permission_handler의 PermissionStatus 번호.
const int _denied = 0;
const int _granted = 1;
const int _restricted = 2;
const int _permanentlyDenied = 4;
const MethodChannel _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

class _FakeOcrService extends OcrService {
  @override
  Future<CaptureFrameLines> recognizeLines({
    required String imagePath,
    required String sourceLanguageCode,
    bool onlyInCaptureFrame = false,
    double? cameraPreviewAspect,
  }) async => (lines: const <String>['hello'], frameApplied: true);

  @override
  Future<String> recognizeText({
    required String imagePath,
    required String sourceLanguageCode,
  }) async => 'hello';
}

class _FakeTranslationService extends TranslationService {
  final List<Completer<String>> calls = [];

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    final completer = Completer<String>();
    calls.add(completer);
    return completer.future;
  }
}

class _FakePhotoNotifier extends PhotoTranslationNotifier {
  final List<String> processed = [];

  @override
  PhotoTranslationState build() => const PhotoTranslationState();

  void emit(PhotoTranslationState next) => state = next;

  @override
  Future<void> processPhoto(String sourcePath) async =>
      processed.add(sourcePath);

  @override
  void leave() {
    if (ref.mounted) state = state.reset();
  }
}

class _TabAt extends TabNotifier {
  @override
  TabState build() => const TabState(selectedIndex: 2);
}

void main() {
  late CameraPlatform originalCameraPlatform;

  setUp(() => originalCameraPlatform = CameraPlatform.instance);
  tearDown(() => CameraPlatform.instance = originalCameraPlatform);

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  void mockPermission(WidgetTester tester, int permission) {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_permissionChannel, (call) async {
      return call.method == 'checkPermissionStatus' ? permission : null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_permissionChannel, null),
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await flush(tester);
  }

  group('기존 번역 화면', () {
    Future<
      ({
        NavigationCaptureController capture,
        FakeCameraPlatform camera,
        ValueNotifier<bool> active,
        _FakeTranslationService translator,
      })
    >
    pumpScreen(
      WidgetTester tester, {
      FakeCameraPlatform? camera,
      int permission = _granted,
    }) async {
      mockPermission(tester, permission);
      final fakeCamera = camera ?? FakeCameraPlatform();
      CameraPlatform.instance = fakeCamera;
      final capture = NavigationCaptureController();
      addTearDown(capture.dispose);
      final active = ValueNotifier<bool>(true);
      addTearDown(active.dispose);
      final translator = _FakeTranslationService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              () => FakeAuthNotifier(initiallySignedIn: false),
            ),
            ocrServiceProvider.overrideWithValue(_FakeOcrService()),
            translationServiceProvider.overrideWithValue(translator),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, value, _) => TranslationScreen(
                  navigationCapture: capture,
                  active: value,
                ),
              ),
            ),
          ),
        ),
      );
      await flush(tester);
      return (
        capture: capture,
        camera: fakeCamera,
        active: active,
        translator: translator,
      );
    }

    testWidgets('카메라가 준비되기 전에는 촬영 동작을 등록하지 않는다', (tester) async {
      final gate = Completer<void>();
      final h = await pumpScreen(
        tester,
        camera: FakeCameraPlatform()..initializeGate = gate,
      );
      expect(h.capture.action.value, isNull);
      // 카메라 준비 중도 촬영 화면이다(메뉴는 흐린 카메라 버튼).
      expect(h.capture.cameraScreen.value, isTrue);

      h.camera.initializeGate = null;
      gate.complete();
      await flush(tester);
      expect(h.capture.action.value, isNotNull);
      expect(h.capture.busy.value, isFalse);
      expect(h.capture.cameraScreen.value, isTrue);

      await unmount(tester);
    });

    testWidgets('메뉴로 촬영하면 촬영 중에는 막고 표시를 알리며, 결과 화면에서도 막는다', (tester) async {
      final gate = Completer<void>();
      final h = await pumpScreen(
        tester,
        camera: FakeCameraPlatform()..takePictureGate = gate,
      );

      h.capture.action.value!();
      await flush(tester);
      expect(h.capture.action.value, isNull);
      expect(h.capture.busy.value, isTrue);
      expect(h.capture.cameraScreen.value, isTrue);
      expect(h.camera.takePictureCameraIds, hasLength(1));

      h.camera.takePictureGate = null;
      gate.complete();
      await flush(tester);
      expect(find.byType(TranslationResultView), findsOneWidget);
      expect(h.capture.action.value, isNull);
      expect(h.capture.busy.value, isFalse);
      // 결과 화면은 촬영 화면이 아니라 메뉴가 번역 탭 아이콘을 보인다.
      expect(h.capture.cameraScreen.value, isFalse);

      h.translator.calls.single.complete('안녕');
      await flush(tester);
      expect(h.capture.action.value, isNull);

      await unmount(tester);
      expect(h.capture.action.value, isNull);
      expect(h.capture.busy.value, isFalse);
    });

    testWidgets('촬영 중 탭을 떠나면 촬영 동작과 촬영 중 표시를 모두 내린다', (tester) async {
      final gate = Completer<void>();
      final h = await pumpScreen(
        tester,
        camera: FakeCameraPlatform()..takePictureGate = gate,
      );
      h.capture.action.value!();
      await flush(tester);
      expect(h.capture.busy.value, isTrue);

      h.active.value = false;
      await flush(tester);
      expect(h.capture.action.value, isNull);
      expect(h.capture.busy.value, isFalse);

      gate.complete();
      await flush(tester);
      await unmount(tester);
    });

    // 버그 수정: 권한 안내 화면에서도 촬영 화면으로 알려 메뉴가 흐린 카메라 버튼을 보였다.
    testWidgets('권한 안내와 카메라를 쓸 수 없는 화면은 촬영 화면으로 알리지 않는다', (tester) async {
      for (final permission in [_denied, _restricted, _permanentlyDenied]) {
        final h = await pumpScreen(tester, permission: permission);
        expect(find.byType(TranslationCameraStatusView), findsOneWidget);
        expect(h.capture.cameraScreen.value, isFalse, reason: '$permission');
        await unmount(tester);
      }
      final h = await pumpScreen(
        tester,
        camera: FakeCameraPlatform(cameras: const []),
      );
      expect(find.byType(TranslationCameraStatusView), findsOneWidget);
      expect(h.capture.cameraScreen.value, isFalse);
      await unmount(tester);
    });

    // 메뉴는 탭을 고른 프레임에 컨트롤러 값을 읽으므로, 보이지 않는 동안에도 촬영 화면 여부를 남긴다.
    testWidgets('탭을 떠나도 촬영 동작은 내리고 촬영 화면 여부는 남긴다', (tester) async {
      final h = await pumpScreen(tester);
      h.active.value = false;
      await flush(tester);
      expect(h.capture.action.value, isNull);
      expect(h.capture.cameraScreen.value, isTrue);
      await unmount(tester);
      expect(h.capture.cameraScreen.value, isFalse);
    });
  });

  group('사진 번역 화면', () {
    Future<
      ({
        NavigationCaptureController capture,
        FakeCameraPlatform camera,
        _FakePhotoNotifier notifier,
        ProviderContainer container,
      })
    >
    pumpScreen(
      WidgetTester tester, {
      FakeCameraPlatform? fakeCamera,
      int permission = _granted,
    }) async {
      mockPermission(tester, permission);
      final camera = fakeCamera ?? FakeCameraPlatform();
      CameraPlatform.instance = camera;
      final capture = NavigationCaptureController();
      addTearDown(capture.dispose);
      final notifier = _FakePhotoNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            photoTranslationProvider.overrideWith(() => notifier),
            tabProvider.overrideWith(_TabAt.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PhotoTranslationScreen(navigationCapture: capture),
            ),
          ),
        ),
      );
      await flush(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PhotoTranslationScreen)),
      );
      return (
        capture: capture,
        camera: camera,
        notifier: notifier,
        container: container,
      );
    }

    testWidgets('다시 그려도 같은 촬영 동작이라 메뉴에 다시 알리지 않는다', (tester) async {
      final h = await pumpScreen(tester);
      expect(h.capture.action.value, isNotNull);
      var notified = 0;
      h.capture.action.addListener(() => notified++);

      // 플래시를 바꾸면 화면이 다시 그려진다.
      await tester.tap(find.byTooltip(PhotoCaptureView.flashOnTooltip));
      await flush(tester);

      expect(notified, 0);
      await unmount(tester);
    });

    testWidgets('메뉴로 촬영하면 촬영 중에는 막고, 결과 화면과 다른 탭에서는 등록하지 않는다', (tester) async {
      final h = await pumpScreen(tester);
      expect(h.capture.cameraScreen.value, isTrue);
      final gate = Completer<void>();
      h.camera.takePictureGate = gate;

      h.capture.action.value!();
      await flush(tester);
      expect(h.capture.action.value, isNull);
      expect(h.capture.busy.value, isTrue);
      expect(h.capture.cameraScreen.value, isTrue);

      gate.complete();
      await flush(tester);
      expect(h.notifier.processed, [h.camera.picturePath]);
      expect(h.capture.busy.value, isFalse);

      h.notifier.emit(
        const PhotoTranslationState(
          status: PhotoTranslationStatus.awaitingConsent,
          photo: NormalizedPhoto(path: 'tmp/p.jpg', width: 800, height: 600),
        ),
      );
      await flush(tester);
      expect(h.capture.action.value, isNull);
      expect(h.capture.cameraScreen.value, isFalse);

      // 다른 탭에서는 촬영 동작을 내리되, 돌아오는 프레임에 쓰도록 촬영 화면 여부는 남긴다.
      h.container.read(tabProvider.notifier).selectTab(0);
      await flush(tester);
      expect(h.capture.action.value, isNull);
      expect(h.capture.busy.value, isFalse);
      expect(h.capture.cameraScreen.value, isTrue);

      await unmount(tester);
    });

    // 버그 수정: 촬영 중 탭을 떠나 카메라를 멈추면 촬영이 오류로 끝나는데, 실패 안내를 띄웠다.
    testWidgets('촬영 중 탭을 떠나면 끝난 촬영을 버리고 실패를 알리지 않는다', (tester) async {
      final h = await pumpScreen(tester);
      final gate = Completer<void>();
      h.camera.takePictureGate = gate;

      h.capture.action.value!();
      await flush(tester);
      h.container.read(tabProvider.notifier).selectTab(0);
      await flush(tester);
      gate.complete();
      await flush(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(h.notifier.processed, isEmpty);
      expect(h.capture.busy.value, isFalse);

      await unmount(tester);
    });

    testWidgets('권한 안내와 카메라를 쓸 수 없는 화면은 촬영 화면으로 알리지 않는다', (tester) async {
      for (final permission in [_denied, _restricted, _permanentlyDenied]) {
        final h = await pumpScreen(tester, permission: permission);
        expect(find.byType(TranslationCameraStatusView), findsOneWidget);
        expect(h.capture.cameraScreen.value, isFalse, reason: '$permission');
        await unmount(tester);
      }
      final h = await pumpScreen(
        tester,
        fakeCamera: FakeCameraPlatform(cameras: const []),
      );
      expect(find.byType(TranslationCameraStatusView), findsOneWidget);
      expect(h.capture.cameraScreen.value, isFalse);
      await unmount(tester);
    });
  });
}
