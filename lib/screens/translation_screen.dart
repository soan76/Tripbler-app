import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ConsumerState, ConsumerStatefulWidget;

import '../providers/translation/translation_provider.dart';
import '../widgets/translation/translation_camera.dart';
import '../widgets/translation/translation_camera_view.dart';
import '../widgets/translation/translation_result_view.dart';
import '../widgets/translation/translation_state_views.dart';

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

// 번역 화면을 구성하는 StatefulWidget
class TranslationScreen extends ConsumerStatefulWidget {
  const TranslationScreen({super.key});

  @override
  ConsumerState<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends ConsumerState<TranslationScreen>
    with WidgetsBindingObserver {
  final ImagePicker _imagePicker = ImagePicker();
  final TranslationCamera _camera = TranslationCamera();

  bool _hasRequestedCameraPermission = false;
  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _checkCameraPermissionOnEntry();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.disposeController();
    super.dispose();
  }

  // 앱 라이프사이클 상태 변경 시 카메라 권한 및 초기화 상태를 관리
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _camera.disposeController();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _checkCameraPermissionOnEntry();
    }
  }

  // 들어올 때(돌아올 때) 카메라 권한을 확인하고, 허용이면 카메라를 준비한다.
  Future<void> _checkCameraPermissionOnEntry() async {
    if (!mounted) {
      return;
    }

    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.checkingPermission);

    final permissionStatus = await Permission.camera.status;

    if (!mounted) {
      return;
    }

    await _applyPermissionStatus(permissionStatus);
  }

  // 카메라 권한을 요청하고, 허용이면 카메라를 준비한다.
  Future<void> _requestCameraPermission() async {
    if (!mounted) {
      return;
    }

    _hasRequestedCameraPermission = true;

    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.checkingPermission);

    final permissionStatus = await Permission.camera.request();

    if (!mounted) {
      return;
    }

    await _applyPermissionStatus(permissionStatus);
  }

  // 허용이면 카메라를 준비하고, 아니면 컨트롤러를 먼저 정리한 뒤 권한 안내 상태로 바꾼다.
  // 호출부가 권한 확인 직후 mounted를 확인한 뒤 부른다. 정리하는 동안 화면이 사라져도 상태를 바꾸도록
  // notifier를 먼저 읽어 둔다(지금까지와 같은 동작).
  Future<void> _applyPermissionStatus(PermissionStatus permissionStatus) async {
    final provider = ref.read(translationProvider.notifier);

    if (permissionStatus.isGranted) {
      await _initializeCamera();
      return;
    }

    await _camera.disposeController();

    provider.setStatus(
      blockedStatusFor(
        permissionStatus,
        hasRequested: _hasRequestedCameraPermission,
      )!,
    );
  }

  // 카메라를 준비하고 결과에 맞게 화면 상태를 바꾼다.
  Future<void> _initializeCamera() async {
    if (!mounted || _camera.isInitializing) {
      return;
    }

    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.initializingCamera);

    final result = await _camera.initialize(isMounted: () => mounted);

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

  // 사진을 찍어 글자 인식·번역을 시작한다. 처리가 끝날 때까지 다시 찍지 않는다.
  Future<void> _capturePhoto() async {
    if (_isTakingPicture || !_camera.isReady) {
      return;
    }

    _isTakingPicture = true;
    // 사진 촬영 중 상태를 관리하기 위해 번역 상태를 업데이트
    final provider = ref.read(translationProvider.notifier);
    provider.setStatus(TranslationStatus.capturing);

    try {
      final shot = await _camera.takePicture();

      if (!mounted) {
        return;
      }

      debugPrint('=== OCR 호출 직전 ===');

      await provider.processImage(
        shot.path,
        fromCamera: true,
        cameraPreviewAspect: shot.previewAspect,
      );
    } catch (error, stackTrace) {
      debugPrint('=== takePicture catch 진입 ===');
      debugPrint('사진 촬영 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      provider.setError(message: '사진을 촬영하지 못했습니다.\n다시 시도해 주세요.');
    } finally {
      _isTakingPicture = false;
    }
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
    final result = await _camera.toggleFlash(isMounted: () => mounted);

    // 카메라가 isMounted로 확인했지만, 결과를 받는 사이 화면이 사라졌을 수 있다.
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
  Future<void> _retake() async {
    ref.read(translationProvider.notifier).resetForRetake();

    final permissionStatus = await Permission.camera.status;

    if (!mounted) {
      return;
    }

    if (permissionStatus.isGranted) {
      await _initializeCamera();
    } else {
      await _checkCameraPermissionOnEntry();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final state = ref.watch(translationProvider);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colorScheme.surface,
      child: SafeArea(child: _buildBody(state)),
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
        state: state,
        cameraController: _camera.controller,
        isCameraReady: _camera.isReady,
        isFlashOn: _camera.isFlashOn,
        onSourceLanguageChanged: notifier.changeSourceLanguage,
        onTargetLanguageChanged: notifier.changeTargetLanguage,
        onSwapLanguages: notifier.swapLanguages,
        onToggleFlash: _toggleFlash,
        onCapture: _capturePhoto,
        onPickFromGallery: _pickImageFromGallery,
        onRetry: _retryCamera,
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
