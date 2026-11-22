import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../domain/translation/capture_frame.dart';

/// [TranslationCamera.initialize] 결과.
enum TranslationCameraInitResult {
  /// 카메라를 준비했다.
  ready,

  /// 기기에 카메라가 없다.
  noCamera,

  /// 후면 카메라가 없다.
  noBackCamera,

  /// 준비 중 오류가 났다(컨트롤러는 정리했다).
  failed,

  /// 이미 준비 중이었거나 준비 도중 화면이 사라졌다. 화면은 상태를 바꾸지 않는다.
  ignored,
}

/// [TranslationCamera.toggleFlash] 결과.
enum TranslationFlashResult {
  /// 플래시를 바꿨다([TranslationCamera.isFlashOn]이 바뀌었다).
  toggled,

  /// 기기가 플래시를 바꾸지 못했다.
  failed,

  /// 카메라가 준비되지 않았거나 바꾸는 도중 화면이 사라졌다.
  ignored,
}

/// 번역 화면의 카메라 장치 제어(권한은 다루지 않는다).
///
/// 컨트롤러 만들기·준비·정리, 플래시, 촬영만 맡는다. 오류 문구와 화면 상태는 화면이 정한다.
/// 화면이 사라졌는지는 [initialize]·[toggleFlash]에 넘기는 `isMounted`로 확인한다.
class TranslationCamera {
  TranslationCamera({Future<List<CameraDescription>> Function()? listCameras})
    : _listCameras = listCameras ?? availableCameras;

  final Future<List<CameraDescription>> Function() _listCameras;

  CameraController? _controller;
  bool _isInitializing = false;
  bool _isFlashOn = false;

  /// 지금 쓰는 컨트롤러. 정리했거나 만들지 않았으면 null.
  CameraController? get controller => _controller;

  /// 카메라를 준비하는 중인지.
  bool get isInitializing => _isInitializing;

  /// 화면에 보이는 플래시 상태.
  bool get isFlashOn => _isFlashOn;

  /// 컨트롤러가 있고 준비가 끝났는지.
  bool get isReady {
    final controller = _controller;
    return controller != null && controller.value.isInitialized;
  }

  /// 후면 카메라를 찾아 준비한다.
  ///
  /// 이미 준비 중이면 [TranslationCameraInitResult.ignored]. 카메라 목록을 받은 뒤와 준비가 끝난 뒤에
  /// [isMounted]를 확인하고, 준비가 끝난 뒤 화면이 사라졌으면 새 컨트롤러를 정리한다.
  Future<TranslationCameraInitResult> initialize({
    required bool Function() isMounted,
  }) async {
    if (_isInitializing) {
      return TranslationCameraInitResult.ignored;
    }

    _isInitializing = true;

    try {
      await disposeController();
      // 사용 가능한 카메라 목록을 가져온다.
      final cameras = await _listCameras();

      if (!isMounted()) {
        return TranslationCameraInitResult.ignored;
      }

      if (cameras.isEmpty) {
        return TranslationCameraInitResult.noCamera;
      }
      // 후면 카메라만 쓴다.
      final backCameras = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );

      if (backCameras.isEmpty) {
        return TranslationCameraInitResult.noBackCamera;
      }

      final controller = CameraController(
        backCameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _controller = controller;

      await controller.initialize();

      if (!isMounted()) {
        await controller.dispose();
        return TranslationCameraInitResult.ignored;
      }

      // 화면의 플래시 상태만 끈다(새 컨트롤러는 플래시가 꺼진 채 시작한다).
      _isFlashOn = false;
      return TranslationCameraInitResult.ready;
    } catch (error, stackTrace) {
      debugPrint('카메라 초기화 실패: $error');
      debugPrint('$stackTrace');

      if (!isMounted()) {
        return TranslationCameraInitResult.ignored;
      }

      await disposeController();

      return TranslationCameraInitResult.failed;
    } finally {
      _isInitializing = false;
    }
  }

  /// 컨트롤러를 정리한다. 플래시가 켜져 있으면 먼저 끈다. 오류는 출력만 한다.
  Future<void> disposeController() async {
    final controller = _controller;
    _controller = null;

    if (controller == null) {
      return;
    }

    try {
      if (_isFlashOn) {
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (error) {
      debugPrint('플래시 종료 실패: $error');
    }

    try {
      await controller.dispose();
    } catch (error) {
      debugPrint('카메라 dispose 실패: $error');
    }

    _isFlashOn = false;
  }

  /// 플래시를 켜거나 끈다. 성공해도 그 사이 화면이 사라졌으면 상태를 바꾸지 않는다.
  Future<TranslationFlashResult> toggleFlash({
    required bool Function() isMounted,
  }) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return TranslationFlashResult.ignored;
    }

    try {
      final nextFlashMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(nextFlashMode);

      if (!isMounted()) {
        return TranslationFlashResult.ignored;
      }

      _isFlashOn = !_isFlashOn;
      return TranslationFlashResult.toggled;
    } catch (error) {
      debugPrint('플래시 변경 실패: $error');

      if (!isMounted()) {
        return TranslationFlashResult.ignored;
      }

      return TranslationFlashResult.failed;
    }
  }

  /// 사진을 찍어 경로와 촬영 순간 미리보기 비율을 돌려준다(10초 제한).
  ///
  /// 가이드 프레임을 사진에 옮길 때 쓰는 미리보기 비율. 사진은 미리보기와 화각이 다를 수 있다
  /// (미리보기 16:9, 사진 4:3 등). 촬영 뒤에는 컨트롤러가 정리될 수 있어 찍기 전에 읽는다.
  /// 준비되지 않았으면 [StateError], 촬영 실패·시간 초과면 그 오류를 던진다.
  Future<({String path, double? previewAspect})> takePicture() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      throw StateError('카메라가 준비되지 않았습니다.');
    }

    final previewAspect = CaptureFrame.portraitAspectOf(
      controller.value.previewSize,
    );

    debugPrint('=== takePicture 시작 ===');
    final image = await controller.takePicture().timeout(
      const Duration(seconds: 10),
    );

    debugPrint('=== takePicture 완료 ===');

    return (path: image.path, previewAspect: previewAspect);
  }
}
