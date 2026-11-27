import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../providers/translation/translation_provider.dart';
import '../navigation/navigation_capture_controller.dart';
import 'photo/photo_capture_view.dart';

/// 기존 번역 화면의 카메라 대기 화면. 목업(docs/mockups/translation-camera.html)대로 카메라가 화면 전체를
/// 채우고, 사진 번역 화면과 같은 배치([PhotoCaptureView])를 쓴다. 찍은 사진은 프레임 없이 전체를 읽는다.
class TranslationCameraView extends StatelessWidget {
  const TranslationCameraView({
    super.key,
    this.navigationCapture,
    required this.state,
    required this.cameraController,
    required this.isCameraReady,
    required this.isFlashOn,
    this.isCaptureInFlight = false,
    required this.onSourceLanguageChanged,
    required this.onTargetLanguageChanged,
    required this.onSwapLanguages,
    required this.onToggleFlash,
    required this.onCapture,
    required this.onPickFromGallery,
  });

  final NavigationCaptureController? navigationCapture;
  final TranslationState state;
  final CameraController? cameraController;
  final bool isCameraReady;
  final bool isFlashOn;

  /// 앞 촬영이 기기에서 아직 끝나지 않았는지(시간 제한 뒤 포함). 이때 셔터는 촬영 중처럼 비활성이다.
  final bool isCaptureInFlight;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;
  final VoidCallback onSwapLanguages;
  final Future<void> Function() onToggleFlash;
  final Future<void> Function() onCapture;
  final Future<void> Function() onPickFromGallery;

  @override
  Widget build(BuildContext context) {
    return PhotoCaptureView(
      navigationCapture: navigationCapture,
      cameraController: cameraController,
      isCameraReady: isCameraReady,
      isFlashOn: isFlashOn,
      isCapturing:
          state.status == TranslationStatus.capturing || isCaptureInFlight,
      sourceLanguageCode: state.sourceLanguageCode,
      targetLanguageCode: state.targetLanguageCode,
      languages: state.languages,
      onSourceLanguageChanged: onSourceLanguageChanged,
      onTargetLanguageChanged: onTargetLanguageChanged,
      onSwapLanguages: onSwapLanguages,
      onToggleFlash: () => onToggleFlash(),
      onCapture: () => onCapture(),
      onPickFromGallery: () => onPickFromGallery(),
    );
  }
}
