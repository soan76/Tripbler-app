import 'dart:ui' show Offset, Rect, Size;

import 'capture_frame.dart';

/// 실시간 번역의 줄 위치를 미리보기 카드 좌표로 옮기는 계산.
///
/// 좌표 흐름:
/// 1. 카메라 프레임(센서 방향, 예: 1280×720)을 ML Kit에 회전값과 함께 넘기면, 인식한 줄 위치는 회전을
///    적용해 세운 영상 좌표(예: 720×1280)로 돌아온다([uprightImageSize]).
/// 2. 미리보기는 세운 영상과 중심이 같고, 세운 영상 가운데를 미리보기 비율로 자른 화각이라고 본다.
/// 3. 카드는 그 미리보기를 [CaptureFrame.previewAspectRatio](3:4)로 가운데 잘라(cover) 채운다.
///
/// Android 실기기(분석·미리보기 1280×720)에서 멈춘 상태의 위치가 글자와 맞는 것을 확인한 식이다.
abstract final class LiveOverlayMapping {
  /// Android 카메라 프레임을 세우는 데 필요한 시계 방향 회전(0·90·180·270).
  ///
  /// CameraX ImageAnalysis는 버퍼를 돌리지 않고 센서 방향 그대로 보낸다. 기기를 [deviceRotationDegrees]만큼
  /// 돌려 들면 그만큼 덜 돌린다. 후면은 `(센서 - 기기 + 360) % 360`, 전면은 거울상이라 `(센서 + 기기) % 360`
  /// (ML Kit 공식 예제의 계산).
  static int frameRotationDegrees({
    required int sensorOrientation,
    required int deviceRotationDegrees,
    bool isFrontCamera = false,
  }) {
    final rotation = isFrontCamera
        ? sensorOrientation + deviceRotationDegrees
        : sensorOrientation - deviceRotationDegrees + 360;
    return rotation % 360;
  }

  /// 프레임 회전값을 적용해 세운 영상 크기. 90·270이면 가로세로를 바꾼다.
  static Size uprightImageSize(Size frameSize, int rotationDegrees) {
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      return Size(frameSize.height, frameSize.width);
    }
    return frameSize;
  }

  /// 세운 영상([imageSize]) 좌표를 [cardSize] 카드 좌표로 바꾸는 변환.
  ///
  /// [previewAspect]는 미리보기의 세로 기준 비율(짧은 변/긴 변, [CaptureFrame.portraitAspectOf])이다.
  /// 모르면 영상과 미리보기가 같은 화각이라고 본다. 크기가 0 이하면 null.
  static LiveOverlayTransform? transformFor({
    required Size imageSize,
    required Size cardSize,
    double? previewAspect,
  }) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        cardSize.width <= 0 ||
        cardSize.height <= 0) {
      return null;
    }

    // 1. 영상 안에서 미리보기에 보이던 영역.
    final preview = _centerCrop(imageSize, previewAspect);
    // 2. 그 미리보기 중 카드에 보이던 영역(카드 비율로 가운데 자름 = cover).
    final visible = _centerCrop(preview, cardSize.width / cardSize.height);

    return LiveOverlayTransform(
      origin: Offset(
        (imageSize.width - visible.width) / 2,
        (imageSize.height - visible.height) / 2,
      ),
      scale: cardSize.width / visible.width,
    );
  }

  /// [size] 가운데에서 [aspect](가로/세로) 비율로 자를 수 있는 가장 큰 크기.
  static Size _centerCrop(Size size, double? aspect) {
    if (aspect == null || !aspect.isFinite || aspect <= 0) {
      return size;
    }
    if (size.width / size.height > aspect) {
      return Size(size.height * aspect, size.height);
    }
    return Size(size.width, size.width / aspect);
  }
}

/// 세운 영상 좌표 → 카드 좌표 변환(평행 이동 뒤 같은 비율 확대).
class LiveOverlayTransform {
  const LiveOverlayTransform({required this.origin, required this.scale});

  /// 카드 왼쪽 위에 보이는 영상 좌표.
  final Offset origin;

  /// 영상 1픽셀이 카드에서 차지하는 길이.
  final double scale;

  /// 영상 좌표의 [box]를 카드 좌표로 바꾼다. 카드 밖으로 나갈 수 있다(그리는 쪽이 잘라 낸다).
  Rect map(Rect box) {
    return Rect.fromLTRB(
      (box.left - origin.dx) * scale,
      (box.top - origin.dy) * scale,
      (box.right - origin.dx) * scale,
      (box.bottom - origin.dy) * scale,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveOverlayTransform &&
      other.origin == origin &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(origin, scale);
}
