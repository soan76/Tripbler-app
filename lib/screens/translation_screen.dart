import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ConsumerState, ConsumerStatefulWidget;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/translation/translation_provider.dart';
import '../widgets/navigation/navigation_capture_controller.dart';
import '../widgets/translation/translation_camera.dart';
import '../widgets/translation/translation_camera_view.dart';
import '../widgets/translation/translation_result_view.dart';
import '../widgets/translation/translation_state_views.dart';

part 'translation_camera_permission_flow.dart';

/// 카메라 권한 상태로 카메라를 쓸 수 없을 때 보여 줄 화면 상태. 허용이면 null.
///
/// 영구 거부·제한이면 설정 안내, 그 밖의 거부는 권한을 요청한 적이 있는지([hasRequested])에 따라
/// 거부 안내 또는 첫 권한 안내.
@visibleForTesting
TranslationStatus? blockedStatusFor(
  PermissionStatus status, {
  required bool hasRequested,
}) {
  if (status.isGranted) {
    return null;
  }

  if (status.isPermanentlyDenied || status.isRestricted) {
    return TranslationStatus.permissionPermanentlyDenied;
  }

  return hasRequested
      ? TranslationStatus.permissionDenied
      : TranslationStatus.permissionRequired;
}

/// 카메라 대기 화면이거나 곧 그렇게 되는 상태(권한 확인·카메라 준비 중)인지.
/// 권한 안내와 카메라를 쓸 수 없음은 기다려도 촬영할 수 없으므로 false다.
bool _awaitsCamera(TranslationStatus status) => switch (status) {
  TranslationStatus.checkingPermission ||
  TranslationStatus.initializingCamera ||
  TranslationStatus.cameraReady ||
  TranslationStatus.capturing => true,
  _ => false,
};

// 번역 화면을 구성하는 StatefulWidget
class TranslationScreen extends ConsumerStatefulWidget {
  const TranslationScreen({
    super.key,
    this.navigationCapture,
    this.active = true,
  });
  final NavigationCaptureController? navigationCapture;
  final bool active;

