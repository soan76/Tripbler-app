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

// TranslationCamera(카메라 장치 제어) 단위 테스트.
// 비동기 계약: 세대 번호, 중복 초기화 공유, 컨트롤러별 플래시, suspend/dispose, 촬영 중복 방지.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform originalPlatform;

  setUp(() => originalPlatform = CameraPlatform.instance);
  tearDown(() => CameraPlatform.instance = originalPlatform);

  FakeCameraPlatform useFake([FakeCameraPlatform? fake]) {
    final platform = fake ?? FakeCameraPlatform();
    CameraPlatform.instance = platform;
    return platform;
  }

  group('initialize', () {
    test('후면 카메라를 준비하면 ready이고, 플래시는 꺼짐이며 기기에 플래시 명령을 보내지 않는다', () async {
      final platform = useFake();
      final camera = TranslationCamera();

      final result = await camera.initialize();

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

      expect(await camera.initialize(), TranslationCameraInitResult.noCamera);
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

      expect(
        await camera.initialize(),
        TranslationCameraInitResult.noBackCamera,
      );
      expect(camera.controller, isNull);
      expect(platform.createdCameraIds, isEmpty);
    });

    test('초기화 중 예외가 나면 failed이고 컨트롤러를 정리한다', () async {
      final platform = useFake(
        FakeCameraPlatform()..initializeError = fakeCameraError(),
      );
      final camera = TranslationCamera();

      expect(await camera.initialize(), TranslationCameraInitResult.failed);
      expect(camera.controller, isNull);
      expect(camera.isReady, isFalse);
      expect(platform.disposedCameraIds, [platform.lastCameraId]);
      expect(camera.isInitializing, isFalse);
    });

    test('중복 초기화: 진행 중이면 같은 작업을 함께 기다리고 카메라는 하나만 만든다', () async {
      final platform = useFake();
      final cameras = Completer<List<CameraDescription>>();
      final camera = TranslationCamera(listCameras: () => cameras.future);

      final first = camera.initialize();
      expect(camera.isInitializing, isTrue);
      final second = camera.initialize();

      cameras.complete(<CameraDescription>[FakeCameraPlatform.backCamera]);

      expect(await first, TranslationCameraInitResult.ready);
      expect(await second, TranslationCameraInitResult.ready);
      expect(platform.createdCameraIds, hasLength(1));
      expect(camera.isInitializing, isFalse);
    });

    test('다시 준비하면 이전 컨트롤러를 먼저 정리한다', () async {
      final platform = useFake();
      final camera = TranslationCamera();

      await camera.initialize();
      final firstId = platform.lastCameraId;
      await camera.initialize();

      expect(platform.disposedCameraIds, [firstId]);
      expect(platform.createdCameraIds, hasLength(2));
      expect(camera.isReady, isTrue);
    });

    test('카메라 목록을 기다리는 중 suspend되면 ignored이고 카메라를 만들지 않는다', () async {
      final platform = useFake();
      final cameras = Completer<List<CameraDescription>>();
      final camera = TranslationCamera(listCameras: () => cameras.future);

      final pending = camera.initialize();
      await pumpEventQueue();
      await camera.suspend();
      cameras.complete(<CameraDescription>[FakeCameraPlatform.backCamera]);

      expect(await pending, TranslationCameraInitResult.ignored);
      expect(platform.createdCameraIds, isEmpty);
      expect(camera.controller, isNull);
    });

    test('기기 초기화 중 suspend되면 ignored이고 새 컨트롤러를 닫으며, 다시 준비할 수 있다', () async {
      final gate = Completer<void>();
      final platform = useFake(FakeCameraPlatform()..initializeGate = gate);
      final camera = TranslationCamera();

      final pending = camera.initialize();
      await pumpEventQueue();
      final firstId = platform.lastCameraId;
      expect(firstId, isNotNull);

      final suspended = camera.suspend();
      // suspend 뒤 다시 준비: 진행 중이던 작업을 공유하지 않고 새로 시작한다.
      final again = camera.initialize();
      expect(camera.isInitializing, isTrue);

      gate.complete();

      expect(await pending, TranslationCameraInitResult.ignored);
      await suspended;
      expect(await again, TranslationCameraInitResult.ready);
      expect(platform.disposedCameraIds, contains(firstId));
      expect(platform.createdCameraIds, hasLength(2));
      expect(camera.isReady, isTrue);
      expect(camera.controller!.cameraId, platform.lastCameraId);
    });

    test('기기 초기화 중 dispose되면 ignored이고 새 컨트롤러를 닫으며, 이후 요청은 모두 무시한다', () async {
      final gate = Completer<void>();
      final platform = useFake(FakeCameraPlatform()..initializeGate = gate);
      final camera = TranslationCamera();

      final pending = camera.initialize();
      await pumpEventQueue();
      final disposing = camera.dispose();
      gate.complete();

      expect(await pending, TranslationCameraInitResult.ignored);
      await disposing;
      expect(platform.disposedCameraIds, [platform.lastCameraId]);

      expect(await camera.initialize(), TranslationCameraInitResult.ignored);
      expect(platform.createdCameraIds, hasLength(1));
      expect(await camera.toggleFlash(), TranslationFlashResult.ignored);
      expect(camera.controller, isNull);
    });

    test('기기 초기화 중 예외가 났는데 그 사이 suspend됐으면 failed가 아니라 ignored', () async {
      final gate = Completer<void>();
      final platform = useFake(
        FakeCameraPlatform()
          ..initializeGate = gate
          ..initializeError = fakeCameraError(),
      );
      final camera = TranslationCamera();

      final pending = camera.initialize();
      await pumpEventQueue();
      unawaited(camera.suspend());
      gate.complete();

      expect(await pending, TranslationCameraInitResult.ignored);
      expect(platform.disposedCameraIds, [platform.lastCameraId]);
    });

    test('새 초기화는 앞 컨트롤러 정리가 끝난 뒤 카메라를 연다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize();

      final disposeGate = Completer<void>();
      platform.disposeGate = disposeGate;
      unawaited(camera.suspend());
      final again = camera.initialize();
      await pumpEventQueue();

      // 앞 카메라 정리가 끝나지 않아 새 카메라를 아직 만들지 않았다.
      expect(platform.createdCameraIds, hasLength(1));

      platform.disposeGate = null;
      disposeGate.complete();

      expect(await again, TranslationCameraInitResult.ready);
      expect(platform.createdCameraIds, hasLength(2));
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
      await camera.initialize();

      final shot = await camera.takePicture();

      expect(shot.path, '/fake/photo.jpg');
      expect(shot.previewAspect, closeTo(1080 / 1920, 1e-9));
      expect(platform.takePictureCameraIds, [platform.lastCameraId]);
      expect(camera.isCaptureInFlight, isFalse);
    });

    test('촬영이 실패하면 오류를 던지고, 다음 촬영은 할 수 있다', () async {
      final platform = useFake(
        FakeCameraPlatform()..takePictureError = fakeCameraError(),
      );
      final camera = TranslationCamera();
      await camera.initialize();

      await expectLater(camera.takePicture(), throwsA(isA<CameraException>()));
      await pumpEventQueue();
      expect(camera.isCaptureInFlight, isFalse);

      platform.takePictureError = null;
      await camera.takePicture();
      expect(platform.takePictureCameraIds, hasLength(2));
    });

    test('준비되지 않았으면 StateError를 던진다', () async {
      useFake();
      final camera = TranslationCamera();

      await expectLater(camera.takePicture(), throwsStateError);
    });

    testWidgets('시간 제한 뒤에도 앞 촬영이 실제로 끝날 때까지 새 촬영을 시작하지 않고, 늦은 결과는 버린다', (
      tester,
    ) async {
      final gate = Completer<void>();
      final platform = useFake(FakeCameraPlatform()..takePictureGate = gate);
      final camera = TranslationCamera();
      await tester.runAsync(camera.initialize);

      Object? firstError;
      final first = camera.takePicture().then<void>(
        (_) {},
        onError: (Object error) => firstError = error,
      );
      await tester.pump(TranslationCamera.captureTimeout);
      await first;
      expect(firstError, isA<TimeoutException>());
      expect(camera.isCaptureInFlight, isTrue);

      // 앞 촬영이 아직 진행 중이라 새 촬영은 기기를 부르지 않고 바로 실패한다.
      await expectLater(
        camera.takePicture(),
        throwsA(isA<TranslationCameraBusyException>()),
      );
      expect(platform.takePictureCameraIds, hasLength(1));

      // 앞 촬영이 늦게 끝나면 결과는 버리고 다음 촬영을 허용한다.
      platform.takePictureGate = null;
      gate.complete();
      await tester.pump();
      expect(camera.isCaptureInFlight, isFalse);

      final shot = await camera.takePicture();
      expect(shot.path, platform.picturePath);
      expect(platform.takePictureCameraIds, hasLength(2));
    });

    test('촬영이 기기에서 시작·끝날 때 captureInFlight로 알린다', () async {
      final gate = Completer<void>();
      useFake(FakeCameraPlatform()..takePictureGate = gate);
      final camera = TranslationCamera();
      await camera.initialize();
      final changes = <bool>[];
      camera.captureInFlight.addListener(
        () => changes.add(camera.captureInFlight.value),
      );

      final shot = camera.takePicture();
      expect(changes, [true]);
      gate.complete();
      await shot;
      await pumpEventQueue();

      expect(changes, [true, false]);
      expect(camera.isCaptureInFlight, isFalse);
    });

    test('이전 컨트롤러의 촬영이 끝나지 않아도 새 컨트롤러는 바로 찍을 수 있다', () async {
      final oldGate = Completer<void>();
      final platform = useFake(FakeCameraPlatform()..takePictureGate = oldGate);
      final camera = TranslationCamera();
      await camera.initialize();
      final oldId = platform.lastCameraId;

      final oldShot = camera.takePicture();
      expect(camera.isCaptureInFlight, isTrue);

      // 다시 준비하면 새 컨트롤러 기준으로 다시 계산한다(이전 촬영은 아직 끝나지 않음).
      final changes = <bool>[];
      camera.captureInFlight.addListener(
        () => changes.add(camera.captureInFlight.value),
      );
      expect(await camera.initialize(), TranslationCameraInitResult.ready);
      final newId = platform.lastCameraId;
      expect(newId, isNot(oldId));
      expect(camera.isCaptureInFlight, isFalse);
      expect(changes, [false]);

      platform.takePictureGate = null;
      final shot = await camera.takePicture();
      expect(shot.path, platform.picturePath);
      expect(platform.takePictureCameraIds, [oldId, newId]);

      oldGate.complete();
      await expectLater(
        oldShot,
        throwsA(isA<TranslationCameraBusyException>()),
      );
    });

    test('이전 촬영이 늦게 끝나도 새 촬영의 진행 상태를 지우지 않는다', () async {
      final oldGate = Completer<void>();
      final platform = useFake(FakeCameraPlatform()..takePictureGate = oldGate);
      final camera = TranslationCamera();
      await camera.initialize();

      final oldShot = camera.takePicture().then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
      await camera.initialize();

      final newGate = Completer<void>();
      platform.takePictureGate = newGate;
      final newShot = camera.takePicture();
      expect(camera.isCaptureInFlight, isTrue);

      // 이전 촬영이 끝났다: 결과는 버리고, 새 촬영은 여전히 진행 중이다.
      oldGate.complete();
      expect(await oldShot, isA<TranslationCameraBusyException>());
      await pumpEventQueue();
      expect(camera.isCaptureInFlight, isTrue);
      await expectLater(
        camera.takePicture(),
        throwsA(isA<TranslationCameraBusyException>()),
      );
      expect(platform.takePictureCameraIds, hasLength(2));

      // 새 촬영이 끝나야 해제된다.
      newGate.complete();
      await newShot;
      await pumpEventQueue();
      expect(camera.isCaptureInFlight, isFalse);
    });

    test('찍는 사이 suspend되면 결과를 쓰지 않는다', () async {
      final gate = Completer<void>();
      final platform = useFake(FakeCameraPlatform()..takePictureGate = gate);
      final camera = TranslationCamera();
      await camera.initialize();

      final shot = camera.takePicture();
      await pumpEventQueue();
      unawaited(camera.suspend());
      gate.complete();

      await expectLater(shot, throwsA(isA<TranslationCameraBusyException>()));
      expect(platform.takePictureCameraIds, hasLength(1));
    });
  });

  group('toggleFlash', () {
    test('성공하면 toggled이고 켜짐·꺼짐이 번갈아 바뀐다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize();

      expect(await camera.toggleFlash(), TranslationFlashResult.toggled);
      expect(camera.isFlashOn, isTrue);

      expect(await camera.toggleFlash(), TranslationFlashResult.toggled);
      expect(camera.isFlashOn, isFalse);
      expect(platform.flashModes, [FlashMode.torch, FlashMode.off]);
    });

    test('기기가 실패하면 failed이고 꺼짐을 유지한다', () async {
      final platform = useFake(
        FakeCameraPlatform()..setFlashModeError = fakeCameraError(),
      );
      final camera = TranslationCamera();
      await camera.initialize();

      expect(await camera.toggleFlash(), TranslationFlashResult.failed);
      expect(camera.isFlashOn, isFalse);
      expect(platform.flashModes, [FlashMode.torch]);
    });

    test('카메라가 준비되지 않았으면 ignored이고 기기를 부르지 않는다', () async {
      final platform = useFake();
      final camera = TranslationCamera();

      expect(await camera.toggleFlash(), TranslationFlashResult.ignored);
      expect(platform.flashModes, isEmpty);
    });

    test('바꾸는 사이 suspend되면 ignored이고 상태를 바꾸지 않는다', () async {
      useFake();
      final camera = TranslationCamera();
      await camera.initialize();

      final toggling = camera.toggleFlash();
      unawaited(camera.suspend());

      expect(await toggling, TranslationFlashResult.ignored);
      expect(camera.isFlashOn, isFalse);
    });

    test('늦게 끝난 이전 컨트롤러 정리가 새 컨트롤러의 플래시 상태를 덮지 않는다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize();
      final firstId = platform.lastCameraId;
      await camera.toggleFlash();
      expect(camera.isFlashOn, isTrue);

      // 앞 컨트롤러(플래시 켜짐)의 정리가 기기 dispose에서 멈춘다.
      final disposeGate = Completer<void>();
      platform.disposeGate = disposeGate;
      final suspended = camera.suspend();
      // 떼어 내는 순간 화면의 플래시 상태는 꺼짐이다.
      expect(camera.isFlashOn, isFalse);
      final again = camera.initialize();
      await pumpEventQueue();

      platform.disposeGate = null;
      disposeGate.complete();
      await suspended;
      expect(await again, TranslationCameraInitResult.ready);

      // 새 컨트롤러에서 플래시를 켠다.
      expect(await camera.toggleFlash(), TranslationFlashResult.toggled);
      await pumpEventQueue();

      expect(camera.isFlashOn, isTrue);
      // 앞 컨트롤러 정리는 그 컨트롤러의 플래시만 껐다.
      expect(platform.flashModes, [
        FlashMode.torch,
        FlashMode.off,
        FlashMode.torch,
      ]);
      expect(platform.disposedCameraIds, [firstId]);
    });
  });

  group('suspend·dispose', () {
    test('플래시를 켠 채 닫으면 플래시를 끈 뒤 정리하고 꺼짐으로 둔다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize();
      final cameraId = platform.lastCameraId;
      await camera.toggleFlash();

      await camera.suspend();

      expect(platform.flashModes, [FlashMode.torch, FlashMode.off]);
      expect(platform.disposedCameraIds, [cameraId]);
      expect(camera.controller, isNull);
      expect(camera.isFlashOn, isFalse);
    });

    test('플래시가 꺼져 있으면 플래시 명령 없이 정리하고, 두 번 불러도 한 번만 정리한다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize();

      await camera.suspend();
      await camera.suspend();

      expect(platform.flashModes, isEmpty);
      expect(platform.disposedCameraIds, hasLength(1));
    });

    test('플래시 끄기가 실패해도 컨트롤러는 정리한다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize();
      await camera.toggleFlash();
      platform.setFlashModeError = fakeCameraError();

      await camera.suspend();

      expect(platform.disposedCameraIds, hasLength(1));
      expect(camera.isFlashOn, isFalse);
    });

    test('suspend 뒤에는 다시 준비할 수 있다', () async {
      final platform = useFake();
      final camera = TranslationCamera();
      await camera.initialize();

      await camera.suspend();

      expect(await camera.initialize(), TranslationCameraInitResult.ready);
      expect(platform.createdCameraIds, hasLength(2));
    });
  });
}
