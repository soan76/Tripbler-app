import 'dart:async';

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

  /// 준비 도중 잠시 종료([TranslationCamera.suspend])·최종 종료([TranslationCamera.dispose])돼
  /// 결과가 더 이상 유효하지 않다. 실패가 아니므로 화면은 상태를 바꾸지 않는다.
  ignored,
}

/// [TranslationCamera.toggleFlash] 결과.
enum TranslationFlashResult {
  /// 플래시를 바꿨다([TranslationCamera.isFlashOn]이 바뀌었다).
  toggled,

  /// 기기가 플래시를 바꾸지 못했다.
  failed,

  /// 카메라가 준비되지 않았거나, 바꾸는 사이 카메라가 바뀌었거나 닫혔다.
  ignored,
}

/// 앞 촬영이 아직 끝나지 않았거나, 찍는 사이 카메라가 닫혀 결과를 쓸 수 없을 때 던진다.
class TranslationCameraBusyException implements Exception {
  const TranslationCameraBusyException(this.message);

  final String message;

  @override
  String toString() => 'TranslationCameraBusyException: $message';
}

/// 번역 화면의 카메라 장치 제어(권한은 다루지 않는다).
///
/// 비동기 계약:
/// - 세대 번호: [initialize] 시작, [suspend], [dispose] 때 올린다. await 뒤 번호가 바뀌었으면
///   결과를 반영하지 않고([TranslationCameraInitResult.ignored]) 그 사이 만든 컨트롤러는 닫는다.
/// - 중복 초기화: 같은 세대의 초기화가 진행 중이면 새로 시작하지 않고 그 작업을 함께 기다린다(결과 공유).
///   [suspend]·[dispose]는 진행 중 작업을 끊으므로, 그 뒤의 [initialize]는 새로 시작한다.
/// - 플래시 상태는 지금 컨트롤러의 것이다. 컨트롤러를 떼어 낼 때 바로 꺼짐으로 바꾸고, 떼어 낸 컨트롤러의
///   정리는 그 컨트롤러의 플래시 상태만 쓴다(늦게 끝난 정리가 새 컨트롤러 상태를 덮지 않는다).
/// - 컨트롤러 정리는 차례대로 하고, 새 초기화는 앞 정리가 끝난 뒤 카메라를 연다.
/// - [suspend]: 백그라운드·inactive. 컨트롤러만 닫고 다시 [initialize]할 수 있다.
/// - [dispose]: 화면 제거. 이후 모든 요청을 무시한다.
/// - 촬영: 시간 제한(10초)이 실제 촬영을 취소하지 않으므로, 같은 컨트롤러에서는 앞 촬영이 실제로 끝나기
///   전에 새 촬영을 시작하지 않는다. 촬영 중 상태는 컨트롤러·작업 번호별로 두어, 새 컨트롤러는 이전
///   컨트롤러의 끝나지 않은 촬영에 막히지 않는다. 늦게 끝난 이전 촬영 결과는 버린다.
class TranslationCamera {
  TranslationCamera({Future<List<CameraDescription>> Function()? listCameras})
    : _listCameras = listCameras ?? availableCameras;

  /// 촬영 시간 제한.
  static const Duration captureTimeout = Duration(seconds: 10);

  final Future<List<CameraDescription>> Function() _listCameras;

  CameraController? _controller;
  bool _isFlashOn = false;
  int _generation = 0;
  bool _isDisposed = false;
  Future<TranslationCameraInitResult>? _pendingInit;
  Future<void> _closing = Future<void>.value();
  final ValueNotifier<bool> _captureInFlight = ValueNotifier<bool>(false);

  /// 컨트롤러별로 기기에서 아직 끝나지 않은 촬영 작업 번호. 한 컨트롤러에는 촬영이 하나만 있다.
  /// 촬영이 끝나면 자기 작업 번호일 때만 지운다(다른 작업의 진행 상태를 지우지 않는다).
  final Map<CameraController, int> _capturesInFlight =
      <CameraController, int>{};
  int _lastCaptureId = 0;

  /// 지금 쓰는 컨트롤러. 닫았거나 만들지 않았으면 null.
  CameraController? get controller => _controller;

  /// 카메라를 준비하는 중인지.
  bool get isInitializing => _pendingInit != null;

  /// 지금 컨트롤러의 플래시 상태(화면 표시용).
  bool get isFlashOn => _isFlashOn;

