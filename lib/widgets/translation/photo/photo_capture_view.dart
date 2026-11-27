import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/translation/translation_provider.dart'
    show TranslationLanguage;
import '../../navigation/bottom_menu_capture_marks.dart';
import '../../navigation/navigation_capture_controller.dart';
import 'fake_translation_banner.dart';
import 'photo_language_pill.dart';

/// 번역 촬영 화면(목업 docs/mockups/translation-camera.html). 사진 번역 화면과 기존 번역 화면이 함께 쓴다.
///
/// 미리보기가 화면 전체를 채우고(cover), 위 가운데에 "Tripbler"와 언어 막대,
/// 하단 메뉴 원 양옆에 사진 고르기·플래시를 둔다. 촬영은 하단 메뉴의 현재 화면 버튼이 맡는다.
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
    this.fakeMode = false,
    this.navigationCapture,
    this.onSwapLanguages,
  });

  static const String brand = 'Tripbler';
  static const String shutterTooltip = '사진 찍기';
  static const String galleryTooltip = '갤러리에서 사진 고르기';
  static const String flashOnTooltip = '플래시 켜기';
  static const String flashOffTooltip = '플래시 끄기';

  final NavigationCaptureController? navigationCapture;
  final CameraController? cameraController;
  final bool isCameraReady;
  final bool isFlashOn;

  /// 촬영 중(앞 촬영이 기기에서 끝나지 않은 경우 포함)이면 셔터와 사진 고르기를 막는다.
  final bool isCapturing;
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslationLanguage> languages;
  final ValueChanged<String> onSourceLanguageChanged;
  final ValueChanged<String> onTargetLanguageChanged;
  final VoidCallback onToggleFlash;
  final VoidCallback onCapture;
  final VoidCallback onPickFromGallery;

  /// 개발용 가짜 번역 모드. 가짜 결과임을 알리는 띠를 하단 메뉴 위에 보인다.
  final bool fakeMode;

  /// 언어 바꾸기. 없으면 막대가 두 언어 변경 콜백으로 바꾼다.
  final VoidCallback? onSwapLanguages;

  // 촬영 화면은 미리보기 위에 그려 바탕이 늘 사진이라 앱 테마와 상관없이 어두운 테마로 그린다.
  static final ThemeData _theme = AppTheme.darkTheme;

  // 메뉴 없이 쓸 때(navigationCapture 없음)만 보이는 셔터 지름.
  static const double _shutterIconSize = 64;

  // 양옆 버튼 지름과 화면 가장자리에서 띄운 거리.
  static const double _sideSize = 48;
  static const double _sideInset = 28;

  // 사진 위에서도 글자가 읽히게 하는 그림자.
  static const List<Shadow> _textShadow = [
    Shadow(color: Color(0xB3000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  bool get _hasMenu => navigationCapture != null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = _theme.colorScheme;
    final text = _theme.textTheme;
    // 양옆 버튼은 하단 메뉴 원과 같은 높이(중심)에 둔다.
    final sideBottom = _hasMenu
        ? BottomMenuMetrics.iconCenter.dy - _sideSize / 2
        : 12 + (_shutterIconSize + 16 - _sideSize) / 2;
    // 가짜 모드 띠는 하단 메뉴 원 위에 둔다(촬영 안내 문구는 2026-11-27 사용자 요청으로 뺐다).
    final bannerBottom = _hasMenu
        ? BottomMenuMetrics.contentClearance
        : 12 + _shutterIconSize + 16 + 12;
    return Theme(
      data: _theme,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isCameraReady) _buildPreview(),
            // "Tripbler"와 언어 막대를 한 줄기로 쌓아, 글자 배율이 커져 제목이 높아지면 막대도 함께 내려가게 한다.
            Positioned(
              top: 22,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    brand,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      shadows: _textShadow,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 언어 이름이 길거나 화면이 좁아도 막대가 넘치지 않게 줄여 맞춘다.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: PhotoLanguagePill(
                      sourceLanguageCode: sourceLanguageCode,
                      targetLanguageCode: targetLanguageCode,
                      languages: languages,
                      onSourceLanguageChanged: onSourceLanguageChanged,
                      onTargetLanguageChanged: onTargetLanguageChanged,
                      onSwapLanguages: onSwapLanguages,
                    ),
                  ),
                ],
              ),
            ),
            if (fakeMode)
              Positioned(
                left: 16,
                right: 16,
                bottom: bannerBottom,
                child: NavigationCaptureControls(
                  controller: navigationCapture,
                  child: const FakeTranslationBanner(
                    message: FakeTranslationBanner.captureMessage,
                  ),
                ),
              ),
            Positioned(
              left: _sideInset,
              bottom: sideBottom,
              child: NavigationCaptureControls(
                controller: navigationCapture,
                child: _SideButton(
                  tooltip: galleryTooltip,
                  icon: Icons.photo_library_outlined,
                  onPressed: isCapturing ? null : onPickFromGallery,
                ),
              ),
            ),
            Positioned(
              right: _sideInset,
              bottom: sideBottom,
              child: NavigationCaptureControls(
                controller: navigationCapture,
                child: _SideButton(
                  tooltip: isFlashOn ? flashOffTooltip : flashOnTooltip,
                  icon: isFlashOn ? Icons.flash_on : Icons.flash_off,
                  selected: isFlashOn,
                  onPressed: isCameraReady ? onToggleFlash : null,
                ),
              ),
            ),
            if (!_hasMenu)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(child: _buildShutter(colorScheme)),
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

  Widget _buildShutter(ColorScheme colorScheme) {
    final shutterEnabled = isCameraReady && !isCapturing;
    // 촬영 중에는 셔터 자리에 진행 표시를 두어 눌렸음을 알린다.
    return IconButton(
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
    );
  }
}

/// 하단 메뉴 원 양옆의 반투명 원 버튼(48). 켜진 플래시는 노란 바탕으로 보인다.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  // 켜진 플래시는 카메라 앱에서 흔히 쓰는 노랑(목업 값)으로 보인다. 테마에 맞는 노랑이 없어 여기서 정한다.
  static const Color _selectedColor = Color(0xFFFFD54F);

  @override
  Widget build(BuildContext context) {
    // 촬영 화면의 어두운 테마: onSurface는 흰색에 가깝고 surface·scrim은 검정에 가깝다.
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(PhotoCaptureView._sideSize),
        backgroundColor: selected
            ? _selectedColor
            : colorScheme.scrim.withValues(alpha: .45),
        foregroundColor: selected ? colorScheme.surface : foreground,
        disabledBackgroundColor: colorScheme.scrim.withValues(alpha: .3),
        disabledForegroundColor: foreground.withValues(alpha: .38),
      ),
    );
  }
}
