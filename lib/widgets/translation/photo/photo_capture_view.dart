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

  // 촬영 화면은 미리보기 위에 그려 바탕이 늘 사진이라 앱 테마와 상관없이 어두운 테마로 그린다.
  static final ThemeData _theme = AppTheme.darkTheme;

  // 셔터 지름. 엄지로 바로 누를 수 있게 터치 영역 48dp보다 넉넉하게 둔다.
  static const double _shutterIconSize = 64;

  @override
  Widget build(BuildContext context) {
    final colorScheme = _theme.colorScheme;
    return Theme(
      data: _theme,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isCameraReady) _buildPreview(),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _LanguageBar(
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                languages: languages,
                onSourceLanguageChanged: onSourceLanguageChanged,
                onTargetLanguageChanged: onTargetLanguageChanged,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildControls(colorScheme),
            ),
          ],
        ),
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

  // 아래 막대: 갤러리 · 셔터 · 플래시, 그 아래 전송 안내. 사진 위에서도 읽히게 단색으로 어둡게 덮는다.
  Widget _buildControls(ColorScheme colorScheme) {
    final shutterEnabled = isCameraReady && !isCapturing;
    return ColoredBox(
      color: colorScheme.scrim.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  tooltip: galleryTooltip,
                  onPressed: isCapturing ? null : onPickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                ),
                // 촬영 중에는 셔터 자리에 진행 표시를 두어 눌렸음을 알린다.
                IconButton(
                  tooltip: shutterTooltip,
                  iconSize: _shutterIconSize,
                  color: colorScheme.onSurface,
                  disabledColor: colorScheme.onSurface.withValues(alpha: 0.38),
                  onPressed: shutterEnabled ? onCapture : null,
                  icon: isCapturing
                      ? const SizedBox.square(
                          dimension: _shutterIconSize,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                        )
                      : const Icon(Icons.radio_button_checked),
                ),
                IconButton.filledTonal(
                  tooltip: isFlashOn ? flashOffTooltip : flashOnTooltip,
                  isSelected: isFlashOn,
                  onPressed: isCameraReady ? onToggleFlash : null,
                  icon: const Icon(Icons.flash_off),
                  selectedIcon: const Icon(Icons.flash_on),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notice,
              textAlign: TextAlign.center,
              style: _theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
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

  static const String sourceLabel = '원문 언어';
  static const String targetLabel = '번역 언어';

  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targets = languages.where((language) => language.code != 'auto');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.scrim.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: _dropdown(
                theme,
                sourceLabel,
                sourceLanguageCode,
                languages,
                onSourceLanguageChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            Expanded(
              child: _dropdown(
                theme,
                targetLabel,
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
    ThemeData theme,
    String label,
    String value,
    List<TranslationLanguage> options,
    ValueChanged<String> onChanged,
  ) {
    final safeValue = options.any((language) => language.code == value)
        ? value
        : options.first.code;
    // 낭독기가 어느 쪽 언어인지 알 수 있게 이름을 붙인다.
    return Semantics(
      label: label,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
          dropdownColor: theme.colorScheme.surfaceContainerHigh,
          iconEnabledColor: theme.colorScheme.onSurface,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
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
      ),
    );
  }
}
