import 'dart:ui' show Offset, Rect, Size;

/// 프레임으로 고른 줄과 프레임을 실제로 적용했는지.
///
/// [frameApplied]가 false면 프레임을 맞출 수 없어 사진 전체의 줄을 담았다는 뜻이다.
typedef CaptureFrameLines = ({List<String> lines, bool frameApplied});

/// 번역 화면 카메라의 가이드 프레임(찍기 모드에서 이 안의 글자만 번역한다).
///
/// 카메라 미리보기 카드와 사진 속 인식 영역이 같은 값을 쓰도록 한곳에 둔다.
/// - 카드는 [previewAspectRatio](가로:세로 3:4)이고, 카메라 화면을 가운데 기준으로 잘라(cover) 채운다.
/// - 프레임은 카드 가운데에 카드 폭의 [widthFactor], 높이의 [heightFactor] 크기로 그린다.
abstract final class CaptureFrame {
  static const double previewAspectRatio = 3 / 4;
  static const double widthFactor = 0.78;
  static const double heightFactor = 0.42;

  /// 줄 위치 반올림·여백으로 사진 경계를 조금 넘을 수 있어 2%를 허용한다.
  static const double _boundsTolerance = 1.02;

  /// 세로 사진으로 볼 수 있는 최소 비율. 줄 중 이 비율 이상이 세로 사진 안에 들어맞으면 세로 사진으로 본다.
  ///
  /// 인식기가 사진 가장자리에서 경계를 넘는 줄을 가끔 돌려줘, 줄 하나 때문에 프레임 전체를 포기하지 않도록
  /// 전부(100%)가 아니라 90%로 둔다. 가로로 들고 찍은 사진은 줄 대부분이 세로 사진 폭을 넘어 이 기준에 걸린다.
  /// 들어맞지 않는 소수 줄은 프레임 밖으로 보고 버린다.
  static const double minFittingLineRatio = 0.9;

  /// 세로 카메라 미리보기 크기([previewSize], 센서 방향이라 가로가 길 수 있음)를 세로 기준 비율(짧은 변/긴 변)로
  /// 바꾼다. 크기를 모르거나 0 이하면 null.
  static double? portraitAspectOf(Size? previewSize) {
    if (previewSize == null ||
        previewSize.width <= 0 ||
        previewSize.height <= 0) {
      return null;
    }

    return previewSize.shortestSide / previewSize.longestSide;
  }

  /// 세로로 세운 사진(가로 [photo].width, 세로 [photo].height 픽셀)에서 프레임이 가리키는 영역.
  ///
  /// 가정: 미리보기와 사진은 중심이 같고, 미리보기는 사진 가운데를 [cameraPreviewAspect](세로 기준 가로/세로,
  /// 예: 9/16) 비율로 자른 화각이다(사진이 더 넓으면 좌우, 더 길면 위아래를 덜어 낸 최대 사각형).
  /// 카드는 그 미리보기 영역을 3:4로 가운데 잘라(cover) 보여 주고, 프레임은 카드에 보이던 부분 안의
  /// [widthFactor]×[heightFactor]다.
  ///
  /// [cameraPreviewAspect]를 모르면(null 또는 0 이하) 사진과 미리보기가 같은 화각이라고 본다.
  /// 사진 크기가 0 이하면 null.
  static Rect? regionInPhoto(Size photo, {double? cameraPreviewAspect}) {
    if (photo.width <= 0 || photo.height <= 0) {
      return null;
    }

    // 1. 사진 안에서 미리보기에 보이던 영역.
    final preview = _centerCrop(photo, cameraPreviewAspect);
    // 2. 그 미리보기 중 3:4 카드에 보이던 영역.
    final visible = _centerCrop(preview, previewAspectRatio);

    return Rect.fromCenter(
      center: photo.center(Offset.zero),
      width: visible.width * widthFactor,
      height: visible.height * heightFactor,
    );
  }

  /// [size] 가운데에서 [aspect](가로/세로) 비율로 자를 수 있는 가장 큰 크기.
  /// [aspect]가 없거나 0 이하면 [size] 그대로.
  static Size _centerCrop(Size size, double? aspect) {
    if (aspect == null || !aspect.isFinite || aspect <= 0) {
      return size;
    }

    if (size.width / size.height > aspect) {
      // 더 넓다: 좌우를 덜어 낸다.
      return Size(size.height * aspect, size.height);
    }

    // 더 길다: 위아래를 덜어 낸다.
    return Size(size.width, size.width / aspect);
  }

  /// 글자 인식 결과 중 가운데 점이 프레임 안에 있는 줄만 순서대로 고른다.
  ///
  /// [storedSize]는 파일에 저장된 사진 크기다. 사진은 방향 정보(EXIF)로 돌려 저장될 수 있어 가로세로가
  /// 뒤바뀌어 있을 수 있다. 인식기가 돌려준 줄 위치는 세워진 사진 기준이므로, 줄의 대부분
  /// ([minFittingLineRatio] 이상)이 세로 사진 안에 들어맞으면 세로 사진으로 본다. 들어맞지 않는 줄은 버린다.
  /// [cameraPreviewAspect]는 [regionInPhoto] 참고.
  ///
  /// 프레임을 적용할 수 없으면 null을 돌려준다(호출부는 모든 줄을 쓴다).
  /// - 사진 크기를 모름(0 이하)
  /// - 줄 위치가 세로 사진 안에 들어맞지 않음(가로로 들고 찍었거나 크기 정보가 맞지 않음). 프레임은 세로 화면의
  ///   미리보기 기준이라 가로 사진에는 맞출 수 없다.
  static List<String>? linesInFrame(
    List<({String text, Rect box})> lines,
    Size storedSize, {
    double? cameraPreviewAspect,
  }) {
    if (storedSize.width <= 0 || storedSize.height <= 0) {
      return null;
    }

    final portrait = portraitSizeOf(storedSize);

    bool fits(Rect box) {
      return box.right <= portrait.width * _boundsTolerance &&
          box.bottom <= portrait.height * _boundsTolerance;
    }

    final fitting = [
      for (final line in lines)
        if (fits(line.box)) line,
    ];

    if (lines.isNotEmpty &&
        fitting.length / lines.length < minFittingLineRatio) {
      return null;
    }

    final region = regionInPhoto(
      portrait,
      cameraPreviewAspect: cameraPreviewAspect,
    );

    if (region == null) {
      return null;
    }

    return <String>[
      for (final line in fitting)
        if (region.contains(line.box.center)) line.text,
    ];
  }

  /// [storedSize]가 있으면 프레임 안의 줄만 고르고, 프레임을 맞출 수 없거나 [storedSize]가 없으면 모든 줄을
  /// 돌려준다. [CaptureFrameLines.frameApplied]로 어느 쪽인지 알린다.
  static CaptureFrameLines selectLines(
    List<({String text, Rect box})> lines,
    Size? storedSize, {
    double? cameraPreviewAspect,
  }) {
    if (storedSize != null) {
      final inFrame = linesInFrame(
        lines,
        storedSize,
        cameraPreviewAspect: cameraPreviewAspect,
      );

      if (inFrame != null) {
        return (lines: inFrame, frameApplied: true);
      }
    }

    return (
      lines: <String>[for (final line in lines) line.text],
      frameApplied: false,
    );
  }

  /// 저장 크기의 짧은 변을 가로, 긴 변을 세로로 둔 세로 사진 크기.
  static Size portraitSizeOf(Size storedSize) {
    return Size(storedSize.shortestSide, storedSize.longestSide);
  }
}