  @override
  ConsumerState<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends ConsumerState<TranslationScreen>
    with WidgetsBindingObserver, _CameraPermissionFlow {
  final ImagePicker _imagePicker = ImagePicker();
  @override
  final TranslationCamera _camera = TranslationCamera();

  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앞 촬영이 기기에서 끝나면 셔터를 다시 켜도록 다시 그린다.
    _camera.captureInFlight.addListener(_onCaptureInFlightChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _checkCameraPermissionOnEntry();
    });
  }

  @override
  void didUpdateWidget(TranslationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    _permissionFlowId++;
    if (!widget.active) {
      _camera.suspend();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkCameraPermissionOnEntry();
      });
    }
  }

  void _onCaptureInFlightChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.captureInFlight.removeListener(_onCaptureInFlightChanged);
    _camera.dispose();
    super.dispose();
  }

  /// 사진 흐름(촬영 중이거나 결과·인식·번역을 보여 주는 중)인지.
  ///
  /// 이때는 카메라가 필요 없고, 권한 확인·카메라 준비가 화면 상태를 바꾸면 번역 상태
  /// (recognizing·translating·completed·failed)나 촬영 중 상태를 덮어 처리 중 버튼 비활성과
  /// 중복 처리 방지가 풀린다. 촬영 중(`capturing`)도 포함한다: 곧 결과 화면으로 넘어가거나 실패를
  /// 보여 주므로 카메라 대기 화면 상태로 되돌리면 안 된다. 카메라는 "다시 촬영" 때 다시 확인·준비한다.
  @override
  bool get _isInPhotoFlow {
    final state = ref.read(translationProvider);
    return _isTakingPicture ||
        state.showsResult ||
        state.status == TranslationStatus.capturing;
  }

  // 앱 라이프사이클 상태 변경 시 카메라 권한 및 초기화 상태를 관리
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // 진행 중인 준비를 끊고 컨트롤러만 닫는다. 돌아오면 다시 준비한다.
      _camera.suspend();
      if (mounted) {
        // 닫힌 컨트롤러를 미리보기에 남기지 않는다.
        setState(() {});
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_isRequestingPermission || _isInPhotoFlow) {
        return;
      }

      _checkCameraPermissionOnEntry();
    }
  }

  // 사진을 찍어 글자 인식·번역을 시작한다. 처리가 끝날 때까지 다시 찍지 않는다.
  // 앞 촬영이 기기에서 아직 끝나지 않았으면(시간 제한 뒤 포함) 상태를 바꾸지 않고 무시한다.
  Future<void> _capturePhoto() async {
    if (!widget.active ||
        _isTakingPicture ||
        !_camera.isReady ||
        _camera.isCaptureInFlight) {
      return;
    }

    _isTakingPicture = true;
    // 사진 촬영 중 상태를 관리하기 위해 번역 상태를 업데이트
    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.capturing);

    final flowId = _permissionFlowId;
    var abandoned = false;
    try {
      final shot = await _camera.takePicture();

      if (!mounted || !widget.active || flowId != _permissionFlowId) {
        abandoned = true;
        return;
      }

      debugPrint('=== OCR 호출 직전 ===');

      // 촬영 화면에 프레임이 없으므로(목업) 갤러리 사진처럼 사진 전체의 글자를 읽는다.
      await provider.processImage(shot.path);
    } catch (error, stackTrace) {
      debugPrint('=== takePicture catch 진입 ===');
      debugPrint('사진 촬영 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      // 탭을 떠나 카메라를 멈추면 찍던 촬영이 오류로 끝난다. 사용자가 실패한 것이 아니므로 실패 화면 대신
      // 버린 촬영으로 처리해, 돌아왔을 때 카메라를 다시 준비한다.
      if (!widget.active || flowId != _permissionFlowId) {
        abandoned = true;
        return;
      }

      provider.setError(message: '사진을 촬영하지 못했습니다.\n다시 시도해 주세요.');
    } finally {
      _isTakingPicture = false;
      if (abandoned) _recoverAbandonedCapture();
    }
  }

  // 촬영 중 탭을 떠나 찍은 사진을 버렸으면 "촬영 중" 상태를 풀어 카메라를 다시 준비할 수 있게 한다.
  // 이미 돌아와 있으면 촬영 중이라 건너뛴 권한 확인·카메라 준비를 지금 다시 한다.
  void _recoverAbandonedCapture() {
    if (!mounted) return;
    if (ref.read(translationProvider).status == TranslationStatus.capturing) {
      ref
          .read(translationProvider.notifier)
          .setStatus(TranslationStatus.checkingPermission);
    }
    if (widget.active) _checkCameraPermissionOnEntry();
  }

  // 갤러리에서 이미지를 골라 글자 인식·번역을 시작한다.
  Future<void> _pickImageFromGallery() async {
    if (ref.read(translationProvider).isProcessing) {
      return;
    }

    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (!mounted || pickedImage == null) {
        return;
      }

      await ref
          .read(translationProvider.notifier)
          .processImage(pickedImage.path);
    } catch (error, stackTrace) {
      debugPrint('이미지 선택 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ref
          .read(translationProvider.notifier)
          .setError(message: '이미지를 선택하지 못했습니다.\n다시 시도해 주세요.');
    }
  }

  // 플래시를 켜거나 끈다. 기기가 지원하지 않으면 안내한다.
  Future<void> _toggleFlash() async {
    final result = await _camera.toggleFlash();

    if (!mounted) {
      return;
    }

    switch (result) {
      case TranslationFlashResult.ignored:
        return;
      case TranslationFlashResult.toggled:
        setState(() {});
      case TranslationFlashResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 기기에서는 플래시를 사용할 수 없습니다.')),
        );
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _retryCamera() async {
    await _checkCameraPermissionOnEntry();
  }

  // 결과를 비우고 카메라 대기 화면으로 돌아간다.
  // 권한은 한 번만 조회하고, 그 결과로 카메라 준비 또는 권한 안내를 정한다.
  Future<void> _retake() async {
    ref.read(translationProvider.notifier).resetForRetake();

    final flowId = ++_permissionFlowId;
    final permissionStatus = await Permission.camera.status;

    if (!mounted || flowId != _permissionFlowId) {
      return;
    }

    await _applyPermissionStatus(permissionStatus, flowId);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final state = ref.watch(translationProvider);

    return NavigationCaptureBinding(
      controller: widget.navigationCapture,
      onCapture:
          widget.active &&
              state.status == TranslationStatus.cameraReady &&
              _camera.isReady &&
              !_isTakingPicture &&
              !_camera.isCaptureInFlight
          ? _capturePhoto
          : null,
      busy:
          widget.active &&
          !state.showsResult &&
          (state.status == TranslationStatus.capturing ||
              _camera.isCaptureInFlight),
      // 탭 선택과 상관없이 알린다. 메뉴가 탭을 고른 프레임에 바로 쓰도록 보이지 않는 동안에도 남긴다.
      cameraScreen: !state.showsResult && _awaitsCamera(state.status),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: colorScheme.surface,
        child: SafeArea(child: _buildBody(state)),
      ),
    );
  }

  // 상태에 따라 결과 화면, 카메라 대기 화면, 권한·준비 안내 화면 중 하나를 고른다.
  Widget _buildBody(TranslationState state) {
    if (state.showsResult) {
      return _buildResultView(state);
    }

    if (state.status == TranslationStatus.cameraReady ||
        state.status == TranslationStatus.capturing) {
      final notifier = ref.read(translationProvider.notifier);

      return TranslationCameraView(
        navigationCapture: widget.navigationCapture,
        state: state,
        cameraController: _camera.controller,
        isCameraReady: _camera.isReady,
        isFlashOn: _camera.isFlashOn,
        isCaptureInFlight: _camera.isCaptureInFlight,
        onSourceLanguageChanged: notifier.changeSourceLanguage,
        onTargetLanguageChanged: notifier.changeTargetLanguage,
        onSwapLanguages: notifier.swapLanguages,
        onToggleFlash: _toggleFlash,
        onCapture: _capturePhoto,
        onPickFromGallery: _pickImageFromGallery,
      );
    }

    return TranslationCameraStatusView(
      status: state.status,
      errorMessage: state.errorMessage,
      onRequestPermission: _requestCameraPermission,
      onOpenSettings: _openSettings,
      onRetry: _retryCamera,
    );
  }

  // 번역 결과 뷰를 구성하는 위젯을 반환하는 메서드
  Widget _buildResultView(TranslationState state) {
    final notifier = ref.read(translationProvider.notifier);

    return TranslationResultView(
      status: state.status,
      selectedImagePath: state.selectedImagePath,
      errorMessage: state.errorMessage,
      recognizedText: state.recognizedText,
      translatedText: state.translatedText,
      lineResult: state.lineResult,
      omittedLineCount: state.omittedLineCount,
      frameFallback: state.frameFallback,
      isProcessing: state.isProcessing,
      sourceLanguageCode: state.sourceLanguageCode,
      targetLanguageCode: state.targetLanguageCode,
      languages: state.languages,
      onSourceLanguageChanged: notifier.changeSourceLanguage,
      onTargetLanguageChanged: notifier.changeTargetLanguage,
      onSwapLanguages: notifier.swapLanguages,
      onRetake: _retake,
      onPickFromGallery: _pickImageFromGallery,
    );
  }
}
