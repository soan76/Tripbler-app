import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/translation/capture_frame.dart';

// 카메라 미리보기, 플래시, 촬영, 갤러리, 새로고침 버튼
// 번역 화면에서 카메라 프리뷰를 표시하는 카드 위젯
//
// 색 사용: 카메라 화면 위에 겹쳐 그리는 오버레이라 앱 테마(라이트/다크)와 상관없이
// 바탕이 늘 사진이다. 그래서 바탕·어둡게 덮는 막은 검정, 글자·프레임·촬영 버튼은
// 흰색으로 고정해 어떤 장면에서도 대비를 유지한다. 버튼 아이콘색은 테마를 따른다.
class TranslationCameraPreviewCard extends StatelessWidget {
  final CameraController? cameraController;
  final bool isCameraReady;
  final bool isCapturing;
  final bool isFlashOn;
  final Future<void> Function() onToggleFlash;
  final Future<void> Function() onCapture;
  final Future<void> Function() onPickFromGallery;
  final Future<void> Function() onRetry;

  const TranslationCameraPreviewCard({
    super.key,
    required this.cameraController,
    required this.isCameraReady,
    required this.isCapturing,
    required this.isFlashOn,
    required this.onToggleFlash,
    required this.onCapture,
    required this.onPickFromGallery,
    required this.onRetry,
  });

  /// 안내 문구. 프레임이 실제 인식 범위임을 알린다.
  static const String guideText = '프레임 안의 글자만 번역해요';

  // 프레임 밖을 덮는 막의 진하기. 프레임 밖 장면도 알아볼 수 있을 만큼만 어둡게 한다.
  static const double _scrimAlpha = 0.5;

  // 프레임 선 두께.
  static const double _frameStroke = 2;

  // 카드 안쪽 여백(안내 줄과 버튼 줄).
  static const double _inset = 12;

  // 촬영 버튼 지름. 터치 영역 48dp보다 넉넉하게 둔다.
  static const double _shutterSize = 72;

