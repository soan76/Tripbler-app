import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/translation/translation_provider.dart'
    show TranslationLanguage;

/// 사진 번역 촬영 화면: 미리보기가 화면 전체를 채우고(cover), 위에 언어 막대, 아래에 셔터·갤러리·플래시와
/// 고정 안내를 둔다.
class PhotoCaptureView extends StatelessWidget {
  const PhotoCaptureView({
    super.key,
    required this.cameraController,
    required this.isCameraReady,
    required this.isFlashOn,
    required this.isCapturing,
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.languages,
    required this.onSourceLanguageChanged,
    required this.onTargetLanguageChanged,
    required this.onToggleFlash,
    required this.onCapture,
    required this.onPickFromGallery,
  });

  /// 하단 고정 안내. 보관·삭제·학습 여부는 정책을 확인한 뒤 따로 정한다.
  static const String notice = '촬영한 사진은 AI 번역을 위해 전송됩니다';
  static const String shutterTooltip = '사진 찍기';
  static const String galleryTooltip = '갤러리에서 사진 고르기';
  static const String flashOnTooltip = '플래시 켜기';
  static const String flashOffTooltip = '플래시 끄기';

  final CameraController? cameraController;
  final bool isCameraReady;
  final bool isFlashOn;

  /// 촬영 중(앞 촬영이 기기에서 끝나지 않은 경우 포함)이면 셔터를 막는다.
  final bool isCapturing;
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;
  final VoidCallback onToggleFlash;
  final VoidCallback onCapture;
  final VoidCallback onPickFromGallery;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isCameraReady) _buildPreview(),
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: _LanguageBar(
              sourceLanguageCode: sourceLanguageCode,
              targetLanguageCode: targetLanguageCode,
              languages: languages,
              onSourceLanguageChanged: onSourceLanguageChanged,
              onTargetLanguageChanged: onTargetLanguageChanged,
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildControls()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final controller = cameraController;
    final previewSize = controller?.value.previewSize;
    if (controller == null ||
        !controller.value.isInitialized ||
        previewSize == null) {
      return const SizedBox.shrink();
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // 높이는 CameraPreview가 현재 기기 방향의 비율로 정한다.
          width: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildControls() {
    const white = Colors.white;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black54),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: galleryTooltip,
                  color: white,
                  onPressed: isCapturing ? null : onPickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                ),
                IconButton(
                  tooltip: shutterTooltip,
                  iconSize: 64,
                  color: white,
                  onPressed: isCameraReady && !isCapturing ? onCapture : null,
                  icon: const Icon(Icons.radio_button_checked),
                ),
                IconButton(
                  tooltip: isFlashOn ? flashOffTooltip : flashOnTooltip,
                  color: white,
                  onPressed: isCameraReady ? onToggleFlash : null,
                  icon: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              notice,
              textAlign: TextAlign.center,
              style: TextStyle(color: white),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageBar extends StatelessWidget {
  const _LanguageBar({
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.languages,
    required this.onSourceLanguageChanged,
    required this.onTargetLanguageChanged,
  });

  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final targets = languages.where((language) => language.code != 'auto');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: _dropdown(
                sourceLanguageCode,
                languages,
                onSourceLanguageChanged,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ),
            Expanded(
              child: _dropdown(
                targetLanguageCode,
                targets.toList(),
                onTargetLanguageChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(
    String value,
    List<TranslationLanguage> options,
    ValueChanged<String> onChanged,
  ) {
    final safeValue = options.any((language) => language.code == value)
        ? value
        : options.first.code;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: safeValue,
        isExpanded: true,
        dropdownColor: Colors.black87,
        iconEnabledColor: Colors.white,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        items: [
          for (final language in options)
            DropdownMenuItem(
              value: language.code,
              child: Text(language.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (selected) {
          if (selected != null) {
            onChanged(selected);
          }
        },
      ),
    );
  }
}
