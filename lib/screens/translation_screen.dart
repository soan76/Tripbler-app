import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/translation_provider.dart';

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
      _checkCameraPermissionOnEntry();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCameraController();
    super.dispose();
  }

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

  Future<void> _initializeCamera() async {
    if (!mounted || _isCameraInitializing) {
      return;
    }

    final provider = context.read<TranslationProvider>();
    provider.setStatus(TranslationStatus.initializingCamera);

    _isCameraInitializing = true;

    try {
      await _disposeCameraController();

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

  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;

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

  Future<void> _capturePhoto() async {
    final controller = _cameraController;

    if (_isTakingPicture ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    _isTakingPicture = true;

    final provider = context.read<TranslationProvider>();
    provider.setStatus(TranslationStatus.capturing);

    try {
      final image = await controller.takePicture();

      if (!mounted) {
        return;
      }

      await provider.processImage(image.path);
    } catch (error, stackTrace) {
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

  Future<void> _pickImageFromGallery() async {
    if (context.read<TranslationProvider>().isProcessing) {
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

  Future<void> _toggleFlash() async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

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

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _retryCamera() async {
    await _checkCameraPermissionOnEntry();
  }

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
    return Consumer<TranslationProvider>(
      builder: (context, provider, _) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFC5E1A5),
          child: SafeArea(child: _buildBody(provider)),
        );
      },
    );
  }

  Widget _buildBody(TranslationProvider provider) {
    if (provider.hasImage ||
        provider.status == TranslationStatus.recognizing ||
        provider.status == TranslationStatus.translating ||
        provider.status == TranslationStatus.completed ||
        provider.status == TranslationStatus.failed) {
      return _buildResultView(provider);
    }

    switch (provider.status) {
      case TranslationStatus.checkingPermission:
        return _buildLoadingView('카메라 권한을 확인하고 있습니다.');

      case TranslationStatus.permissionRequired:
        return _buildInitialPermissionView();

      case TranslationStatus.permissionDenied:
        return _buildPermissionView(
          title: '카메라 권한이 허용되지 않았습니다',
          description: '카메라 번역을 사용하려면 카메라 권한을 허용해야 합니다.',
          primaryButtonText: '다시 권한 요청',
          onPrimaryPressed: _requestCameraPermission,
        );

      case TranslationStatus.permissionPermanentlyDenied:
        return _buildPermissionView(
          title: '설정에서 카메라 권한을 허용해 주세요',
          description:
              '카메라 권한이 차단되어 있습니다. 기기 설정에서 이 앱의 카메라 권한을 허용한 뒤 다시 돌아와 주세요.',
          primaryButtonText: '앱 설정 열기',
          onPrimaryPressed: _openSettings,
        );

      case TranslationStatus.initializingCamera:
        return _buildLoadingView('카메라를 준비하고 있습니다.');

      case TranslationStatus.cameraUnavailable:
        return _buildErrorView(
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

  Widget _buildInitialPermissionView() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          children: [
            const Spacer(),

            Image.asset(
              'assets/images/camera_permission.png',
              width: 180,
              height: 180,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 32),

            const Text(
              '번역을 위해 촬영 권한이 필요합니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _requestCameraPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  '접근 권한 허용',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionView({
    required String title,
    required String description,
    required String primaryButtonText,
    required VoidCallback onPrimaryPressed,
    String? bottomText,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                size: 56,
                color: Colors.black87,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPrimaryPressed,
                  child: Text(primaryButtonText),
                ),
              ),
              if (bottomText != null) ...[
                const SizedBox(height: 14),
                Text(
                  bottomText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(
    String message, {
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 52,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onPressed, child: Text(buttonText)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraView(TranslationProvider provider) {
    final isCameraReady =
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        provider.status != TranslationStatus.capturing;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(provider),
          const SizedBox(height: 18),
          _buildCameraPreviewCard(
            isCameraReady: isCameraReady,
            isCapturing: provider.status == TranslationStatus.capturing,
          ),
          const SizedBox(height: 18),
          const Text(
            '촬영하거나 갤러리에서 선택한 이미지는 OCR 처리를 위해 사용됩니다. 현재 OCR은 기기 내 ML Kit 기능을 사용하며, 번역 API는 아직 연결하지 않았습니다.',
            style: TextStyle(fontSize: 13, height: 1.45, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(TranslationProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '카메라 번역',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildLanguageDropdown(
                label: '원문',
                value: provider.sourceLanguageCode,
                languages: provider.languages,
                onChanged: provider.changeSourceLanguage,
              ),
            ),
            IconButton(
              onPressed: provider.sourceLanguageCode == 'auto'
                  ? null
                  : provider.swapLanguages,
              icon: const Icon(Icons.swap_horiz),
            ),
            Expanded(
              child: _buildLanguageDropdown(
                label: '번역',
                value: provider.targetLanguageCode,
                languages: provider.languages
                    .where((language) => language.code != 'auto')
                    .toList(),
                onChanged: provider.changeTargetLanguage,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLanguageDropdown({
    required String label,
    required String value,
    required List<TranslationLanguage> languages,
    required ValueChanged<String> onChanged,
  }) {
    final safeValue = languages.any((language) => language.code == value)
        ? value
        : languages.first.code;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          items: languages.map((language) {
            return DropdownMenuItem<String>(
              value: language.code,
              child: Text('$label: ${language.label}'),
            );
          }).toList(),
          onChanged: (selectedValue) {
            if (selectedValue == null) {
              return;
            }

            onChanged(selectedValue);
          },
        ),
      ),
    );
  }

  Widget _buildCameraPreviewCard({
    required bool isCameraReady,
    required bool isCapturing,
  }) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isCameraReady) _buildCameraPreview(),
              if (!isCameraReady)
                const Center(child: CircularProgressIndicator()),
              _buildGuideFrame(),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Text(
                  '번역할 문자가 프레임 안에 들어오도록 촬영해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: IconButton.filledTonal(
                  onPressed: isCameraReady ? _toggleFlash : null,
                  icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 22,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filled(
                      onPressed: isCameraReady ? _pickImageFromGallery : null,
                      iconSize: 30,
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                    GestureDetector(
                      onTap: isCameraReady && !isCapturing
                          ? _capturePhoto
                          : null,
                      child: Container(
                        width: 76,
                        height: 76,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCapturing ? Colors.grey : Colors.white,
                          ),
                          child: isCapturing
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: _retryCamera,
                      iconSize: 30,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraController!;

    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return CameraPreview(controller);
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildGuideFrame() {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.78,
        heightFactor: 0.42,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.95), width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildResultView(TranslationProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(provider),
          const SizedBox(height: 18),
          if (provider.selectedImagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                File(provider.selectedImagePath!),
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 18),
          if (provider.status == TranslationStatus.recognizing)
            _buildProcessingCard('문자를 인식하고 있습니다.'),
          if (provider.status == TranslationStatus.translating)
            _buildProcessingCard('번역하고 있습니다.'),
          if (provider.errorMessage != null)
            _buildMessageCard(
              message: provider.errorMessage!,
              icon: Icons.info_outline,
            ),
          if (provider.recognizedText.trim().isNotEmpty)
            _buildTextCard(title: '인식된 원문', text: provider.recognizedText),
          if (provider.translatedText.trim().isNotEmpty)
            _buildTextCard(title: '번역 결과', text: provider.translatedText),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: provider.isProcessing ? null : _retake,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('다시 촬영'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: provider.isProcessing
                      ? null
                      : _pickImageFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('다시 선택'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingCard(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard({required String message, required IconData icon}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCard({required String title, required String text}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
