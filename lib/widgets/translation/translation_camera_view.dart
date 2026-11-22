import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../providers/translation/translation_provider.dart';
import 'translation_camera_preview_card.dart';
import 'translation_header.dart';

/// 번역 화면의 카메라 대기 화면: 언어 막대, 미리보기 카드, 안내 문구.
class TranslationCameraView extends StatelessWidget {
  const TranslationCameraView({
    super.key,
    required this.state,
    required this.cameraController,
    required this.isCameraReady,
    required this.isFlashOn,
    required this.onSourceLanguageChanged,
    required this.onTargetLanguageChanged,
    required this.onSwapLanguages,
    required this.onToggleFlash,
    required this.onCapture,
    required this.onPickFromGallery,
    required this.onRetry,
  });

  /// 사진 속 글자를 어디서 읽는지 알리는 안내 문구.
  static const String privacyNote =
      '사진 속 글자는 기기에서 읽어요. 서버에는 읽은 글자만 보내고 사진은 보내지 않아요.';

  final TranslationState state;
  final CameraController? cameraController;
  final bool isCameraReady;
  final bool isFlashOn;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;
  final VoidCallback onSwapLanguages;
  final Future<void> Function() onToggleFlash;
  final Future<void> Function() onCapture;
  final Future<void> Function() onPickFromGallery;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslationHeader(
            sourceLanguageCode: state.sourceLanguageCode,
            targetLanguageCode: state.targetLanguageCode,
            languages: state.languages,
            onSourceLanguageChanged: onSourceLanguageChanged,
            onTargetLanguageChanged: onTargetLanguageChanged,
            onSwapLanguages: onSwapLanguages,
          ),
          const SizedBox(height: 18),
          TranslationCameraPreviewCard(
            cameraController: cameraController,
            isCameraReady: isCameraReady,
            isCapturing: state.status == TranslationStatus.capturing,
            isFlashOn: isFlashOn,
            onToggleFlash: onToggleFlash,
            onCapture: onCapture,
            onPickFromGallery: onPickFromGallery,
            onRetry: onRetry,
          ),
          const SizedBox(height: 18),
          Text(
            privacyNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
