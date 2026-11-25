import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ConsumerState, ConsumerStatefulWidget;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/tab_provider.dart';
import '../providers/translation/photo_translation_provider.dart';
import '../providers/translation/translation_provider.dart'
    show TranslationState, TranslationStatus;
import '../widgets/translation/photo/photo_capture_view.dart';
import '../widgets/translation/photo/photo_consent_dialog.dart';
import '../widgets/translation/photo/photo_result_view.dart';
import '../widgets/translation/translation_camera.dart';
import '../widgets/translation/translation_state_views.dart';

/// 사진 번역 화면: 전체 화면 촬영 → (동의) → 사진 위 번역 상자.
///
/// 사진 번역 상태가 `idle`이면 촬영 화면, 그 밖이면 결과 화면을 보여 준다. 카메라는 촬영 화면에서만
/// 켜 두고, 사진을 고르면 끈다. 상태가 다시 `idle`이 되면(재촬영·동의 취소·세션 변경) 다시 켠다.
class PhotoTranslationScreen extends ConsumerStatefulWidget {
  const PhotoTranslationScreen({super.key});

  @override
  ConsumerState<PhotoTranslationScreen> createState() =>
      _PhotoTranslationScreenState();
}

class _PhotoTranslationScreenState extends ConsumerState<PhotoTranslationScreen>
    with WidgetsBindingObserver {
  // MainScreen 하단 탭에서 번역 탭의 인덱스.
  static const int _translationTabIndex = 2;

  // 언어 목록은 기존 번역 화면과 같다.
  static final _languages = const TranslationState().languages;

  final ImagePicker _imagePicker = ImagePicker();
  final TranslationCamera _camera = TranslationCamera();

  // 화면 제거 때(ref를 쓸 수 없을 때) 이탈을 알리려고 미리 받아 둔다.
  late final PhotoTranslationNotifier _notifier;

  TranslationStatus _cameraStatus = TranslationStatus.checkingPermission;
  String? _cameraError;
  bool _hasRequestedPermission = false;
  bool _isRequestingPermission = false;
  bool _isTakingPicture = false;
  bool _consentOpen = false;

  /// 권한 확인·카메라 준비 흐름 번호. 늦게 끝난 이전 흐름은 반영하지 않는다.
  int _flowId = 0;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(photoTranslationProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _camera.captureInFlight.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.captureInFlight.removeListener(_refresh);
    unawaited(_camera.dispose());
    _notifier.leave();
    super.dispose();
  }

  bool get _inCaptureMode =>
      ref.read(photoTranslationProvider).status == PhotoTranslationStatus.idle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_camera.suspend());
      _refresh();
      return;
    }
    if (state == AppLifecycleState.resumed && !_isRequestingPermission) {
      _startCamera();
    }
  }

  // 촬영 화면일 때만 권한을 확인하고 카메라를 켠다.
  Future<void> _startCamera() async {
    if (!mounted || !_inCaptureMode) {
      return;
    }
    final flowId = ++_flowId;
    setState(() => _cameraStatus = TranslationStatus.checkingPermission);
    final status = await Permission.camera.status;
    await _applyPermission(status, flowId);
  }

  Future<void> _requestPermission() async {
    _hasRequestedPermission = true;
    final flowId = ++_flowId;
    setState(() => _cameraStatus = TranslationStatus.checkingPermission);
    final PermissionStatus status;
    _isRequestingPermission = true;
    try {
      status = await Permission.camera.request();
    } finally {
      _isRequestingPermission = false;
    }
    await _applyPermission(status, flowId);
  }

  Future<void> _applyPermission(PermissionStatus status, int flowId) async {
    if (!mounted || flowId != _flowId || !_inCaptureMode) {
      return;
    }
    if (!status.isGranted) {
      await _camera.suspend();
      if (mounted && flowId == _flowId) {
        setState(() {
          _cameraStatus = status.isPermanentlyDenied || status.isRestricted
              ? TranslationStatus.permissionPermanentlyDenied
              : _hasRequestedPermission
              ? TranslationStatus.permissionDenied
              : TranslationStatus.permissionRequired;
        });
      }
      return;
    }

    setState(() => _cameraStatus = TranslationStatus.initializingCamera);
    final result = await _camera.initialize();
    if (!mounted ||
        flowId != _flowId ||
        result == TranslationCameraInitResult.ignored) {
      return;
    }
    if (!_inCaptureMode) {
      // 준비하는 사이 사진을 골랐다: 카메라는 필요 없다.
      unawaited(_camera.suspend());
      return;
    }
    setState(() {
      _cameraError = switch (result) {
        TranslationCameraInitResult.ready ||
        TranslationCameraInitResult.ignored => null,
        TranslationCameraInitResult.noCamera =>
          '카메라를 사용할 수 없습니다.\n기기의 카메라 상태를 확인해 주세요.',
        TranslationCameraInitResult.noBackCamera => '사용 가능한 후면 카메라가 없습니다.',
        TranslationCameraInitResult.failed =>
          '카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.',
      };
      _cameraStatus = _cameraError == null
          ? TranslationStatus.cameraReady
          : TranslationStatus.cameraUnavailable;
    });
  }

  // 사진을 고른 뒤: 진행 중인 카메라 흐름을 끊고 카메라를 끈 다음 사진 번역을 시작한다.
  void _startPhoto(String path) {
    _flowId++;
    unawaited(_camera.suspend());
    unawaited(_notifier.processPhoto(path));
  }

  Future<void> _capture() async {
    if (_isTakingPicture || !_camera.isReady || _camera.isCaptureInFlight) {
      return;
    }
    setState(() => _isTakingPicture = true);
    try {
      final shot = await _camera.takePicture();
      if (mounted && _inCaptureMode) {
        _startPhoto(shot.path);
      }
    } catch (error) {
      debugPrint('사진 촬영 실패: ${error.runtimeType}');
      _showSnackBar('사진을 촬영하지 못했습니다.\n다시 시도해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _isTakingPicture = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (mounted && picked != null && _inCaptureMode) {
        _startPhoto(picked.path);
      }
    } catch (error) {
      debugPrint('이미지 선택 실패: ${error.runtimeType}');
      _showSnackBar('이미지를 선택하지 못했습니다.\n다시 시도해 주세요.');
    }
  }

  Future<void> _toggleFlash() async {
    final result = await _camera.toggleFlash();
    if (result == TranslationFlashResult.failed) {
      _showSnackBar('이 기기에서는 플래시를 사용할 수 없습니다.');
    }
    _refresh();
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // 동의 대화상자. 상태가 먼저 바뀌어(세션 변경 등) 코드로 닫힌 경우에는 취소를 알리지 않는다.
  Future<void> _askConsent() async {
    _consentOpen = true;
    await showPhotoConsentDialog(
      context,
      onAccept: () => unawaited(_notifier.acceptConsentAndTranslate()),
      onCancel: () {
        if (mounted &&
            ref.read(photoTranslationProvider).status ==
                PhotoTranslationStatus.awaitingConsent) {
          _notifier.cancelConsent();
        }
      },
    );
    _consentOpen = false;
  }

  void _onStateChanged(
    PhotoTranslationState? previous,
    PhotoTranslationState next,
  ) {
    final wasAwaiting =
        previous?.status == PhotoTranslationStatus.awaitingConsent;
    final isAwaiting = next.status == PhotoTranslationStatus.awaitingConsent;
    if (isAwaiting && !wasAwaiting && !_consentOpen) {
      unawaited(_askConsent());
    } else if (wasAwaiting && !isAwaiting && _consentOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (next.status == PhotoTranslationStatus.idle &&
        previous?.status != PhotoTranslationStatus.idle) {
      unawaited(_startCamera());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(photoTranslationProvider, _onStateChanged);
    // 번역 탭을 떠나면 진행 중인 작업을 버리고 임시 사진을 지운다.
    ref.listen(tabProvider, (previous, next) {
      if (previous?.selectedIndex == _translationTabIndex &&
          next.selectedIndex != _translationTabIndex) {
        _notifier.leave();
      }
    });

    final state = ref.watch(photoTranslationProvider);
    if (state.status != PhotoTranslationStatus.idle) {
      return PhotoResultView(
        state: state,
        onRetake: _notifier.retake,
        onRetry: () => unawaited(_notifier.retry()),
        onToggleOriginal: _notifier.toggleOriginal,
      );
    }

    if (_cameraStatus != TranslationStatus.cameraReady) {
      return TranslationCameraStatusView(
        status: _cameraStatus,
        errorMessage: _cameraError,
        onRequestPermission: _requestPermission,
        onOpenSettings: openAppSettings,
        onRetry: _startCamera,
      );
    }

    return PhotoCaptureView(
      cameraController: _camera.controller,
      isCameraReady: _camera.isReady,
      isFlashOn: _camera.isFlashOn,
      isCapturing: _isTakingPicture || _camera.isCaptureInFlight,
      sourceLanguageCode: state.sourceLanguageCode,
      targetLanguageCode: state.targetLanguageCode,
      languages: _languages,
      onSourceLanguageChanged: _notifier.changeSourceLanguage,
      onTargetLanguageChanged: _notifier.changeTargetLanguage,
      onToggleFlash: () => unawaited(_toggleFlash()),
      onCapture: () => unawaited(_capture()),
      onPickFromGallery: () => unawaited(_pickFromGallery()),
    );
  }
}
