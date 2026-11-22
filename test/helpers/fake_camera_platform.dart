import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 테스트용 가짜 카메라 플랫폼.
///
/// camera 0.12 `CameraController`가 실제로 부르는 메서드만 흉내 내고 호출을 기록한다.
/// `CameraPlatform`을 `extends`로 이어받아 플랫폼 토큰 검사를 통과하므로
/// `CameraPlatform.instance = fake`로 바로 넣을 수 있다. 테스트 끝에 원래 인스턴스로 되돌린다.
///
/// - `availableCameras` → [cameras]
/// - `createCameraWithSettings` → 1부터 올라가는 카메라 번호([createdCameraIds])
/// - `initializeCamera` → [initializeError]가 있으면 던지고, 아니면 [onCameraInitialized]가
///   [previewSize] 크기의 준비 완료 이벤트를 보낸다.
/// - `takePicture` → [takePictureError]가 있으면 던지고, 아니면 [picturePath]
/// - `setFlashMode` → [setFlashModeError]가 있으면 던진다. 성공·실패 모두 [flashModes]에 기록한다.
/// - `dispose` → [disposedCameraIds]에 기록
/// - [initializeGate]·[takePictureGate]·[disposeGate]를 두면 해당 호출이 그 Completer를 기다린다.
/// - `buildPreview` → 빈 위젯
class FakeCameraPlatform extends CameraPlatform {
  FakeCameraPlatform({
    List<CameraDescription>? cameras,
    this.previewSize = const Size(1920, 1080),
  }) : cameras = cameras ?? <CameraDescription>[backCamera];

  /// 후면 카메라 한 대.
  static const CameraDescription backCamera = CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  /// 전면 카메라 한 대.
  static const CameraDescription frontCamera = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  );

  /// `availableCameras`가 돌려줄 목록.
  List<CameraDescription> cameras;

  /// 준비 완료 이벤트에 담을 미리보기 크기(가로, 세로 픽셀).
  Size previewSize;

  /// 있으면 `initializeCamera`가 던진다.
  Object? initializeError;

  /// 있으면 `takePicture`가 던진다.
  Object? takePictureError;

  /// 있으면 `setFlashMode`가 던진다.
  Object? setFlashModeError;

  /// `takePicture`가 돌려줄 사진 경로.
  String picturePath = '/fake/camera/photo.jpg';

  /// 있으면 `initializeCamera`가 이 값이 끝날 때까지 기다린다(초기화 시점 조절).
  Completer<void>? initializeGate;

  /// 있으면 `takePicture`가 이 값이 끝날 때까지 기다린다(촬영 시점 조절).
  Completer<void>? takePictureGate;

  /// 있으면 `dispose`가 이 값이 끝날 때까지 기다린다(정리 시점 조절).
  Completer<void>? disposeGate;

  int availableCamerasCallCount = 0;
  final List<CameraDescription> createdDescriptions = <CameraDescription>[];
  final List<MediaSettings> createdSettings = <MediaSettings>[];
  final List<int> createdCameraIds = <int>[];
  final List<int> initializedCameraIds = <int>[];
  final List<int> takePictureCameraIds = <int>[];
  final List<FlashMode> flashModes = <FlashMode>[];
  final List<int> disposedCameraIds = <int>[];

  int _nextCameraId = 1;

  /// 가장 최근에 만든 카메라 번호. 만든 적이 없으면 null.
  int? get lastCameraId =>
      createdCameraIds.isEmpty ? null : createdCameraIds.last;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    availableCamerasCallCount++;
    return List<CameraDescription>.of(cameras);
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) {
    return createCameraWithSettings(
      cameraDescription,
      MediaSettings(
        resolutionPreset: resolutionPreset,
        enableAudio: enableAudio,
      ),
    );
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    final cameraId = _nextCameraId++;
    createdDescriptions.add(cameraDescription);
    createdSettings.add(mediaSettings);
    createdCameraIds.add(cameraId);
    return cameraId;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    initializedCameraIds.add(cameraId);

    final gate = initializeGate;
    if (gate != null) {
      await gate.future;
    }

    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) {
    // 컨트롤러는 initializeCamera 전에 `.first`로 구독하고, 초기화가 끝난 뒤 이 값을 기다린다.
    return Stream<CameraInitializedEvent>.value(
      CameraInitializedEvent(
        cameraId,
        previewSize.width,
        previewSize.height,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  // `.first`로 구독하므로 빈 스트림이면 "요소 없음" 오류가 난다. 아무것도 보내지 않는 스트림을 쓴다.
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) {
    return StreamController<CameraErrorEvent>().stream;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() {
    return StreamController<DeviceOrientationChangedEvent>().stream;
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    takePictureCameraIds.add(cameraId);

    final gate = takePictureGate;
    if (gate != null) {
      await gate.future;
    }

    final error = takePictureError;
    if (error != null) {
      throw error;
    }

    return XFile(picturePath);
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    flashModes.add(mode);

    final error = setFlashModeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();

  @override
  Future<void> dispose(int cameraId) async {
    disposedCameraIds.add(cameraId);

    final gate = disposeGate;
    if (gate != null) {
      await gate.future;
    }
  }
}

/// 가짜 플랫폼이 던지는 플랫폼 오류. `CameraController`가 `CameraException`으로 바꿔 던진다.
PlatformException fakeCameraError([String code = 'fake']) {
  return PlatformException(code: code, message: 'fake camera error');
}