  /// 컨트롤러가 있고 준비가 끝났는지.
  bool get isReady {
    final controller = _controller;
    return controller != null && controller.value.isInitialized;
  }

  /// 앞 촬영이 실제로 끝나지 않았는지(시간 제한으로 먼저 실패를 돌려준 촬영 포함).
  ///
  /// 지금 컨트롤러 기준이다. 다른(이전) 컨트롤러의 끝나지 않은 촬영은 새 컨트롤러의 촬영을 막지 않는다.
  bool get isCaptureInFlight => _captureInFlight.value;

  /// [isCaptureInFlight]가 바뀔 때 알린다(촬영 시작·끝, 컨트롤러가 바뀔 때 다시 계산).
  /// 화면이 셔터를 다시 그릴 때 쓴다([dispose] 뒤에는 쓰지 않는다).
  ValueListenable<bool> get captureInFlight => _captureInFlight;

  /// 지금 컨트롤러에 진행 중인 촬영이 있는지 다시 계산해 알린다.
  void _updateCaptureInFlight() {
    if (_isDisposed) {
      return;
    }

    final controller = _controller;
    _captureInFlight.value =
        controller != null && _capturesInFlight.containsKey(controller);
  }

  /// 후면 카메라를 찾아 준비한다. 진행 중인 준비가 있으면 그 결과를 함께 기다린다.
  Future<TranslationCameraInitResult> initialize() {
    if (_isDisposed) {
      return Future<TranslationCameraInitResult>.value(
        TranslationCameraInitResult.ignored,
      );
    }

    final pending = _pendingInit;
    if (pending != null) {
      return pending;
    }

    final generation = ++_generation;
    final future = _initialize(generation);
    _pendingInit = future;
    return future;
  }

  Future<TranslationCameraInitResult> _initialize(int generation) async {
    CameraController? created;

    try {
      // 지금 컨트롤러를 떼어 내고, 앞 정리까지 끝난 뒤 카메라를 연다.
      await _closeController();
      if (_isStale(generation)) {
        return TranslationCameraInitResult.ignored;
      }

      final cameras = await _listCameras();
      if (_isStale(generation)) {
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
      created = controller;
      _controller = controller;
      _updateCaptureInFlight();
      // 새 컨트롤러는 플래시가 꺼진 채 시작한다(기기에 명령은 보내지 않는다).
      _isFlashOn = false;

      await controller.initialize();

      if (_isStale(generation)) {
        await _discard(controller);
        return TranslationCameraInitResult.ignored;
      }

      return TranslationCameraInitResult.ready;
    } catch (error, stackTrace) {
      debugPrint('카메라 초기화 실패: $error');
      debugPrint('$stackTrace');

      if (_isStale(generation)) {
        if (created != null) {
          await _discard(created);
        }
        return TranslationCameraInitResult.ignored;
      }

      await _closeController();

      return TranslationCameraInitResult.failed;
    } finally {
      if (_generation == generation) {
        _pendingInit = null;
      }
    }
  }

  bool _isStale(int generation) => _isDisposed || generation != _generation;

  /// 앱이 백그라운드로 가거나 비활성일 때: 진행 중인 준비를 끊고 컨트롤러를 닫는다.
  /// 다시 [initialize]할 수 있다.
  Future<void> suspend() {
    _generation++;
    _pendingInit = null;
    return _closeController();
  }

  /// 화면이 사라질 때: 컨트롤러를 닫고 이후 모든 요청을 무시한다.
  Future<void> dispose() {
    if (!_isDisposed) {
      _captureInFlight.dispose();
    }
    _isDisposed = true;
    _generation++;
    _pendingInit = null;
    return _closeController();
  }

  /// 지금 컨트롤러를 떼어 내 닫는다. 떼어 내는 순간 플래시 상태는 꺼짐이다.
  /// 정리는 앞 정리가 끝난 뒤 차례대로 한다. 반환값은 이번 정리까지 끝나는 시점.
  Future<void> _closeController() {
    final controller = _controller;
    final wasFlashOn = _isFlashOn;
    _controller = null;
    _isFlashOn = false;
    _updateCaptureInFlight();

    final previous = _closing;
    final closing = _close(previous, controller, wasFlashOn);
    _closing = closing;
    return closing;
  }

  static Future<void> _close(
    Future<void> previous,
    CameraController? controller,
    bool wasFlashOn,
  ) async {
    await previous;

    if (controller == null) {
      return;
    }

    try {
      if (wasFlashOn) {
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
  }

  /// 결과를 쓰지 않을 [controller]를 닫는다. 아직 지금 컨트롤러면 떼어 내고, 이미 떼어 냈으면
  /// (잠시 종료 등) 그 정리를 다시 기다리지 않고 닫기만 한다(dispose는 여러 번 불러도 된다).
  Future<void> _discard(CameraController controller) async {
    if (identical(_controller, controller)) {
      await _closeController();
      return;
    }

    try {
      await controller.dispose();
    } catch (error) {
      debugPrint('카메라 dispose 실패: $error');
    }
  }

  /// 지금 컨트롤러의 플래시를 켜거나 끈다. 바꾸는 사이 카메라가 바뀌었거나 닫혔으면 상태를 바꾸지 않는다.
  Future<TranslationFlashResult> toggleFlash() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return TranslationFlashResult.ignored;
    }

    final generation = _generation;
    final turnOn = !_isFlashOn;

    try {
      await controller.setFlashMode(turnOn ? FlashMode.torch : FlashMode.off);

      if (_isStale(generation) || !identical(_controller, controller)) {
        return TranslationFlashResult.ignored;
      }

      _isFlashOn = turnOn;
      return TranslationFlashResult.toggled;
    } catch (error) {
      debugPrint('플래시 변경 실패: $error');

      if (_isStale(generation) || !identical(_controller, controller)) {
        return TranslationFlashResult.ignored;
      }

      return TranslationFlashResult.failed;
    }
  }

  /// 사진을 찍어 경로와 촬영 순간 미리보기 비율을 돌려준다([captureTimeout] 제한).
  ///
  /// 가이드 프레임을 사진에 옮길 때 쓰는 미리보기 비율. 사진은 미리보기와 화각이 다를 수 있다
  /// (미리보기 16:9, 사진 4:3 등). 촬영 뒤에는 컨트롤러가 정리될 수 있어 찍기 전에 읽는다.
  ///
  /// 준비되지 않았으면 [StateError], 앞 촬영이 아직 끝나지 않았거나 찍는 사이 카메라가 닫혔으면
  /// [TranslationCameraBusyException], 촬영 실패·시간 초과면 그 오류를 던진다.
  Future<({String path, double? previewAspect})> takePicture() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      throw StateError('카메라가 준비되지 않았습니다.');
    }

