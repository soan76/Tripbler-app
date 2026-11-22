import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/translation/translation_camera.dart';

import '../../helpers/fake_camera_platform.dart';

/// 찍는 순간(플랫폼 takePicture 호출 중) 컨트롤러의 미리보기 크기를 바꾸는 가짜 플랫폼.
/// 비율을 찍기 전에 읽는지 확인한다.
class _PreviewChangingCameraPlatform extends FakeCameraPlatform {
  TranslationCamera? camera;

  @override
  Future<XFile> takePicture(int cameraId) {
    final controller = camera!.controller!;
    controller.value = controller.value.copyWith(
      previewSize: const Size(1000, 1000),
    );
    return super.takePicture(cameraId);
  }
}

// TranslationCamera(카메라 장치 제어) 단위 테스트. 지금 동작 기준.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform originalPlatform;

  setUp(() => originalPlatform = CameraPlatform.instance);
  tearDown(() => CameraPlatform.instance = originalPlatform);

  bool alwaysMounted() => true;

  FakeCameraPlatform useFake([FakeCameraPlatform? fake]) {
    final platform = fake ?? FakeCameraPlatform();
    CameraPlatform.instance = platform;
    return platform;
  }

  group('initialize', () {
    test('후면 카메라를 준비하면 ready이고, 플래시는 꺼짐이며 기기에 플래시 명령을 보내지 않는다', () async {
      final platform = useFake();
      final camera = TranslationCamera();

      final result = await camera.initialize(isMounted: alwaysMounted);

      expect(result, TranslationCameraInitResult.ready);
      expect(camera.isReady, isTrue);
      expect(camera.isFlashOn, isFalse);
      expect(camera.isInitializing, isFalse);
      expect(platform.flashModes, isEmpty);
      expect(
        platform.createdDescriptions.single.lensDirection,
        CameraLensDirection.back,
      );
      expect(
        platform.createdSettings.single.resolutionPreset,
        ResolutionPreset.high,
      );
      expect(platform.createdSettings.single.enableAudio, isFalse);
    });

    test('카메라가 없으면 noCamera', () async {
      final platform = useFake(
        FakeCameraPlatform(cameras: const <CameraDescription>[]),
      );
      final camera = TranslationCamera();

      final result = await camera.initialize(isMounted: alwaysMounted);

      expect(result, TranslationCameraInitResult.noCamera);
      expect(camera.controller, isNull);
      expect(platform.createdCameraIds, isEmpty);
    });

    test('전면 카메라만 있으면 noBackCamera', () async {
      final platform = useFake(
        FakeCameraPlatform(
          cameras: const <CameraDescription>[FakeCameraPlatform.frontCamera],
        ),
      );
      final camera = TranslationCamera();

      final result = await camera.initialize(isMounted: alwaysMounted);

      expect(result, TranslationCameraInitResult.noBackCamera);
      expect(camera.controller, isNull);
      expect(platform.createdCameraIds, isEmpty);
    });

    test('초기화 중 예외가 나면 failed이고 컨트롤러를 정리한다', () async {
      final platform = useFake(
        FakeCameraPlatform()..initializeError = fakeCameraError(),
      );
      final camera = TranslationCamera();

      final result = await camera.initialize(isMounted: alwaysMounted);

      expect(result, TranslationCameraInitResult.failed);
      expect(camera.controller, isNull);
      expect(camera.isReady, isFalse);
      expect(platform.disposedCameraIds, [platform.lastCameraId]);
      expect(camera.isInitializing, isFalse);
    });

    test('준비 중에 다시 부르면 ignored이고 카메라를 더 만들지 않는다', () async {
      final platform = useFake();
      final cameras = Completer<List<CameraDescription>>();
      final camera = TranslationCamera(listCameras: () => cameras.future);

      final first = camera.initialize(isMounted: alwaysMounted);
      expect(camera.isInitializing, isTrue);

      final second = await camera.initialize(isMounted: alwaysMounted);
      expect(second, TranslationCameraInitResult.ignored);

      cameras.complete(<CameraDescription>[FakeCameraPlatform.backCamera]);
      expect(await first, TranslationCameraInitResult.ready);
      expect(platform.createdCameraIds, hasLength(1));
    });

    test('카메라 목록을 받은 뒤 화면이 사라졌으면 ignored이고 카메라를 만들지 않는다', () async {
      final platform = useFake();
      final camera = TranslationCamera();

      final result = await camera.initialize(isMounted: () => false);

      expect(result, TranslationCameraInitResult.ignored);
      expect(platform.createdCameraIds, isEmpty);
    });

    test('다시 준비하면 이전 컨트롤러를 먼저 정리한다', () async {
      final platform = useFake();
      final camera = TranslationCamera();

      await camera.initialize(isMounted: alwaysMounted);
      final firstId = platform.lastCameraId;
      await camera.initialize(isMounted: alwaysMounted);

      expect(platform.disposedCameraIds, [firstId]);
      expect(platform.createdCameraIds, hasLength(2));
      expect(camera.isReady, isTrue);
    });
  });

  group('takePicture', () {
    test('사진 경로와 찍기 전에 읽은 미리보기 비율을 돌려준다', () async {
      final platform = _PreviewChangingCameraPlatform()
        ..previewSize = const Size(1920, 1080)
        ..picturePath = '/fake/photo.jpg';
      useFake(platform);
      final camera = TranslationCamera();
      platform.camera = camera;
      await camera.initialize(isMounted: alwaysMounted);

      final shot = await camera.takePicture();

      expect(shot.path, '/fake/photo.jpg');
      expect(shot.previewAspect, closeTo(1080 / 1920, 1e-9));
      expect(platform.takePictureCameraIds, [platform.lastCameraId]);
    });

    test('촬영이 실패하면 오류를 던진다', () async {
      useFake(FakeCameraPlatform()..takePictureError = fakeCameraError());
      final camera = TranslationCamera();
      await camera.initialize(isMounted: alwaysMounted);

      await expectLater(camera.takePicture(), throwsA(isA<CameraException>()));
    });

    test('준비되지 않았으면 StateError를 던진다', () async {
      useFake();
      final camera = TranslationCamera();

      await expectLater(camera.takePicture(), throwsStateError);
    });
  });

  group('toggleFlash', () {
    test('성공하면 toggled이고 켜짐·꺼짐이 번갈아 바뀐다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize(isMounted: alwaysMounted);

      expect(
        await camera.toggleFlash(isMounted: alwaysMounted),
        TranslationFlashResult.toggled,
      );
      expect(camera.isFlashOn, isTrue);

      expect(
        await camera.toggleFlash(isMounted: alwaysMounted),
        TranslationFlashResult.toggled,
      );
      expect(camera.isFlashOn, isFalse);
      expect(platform.flashModes, [FlashMode.torch, FlashMode.off]);
    });

    test('기기가 실패하면 failed이고 꺼짐을 유지한다', () async {
      final platform = useFake(
        FakeCameraPlatform()..setFlashModeError = fakeCameraError(),
      );
      final camera = TranslationCamera();
      await camera.initialize(isMounted: alwaysMounted);

      expect(
        await camera.toggleFlash(isMounted: alwaysMounted),
        TranslationFlashResult.failed,
      );
      expect(camera.isFlashOn, isFalse);
      expect(platform.flashModes, [FlashMode.torch]);
    });

    test('카메라가 준비되지 않았으면 ignored이고 기기를 부르지 않는다', () async {
      final platform = useFake();
      final camera = TranslationCamera();

      expect(
        await camera.toggleFlash(isMounted: alwaysMounted),
        TranslationFlashResult.ignored,
      );
      expect(platform.flashModes, isEmpty);
    });

    test('바꾸는 사이 화면이 사라졌으면 ignored이고 상태를 바꾸지 않는다', () async {
      useFake();
      final camera = TranslationCamera();
      await camera.initialize(isMounted: alwaysMounted);

      expect(
        await camera.toggleFlash(isMounted: () => false),
        TranslationFlashResult.ignored,
      );
      expect(camera.isFlashOn, isFalse);
    });
  });

  group('disposeController', () {
    test('플래시를 켠 채 정리하면 플래시를 끈 뒤 정리하고 꺼짐으로 둔다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize(isMounted: alwaysMounted);
      final cameraId = platform.lastCameraId;
      await camera.toggleFlash(isMounted: alwaysMounted);

      await camera.disposeController();

      expect(platform.flashModes, [FlashMode.torch, FlashMode.off]);
      expect(platform.disposedCameraIds, [cameraId]);
      expect(camera.controller, isNull);
      expect(camera.isFlashOn, isFalse);
    });

    test('플래시가 꺼져 있으면 플래시 명령 없이 정리하고, 두 번 불러도 한 번만 정리한다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize(isMounted: alwaysMounted);

      await camera.disposeController();
      await camera.disposeController();

      expect(platform.flashModes, isEmpty);
      expect(platform.disposedCameraIds, hasLength(1));
    });

    test('플래시 끄기가 실패해도 컨트롤러는 정리한다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize(isMounted: alwaysMounted);
      await camera.toggleFlash(isMounted: alwaysMounted);
      platform.setFlashModeError = fakeCameraError();

      await camera.disposeController();

      expect(platform.disposedCameraIds, hasLength(1));
      expect(camera.isFlashOn, isFalse);
    });
  });
}
