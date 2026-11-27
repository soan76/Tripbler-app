part of 'translation_screen.dart';

/// 번역 화면의 카메라 권한 확인·요청과 카메라 준비 흐름.
///
/// 권한 흐름 번호로 늦게 끝난 이전 흐름을 버리고, 보이지 않는 화면(`widget.active`가 false)이나
/// 사진 흐름([_isInPhotoFlow]) 중에는 화면 상태를 바꾸지 않는다. 화면 State의 비공개 상태를 함께 쓰므로
/// 같은 라이브러리의 part로 둔다.
mixin _CameraPermissionFlow on ConsumerState<TranslationScreen> {
  TranslationCamera get _camera;

  /// 촬영 중이거나 결과를 보여 주는 중인지. 화면 State가 정한다.
  bool get _isInPhotoFlow;

  bool _hasRequestedCameraPermission = false;

  /// 권한 확인·요청 흐름 번호. 새 흐름(들어올 때 확인, 요청, 다시 촬영)마다 올리고, 늦게 끝난 이전
  /// 흐름은 결과를 반영하지 않는다(예: 거부 확인 뒤 설정에서 허용하고 돌아온 확인이 먼저 끝난 경우).
  int _permissionFlowId = 0;

  /// 권한 요청 대화상자가 떠 있는지. 대화상자는 앱을 inactive로 만들었다가 resumed로 돌려놓는데,
  /// 이때의 권한 확인은 요청 결과와 경쟁하므로 건너뛰고 요청 결과로만 처리한다(요청 결과가 사용자의
  /// 선택을 직접 담고 있어 더 정확하고, 카메라 준비도 한 번만 한다).
  bool _isRequestingPermission = false;

  // 들어올 때(돌아올 때) 카메라 권한을 확인하고, 허용이면 카메라를 준비한다.
  Future<void> _checkCameraPermissionOnEntry() async {
    if (!mounted || !widget.active || _isInPhotoFlow) {
      return;
    }

    final flowId = ++_permissionFlowId;
    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.checkingPermission);

    final permissionStatus = await Permission.camera.status;

    if (!mounted || flowId != _permissionFlowId || _isInPhotoFlow) {
      return;
    }

    await _applyPermissionStatus(permissionStatus, flowId);
  }

  // 카메라 권한을 요청하고, 허용이면 카메라를 준비한다.
  Future<void> _requestCameraPermission() async {
    if (!mounted) {
      return;
    }

    _hasRequestedCameraPermission = true;

    final flowId = ++_permissionFlowId;
    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.checkingPermission);

    final PermissionStatus permissionStatus;
    _isRequestingPermission = true;
    try {
      permissionStatus = await Permission.camera.request();
    } finally {
      _isRequestingPermission = false;
    }

    if (!mounted || flowId != _permissionFlowId) {
      return;
    }

    await _applyPermissionStatus(permissionStatus, flowId);
  }

  // 허용이면 카메라를 준비하고, 아니면 컨트롤러를 먼저 정리한 뒤 권한 안내 상태로 바꾼다.
  // 정리하는 사이 새 권한 흐름이 시작됐거나 화면이 사라졌으면 상태를 바꾸지 않는다.
  // 사진 흐름(갤러리·촬영 사진의 인식·번역·결과) 중이면 정리 전·후 모두 권한 안내로 덮지 않는다
  // (허용 분기의 _initializeCamera와 같은 보호). 카메라는 "다시 촬영" 때 다시 확인한다.
  Future<void> _applyPermissionStatus(
    PermissionStatus permissionStatus,
    int flowId,
  ) async {
    if (permissionStatus.isGranted) {
      await _initializeCamera();
      return;
    }

    // 보이지 않는 화면은 권한 안내로 바꾸지 않는다(허용 분기의 _initializeCamera와 같은 보호).
    // 돌아오면 didUpdateWidget이 새 흐름으로 다시 확인한다.
    if (!widget.active || _isInPhotoFlow) {
      return;
    }

    final provider = ref.read(translationProvider.notifier);

    await _camera.suspend();

    if (!mounted ||
        !widget.active ||
        flowId != _permissionFlowId ||
        _isInPhotoFlow) {
      return;
    }

    provider.setStatus(
      blockedStatusFor(
        permissionStatus,
        hasRequested: _hasRequestedCameraPermission,
      )!,
    );
  }

  // 카메라를 준비하고 결과에 맞게 화면 상태를 바꾼다.
  // 준비 결과가 ignored(잠시 종료·화면 제거로 끊김)면 실패가 아니므로 상태를 바꾸지 않는다.
  // 끊은 쪽(돌아왔을 때 확인, 다시 촬영)이 다시 준비한다.
  Future<void> _initializeCamera() async {
    if (!mounted || !widget.active || _isInPhotoFlow) {
      return;
    }

    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.initializingCamera);

    final result = await _camera.initialize();

    if (!mounted ||
        result == TranslationCameraInitResult.ignored ||
        _isInPhotoFlow) {
      return;
    }

    switch (result) {
      case TranslationCameraInitResult.ignored:
        return;
      case TranslationCameraInitResult.ready:
        provider.setStatus(TranslationStatus.cameraReady);
      case TranslationCameraInitResult.noCamera:
        provider.setError(
          message: '카메라를 사용할 수 없습니다.\n기기의 카메라 상태를 확인해 주세요.',
          status: TranslationStatus.cameraUnavailable,
        );
      case TranslationCameraInitResult.noBackCamera:
        provider.setError(
          message: '사용 가능한 후면 카메라가 없습니다.',
          status: TranslationStatus.cameraUnavailable,
        );
      case TranslationCameraInitResult.failed:
        provider.setError(
          message: '카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.',
          status: TranslationStatus.cameraUnavailable,
        );
    }
  }
}
