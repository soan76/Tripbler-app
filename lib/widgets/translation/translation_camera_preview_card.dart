import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
// 카메라 미리보기, 플래시, 촬영, 갤러리, 새로고침 버튼
// 번역 화면에서 카메라 프리뷰를 표시하는 카드 위젯
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

  @override
  Widget build(BuildContext context) {
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
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // 플래시 버튼
              Positioned(
                top: 20,
                right: 14,
                child: IconButton.filledTonal(
                  onPressed: isCameraReady
                      ? () {
                          onToggleFlash();
                        }
                      : null,
                  icon: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off),
                ),
              ),
              // 하단 버튼 영역
              Positioned(
                left: 0,
                right: 0,
                bottom: 22,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filled(
                      onPressed: isCameraReady
                          ? () {
                              onPickFromGallery();
                            }
                          : null,
                      iconSize: 30,
                      icon: const Icon(Icons.photo_library_outlined),
                    ),

                    // 촬영 버튼
                    GestureDetector(
                      onTap: isCameraReady && !isCapturing
                          ? () {
                              onCapture();
                            }
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
                      onPressed: () {
                        onRetry();
                      },
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
  // 카메라 프리뷰를 구성하는 위젯을 반환하는 메서드
  Widget _buildCameraPreview() {
    final controller = cameraController;

    if (controller == null || !controller.value.isInitialized) {
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
  // 가이드 프레임을 구성하는 위젯을 반환하는 메서드
  Widget _buildGuideFrame() {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.78,
        heightFactor: 0.42,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.95), width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
