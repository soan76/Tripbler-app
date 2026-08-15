import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/translation_provider.dart';
import '../widgets/translation/initial_camera_permission_view.dart';
import '../widgets/translation/translation_camera_preview_card.dart';
import '../widgets/translation/translation_header.dart';
import '../widgets/translation/translation_result_view.dart';
import '../widgets/translation/translation_state_views.dart';

// 번역 화면을 구성하는 StatefulWidget
class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen>
    with WidgetsBindingObserver {
  final ImagePicker _imagePicker = ImagePicker();

  CameraController? _cameraController;
  bool _hasRequestedCameraPermission = false;
  bool _isCameraInitializing = false;
  bool _isTakingPicture = false;
  bool _isFlashOn = false;

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
    _disposeCameraController();
    super.dispose();
  }
  // 앱 라이프사이클 상태 변경 시 카메라 권한 및 초기화 상태를 관리
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCameraController();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _checkCameraPermissionOnEntry();
    }
  }
  // 카메라 권한 확인 및 초기화 로직을 별도의 메서드로 분리 1
  Future<void> _checkCameraPermissionOnEntry() async {
    if (!mounted) {
      return;
    }

    final provider = context.read<TranslationProvider>();
    provider.setStatus(TranslationStatus.checkingPermission);

    final permissionStatus = await Permission.camera.status;

    if (!mounted) {
      return;
    }

    if (permissionStatus.isGranted) {
      await _initializeCamera();
      return;
    }

    await _disposeCameraController();

    if (permissionStatus.isPermanentlyDenied || permissionStatus.isRestricted) {
      provider.setStatus(TranslationStatus.permissionPermanentlyDenied);
      return;
    }

    if (_hasRequestedCameraPermission) {
      provider.setStatus(TranslationStatus.permissionDenied);
    } else {
      provider.setStatus(TranslationStatus.permissionRequired);
    }
  }
  // 카메라 권한 요청 및 초기화 로직을 별도의 메서드로 분리 2
  Future<void> _requestCameraPermission() async {
    if (!mounted) {
      return;
    }

    _hasRequestedCameraPermission = true;

    final provider = context.read<TranslationProvider>();
    provider.setStatus(TranslationStatus.checkingPermission);

    final permissionStatus = await Permission.camera.request();

    if (!mounted) {
      return;
    }

    if (permissionStatus.isGranted) {
      await _initializeCamera();
      return;
    }

    await _disposeCameraController();

    if (permissionStatus.isPermanentlyDenied || permissionStatus.isRestricted) {
      provider.setStatus(TranslationStatus.permissionPermanentlyDenied);
    } else {
      provider.setStatus(TranslationStatus.permissionDenied);
    }
  }
  // 카메라 초기화 및 상태 관리 로직을 별도의 메서드로 분리 3
  Future<void> _initializeCamera() async {
    if (!mounted || _isCameraInitializing) {
      return;
    }
    // 카메라 초기화 중 상태를 관리하기 위해 TranslationProvider의 상태를 업데이트
    final provider = context.read<TranslationProvider>();
    provider.setStatus(TranslationStatus.initializingCamera);

    _isCameraInitializing = true;

    try {
      await _disposeCameraController();
      // 사용 가능한 카메라 목록을 가져오기 위해 availableCameras() 호출
      final cameras = await availableCameras();

      if (!mounted) {
        return;
      }

      if (cameras.isEmpty) {
        provider.setError(
          message: '카메라를 사용할 수 없습니다.\n기기의 카메라 상태를 확인해 주세요.',
          status: TranslationStatus.cameraUnavailable,
        );
        return;
      }
      // 후면 카메라만 필터링하여 사용 가능한 카메라를 확인
      final backCameras = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );

      if (backCameras.isEmpty) {
        provider.setError(
          message: '사용 가능한 후면 카메라가 없습니다.',
          status: TranslationStatus.cameraUnavailable,
        );
        return;
      }
      // 후면 카메라 중 첫 번째 카메라를 선택하여 CameraController를 초기화
      final selectedCamera = backCameras.first;

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _cameraController = controller;

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _isFlashOn = false;
      provider.setStatus(TranslationStatus.cameraReady);
    } catch (error, stackTrace) {
      debugPrint('카메라 초기화 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      await _disposeCameraController();

      provider.setError(
        message: '카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.',
        status: TranslationStatus.cameraUnavailable,
      );
    } finally {
      _isCameraInitializing = false;
    }
  }
  // 카메라 컨트롤러를 안전하게 종료하고 상태를 초기화하는 메서드
  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;

    if (controller == null) {
      return;
    }
    // 플래시 모드가 켜져 있는 경우 플래시를 끄고 카메라 컨트롤러를 종료
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
  // 사진 촬영 및 이미지 선택 로직을 별도의 메서드로 분리 4
  Future<void> _capturePhoto() async {
    final controller = _cameraController;

    if (_isTakingPicture ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    _isTakingPicture = true;
    // 사진 촬영 중 상태를 관리하기 위해 TranslationProvider의 상태를 업데이트
    final provider = context.read<TranslationProvider>();
    provider.setStatus(TranslationStatus.capturing);

    try {
      debugPrint('=== takePicture 시작 ===');
      final image = await controller.takePicture().timeout(
        const Duration(seconds: 10),
      );

      debugPrint('=== takePicture 완료 ===');

      if (!mounted) {
        return;
      }

      debugPrint('=== OCR 호출 직전 ===');

      await provider.processImage(image.path);
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
  // 갤러리에서 이미지 선택 로직을 별도의 메서드로 분리 5
  Future<void> _pickImageFromGallery() async {
    if (context.read<TranslationProvider>().isProcessing) {
      return;
    }
    // 갤러리에서 이미지를 선택하고 처리하는 로직을 별도의 메서드로 분리
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (!mounted || pickedImage == null) {
        return;
      }

      await context.read<TranslationProvider>().processImage(pickedImage.path);
    } catch (error, stackTrace) {
      debugPrint('이미지 선택 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      context.read<TranslationProvider>().setError(
        message: '이미지를 선택하지 못했습니다.\n다시 시도해 주세요.',
      );
    }
  }
  // 플래시 토글 로직을 별도의 메서드로 분리 6
  Future<void> _toggleFlash() async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    // 플래시 모드 변경 시 발생할 수 있는 예외를 처리하고 상태를 업데이트
    try {
      final nextFlashMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(nextFlashMode);

      if (!mounted) {
        return;
      }

      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (error) {
      debugPrint('플래시 변경 실패: $error');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 기기에서는 플래시를 사용할 수 없습니다.')));
    }
  }
  // 앱 설정 열기 로직을 별도의 메서드로 분리 7
  Future<void> _openSettings() async {
    await openAppSettings();
  }
  // 카메라 재시도 로직을 별도의 메서드로 분리 8
  Future<void> _retryCamera() async {
    await _checkCameraPermissionOnEntry();
  }
  // 사진 재촬영 로직을 별도의 메서드로 분리 9
  Future<void> _retake() async {
    context.read<TranslationProvider>().resetForRetake();

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

    return Consumer<TranslationProvider>(
      builder: (context, provider, _) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: colorScheme.surface,
          child: SafeArea(child: _buildBody(provider)),
        );
      },
    );
  }
  // 번역 화면의 본문 영역을 구성하는 위젯을 반환하는 메서드
  Widget _buildBody(TranslationProvider provider) {
    if (provider.hasImage ||
        provider.status == TranslationStatus.recognizing ||
        provider.status == TranslationStatus.translating ||
        provider.status == TranslationStatus.completed ||
        provider.status == TranslationStatus.failed) {
      return _buildResultView(provider);
    }
    // 번역 화면의 상태에 따라 적절한 위젯을 반환
    switch (provider.status) {
      case TranslationStatus.checkingPermission:
        return const TranslationLoadingView(message: '카메라 권한을 확인하고 있습니다.');

      case TranslationStatus.permissionRequired:
        return InitialCameraPermissionView(
          onRequestPermission: _requestCameraPermission,
        );

      case TranslationStatus.permissionDenied:
        return TranslationPermissionView(
          title: '카메라 권한이 허용되지 않았습니다',
          description: '카메라 번역을 사용하려면 카메라 권한을 허용해야 합니다.',
          primaryButtonText: '다시 권한 요청',
          onPrimaryPressed: _requestCameraPermission,
        );

      case TranslationStatus.permissionPermanentlyDenied:
        return TranslationPermissionView(
          title: '설정에서 카메라 권한을 허용해 주세요',
          description:
              '카메라 권한이 차단되어 있습니다. 기기 설정에서 이 앱의 카메라 권한을 허용한 뒤 다시 돌아와 주세요.',
          primaryButtonText: '앱 설정 열기',
          onPrimaryPressed: _openSettings,
        );

      case TranslationStatus.initializingCamera:
        return const TranslationLoadingView(message: '카메라를 준비하고 있습니다.');

      case TranslationStatus.cameraUnavailable:
        return TranslationErrorView(
          message:
              provider.errorMessage ??
              '카메라를 시작할 수 없습니다.\n카메라 상태를 확인한 뒤 다시 시도해 주세요.',
          buttonText: '다시 시도',
          onPressed: _retryCamera,
        );

      case TranslationStatus.cameraReady:
      case TranslationStatus.capturing:
        return _buildCameraView(provider);

      case TranslationStatus.recognizing:
      case TranslationStatus.translating:
      case TranslationStatus.completed:
      case TranslationStatus.failed:
        return _buildResultView(provider);
    }
  }
  // 카메라 뷰를 구성하는 위젯을 반환하는 메서드
  Widget _buildCameraView(TranslationProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCameraReady =
        _cameraController != null && _cameraController!.value.isInitialized;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslationHeader(
            sourceLanguageCode: provider.sourceLanguageCode,
            targetLanguageCode: provider.targetLanguageCode,
            languages: provider.languages,
            onSourceLanguageChanged: provider.changeSourceLanguage,
            onTargetLanguageChanged: provider.changeTargetLanguage,
            onSwapLanguages: provider.swapLanguages,
          ),
          const SizedBox(height: 18),
          TranslationCameraPreviewCard(
            cameraController: _cameraController,
            isCameraReady: isCameraReady,
            isCapturing: provider.status == TranslationStatus.capturing,
            isFlashOn: _isFlashOn,
            onToggleFlash: _toggleFlash,
            onCapture: _capturePhoto,
            onPickFromGallery: _pickImageFromGallery,
            onRetry: _retryCamera,
          ),
          const SizedBox(height: 18),
          Text(
            '촬영하거나 갤러리에서 선택한 이미지는 OCR 처리를 위해 사용됩니다. 현재 OCR은 기기 내 ML Kit 기능을 사용하며, 번역 API는 아직 연결하지 않았습니다.',
            style: TextStyle(fontSize: 13, height: 1.45, // 라이트/다크 모드에 맞는 보조 텍스트 색상
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
  // 번역 결과 뷰를 구성하는 위젯을 반환하는 메서드
  Widget _buildResultView(TranslationProvider provider) {
    return TranslationResultView(
      status: provider.status,
      selectedImagePath: provider.selectedImagePath,
      errorMessage: provider.errorMessage,
      recognizedText: provider.recognizedText,
      translatedText: provider.translatedText,
      isProcessing: provider.isProcessing,
      sourceLanguageCode: provider.sourceLanguageCode,
      targetLanguageCode: provider.targetLanguageCode,
      languages: provider.languages,
      onSourceLanguageChanged: provider.changeSourceLanguage,
      onTargetLanguageChanged: provider.changeTargetLanguage,
      onSwapLanguages: provider.swapLanguages,
      onRetake: _retake,
      onPickFromGallery: _pickImageFromGallery,
    );
  }
}