  // 카드 높이가 고정 비율이라 안내 문구가 커져도 프레임 위 공간을 넘지 않도록 상한을 둔다.
  // 1.5배까지는 키운 글자 크기를 따르고, 넘는 부분은 2줄 + 말줄임으로 처리한다.
  static const double _maxGuideTextScale = 1.5;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: CaptureFrame.previewAspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
        child: ColoredBox(
          color: Colors.black,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final frameRect = _frameRect(size);

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (isCameraReady) _buildCameraPreview(),
                  if (!isCameraReady)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        semanticsLabel: '카메라 준비 중',
                      ),
                    ),
                  // 프레임 밖을 어둡게 덮고 프레임 선을 그린다.
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _FrameOverlayPainter(
                        frameRect: frameRect,
                        scrimColor: Colors.black.withValues(alpha: _scrimAlpha),
                        frameColor: Colors.white,
                        strokeWidth: _frameStroke,
                        radius: AppTheme.cornerRadius,
                      ),
                    ),
                  ),
                  // 위쪽: 안내 문구 + 플래시. 프레임 위 공간 안에만 둔다.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: frameRect.top,
                    child: _buildTopBar(context),
                  ),
                  // 아래쪽: 갤러리 · 촬영 · 다시 시도. 프레임 아래 공간 안에만 둔다.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: size.height - frameRect.bottom,
                    child: _buildBottomBar(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // 카드 크기에서 프레임 영역을 계산한다. CaptureFrame과 같은 비율·가운데 정렬이라
  // 사진에서 읽는 영역(CaptureFrame.regionInPhoto)과 맞는다.
  static Rect _frameRect(Size size) {
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * CaptureFrame.widthFactor,
      height: size.height * CaptureFrame.heightFactor,
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(color: Colors.white);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_inset + 4, 8, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              // 플래시 버튼(48dp) 가운데 높이에 첫 줄을 맞춘다.
              padding: const EdgeInsets.only(top: 12),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: _maxGuideTextScale,
                child: Text(
                  guideText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: isFlashOn ? '플래시 끄기' : '플래시 켜기',
            isSelected: isFlashOn,
            onPressed: isCameraReady
                ? () {
                    onToggleFlash();
                  }
                : null,
            icon: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    // 아주 작은 카드(폭 약 150dp 이하)에서는 버튼 셋이 들어갈 자리가 모자라 넘친다.
    // 버튼 줄을 최소 크기 이상으로 배치한 뒤 칸에 맞게 줄여(scaleDown) 넘치지 않게 한다.
    // 보통 크기 카드에서는 줄일 필요가 없어 배치가 그대로다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < _bottomBarMinWidth
            ? _bottomBarMinWidth
            : constraints.maxWidth;
        final height = constraints.maxHeight < _shutterSize
            ? _shutterSize
            : constraints.maxHeight;

        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: width,
            height: height,
            child: _buildBottomButtons(),
          ),
        );
      },
    );
  }

  // 아래 버튼 줄이 넘치지 않는 최소 폭: 버튼(48 + 촬영 버튼 + 48)과 사이 여백.
  static const double _bottomBarMinWidth = 48 + _shutterSize + 48 + 4 * 8;

  Widget _buildBottomButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton.filled(
          tooltip: '갤러리에서 사진 고르기',
          onPressed: isCameraReady
              ? () {
                  onPickFromGallery();
                }
              : null,
          iconSize: 28,
          icon: const Icon(Icons.photo_library_outlined),
        ),
        _ShutterButton(
          size: _shutterSize,
          isCapturing: isCapturing,
          onPressed: isCameraReady && !isCapturing
              ? () {
                  onCapture();
                }
              : null,
        ),
        IconButton.filled(
          tooltip: '카메라 다시 켜기',
          onPressed: () {
            onRetry();
          },
          iconSize: 28,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  // 카메라 프리뷰를 구성하는 위젯을 반환하는 메서드
  Widget _buildCameraPreview() {
    final controller = cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final previewSize = controller.value.previewSize;

    // 미리보기 크기를 모르면 카드를 cover로 채울 수 없다. `CameraPreview`도 크기로 비율을 계산하므로
    // (`controller.value.aspectRatio`가 previewSize를 씀) 그리지 않는다. 이때 촬영은 프레임을 쓰지 않고
    // 사진 전체를 읽는다(화면이 미리보기 비율을 null로 넘김).
    if (previewSize == null) {
      return const SizedBox.shrink();
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
}

// 카메라 셔터 버튼. 카메라 앱에서 익숙한 원형(흰 테두리 + 흰 원)을 쓴다.
// 아이콘만 있는 버튼이라 원형 예외에 해당한다.
class _ShutterButton extends StatelessWidget {
  final double size;
  final bool isCapturing;
  final VoidCallback? onPressed;

  const _ShutterButton({
    required this.size,
    required this.isCapturing,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // 카메라가 준비되지 않았을 때는 흐리게 해 누를 수 없음을 보인다.
    final ringColor = Colors.white.withValues(alpha: enabled ? 1 : 0.5);
    final fillColor = Colors.white.withValues(
      alpha: isCapturing ? 0.5 : (enabled ? 1 : 0.4),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: isCapturing ? '사진 찍는 중' : '사진 찍기',
      excludeSemantics: true,
      child: Tooltip(
        message: '사진 찍기',
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 4),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fillColor,
                  ),
                  child: isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 프레임 밖을 어둡게 덮고 프레임 테두리를 그린다.
class _FrameOverlayPainter extends CustomPainter {
  final Rect frameRect;
  final Color scrimColor;
  final Color frameColor;
  final double strokeWidth;
  final double radius;

  const _FrameOverlayPainter({
    required this.frameRect,
    required this.scrimColor,
    required this.frameColor,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(frameRect, Radius.circular(radius));

    // 카드 전체에서 프레임 부분을 뺀 영역만 칠한다.
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(frame);
    canvas.drawPath(scrim, Paint()..color = scrimColor);

    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = frameColor,
    );
  }

  @override
  bool shouldRepaint(_FrameOverlayPainter oldDelegate) {
    return oldDelegate.frameRect != frameRect ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.frameColor != frameColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}