    // 같은 컨트롤러에서는 시간 제한 뒤에도 실제 촬영이 끝날 때까지 새 촬영을 시작하지 않는다.
    if (_capturesInFlight.containsKey(controller)) {
      throw const TranslationCameraBusyException('앞 촬영이 아직 끝나지 않았습니다.');
    }

    final generation = _generation;
    final previewAspect = CaptureFrame.portraitAspectOf(
      controller.value.previewSize,
    );

    debugPrint('=== takePicture 시작 ===');
    final captureId = ++_lastCaptureId;
    _capturesInFlight[controller] = captureId;
    _updateCaptureInFlight();
    final capture = controller.takePicture();
    // 시간 제한으로 먼저 실패를 돌려줘도 실제 촬영이 끝날 때까지 이 컨트롤러의 다음 촬영을 막는다.
    // 끝나면 이 컨트롤러의 이 작업일 때만 지운다.
    unawaited(
      capture.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (_capturesInFlight[controller] == captureId) {
          _capturesInFlight.remove(controller);
          _updateCaptureInFlight();
        }
      }),
    );

    bool isClosed() =>
        _isStale(generation) || !identical(_controller, controller);

    final XFile image;
    try {
      image = await capture.timeout(captureTimeout);
    } catch (_) {
      // 찍는 사이 닫힌 컨트롤러는 닫힌 컨트롤러 사용 오류 등으로 끝날 수 있다. 같은 이유로 묶는다.
      if (isClosed()) {
        throw const TranslationCameraBusyException('찍는 사이 카메라가 닫혔습니다.');
      }
      rethrow;
    }

    debugPrint('=== takePicture 완료 ===');

    if (isClosed()) {
      throw const TranslationCameraBusyException('찍는 사이 카메라가 닫혔습니다.');
    }

    return (path: image.path, previewAspect: previewAspect);
  }
}
