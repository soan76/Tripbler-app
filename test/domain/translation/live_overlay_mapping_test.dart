import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/live_overlay_mapping.dart';

// 실시간 번역 좌표: 프레임 회전, 세운 영상 크기, 영상 → 카드 좌표 변환.
void main() {
  group('frameRotationDegrees', () {
    test('센서 90°인 후면 카메라: 세로 90°, 왼쪽 가로 0°, 오른쪽 가로 180°, 거꾸로 270°', () {
      int rotate(int device) => LiveOverlayMapping.frameRotationDegrees(
        sensorOrientation: 90,
        deviceRotationDegrees: device,
      );

      expect(rotate(0), 90);
      expect(rotate(90), 0);
      expect(rotate(270), 180);
      expect(rotate(180), 270);
    });

    test('전면 카메라는 센서 + 기기 방향', () {
      expect(
        LiveOverlayMapping.frameRotationDegrees(
          sensorOrientation: 270,
          deviceRotationDegrees: 90,
          isFrontCamera: true,
        ),
        0,
      );
    });
  });

  test('uprightImageSize: 90°·270°면 가로세로를 바꾼다', () {
    const frame = Size(1280, 720);
    expect(
      LiveOverlayMapping.uprightImageSize(frame, 90),
      const Size(720, 1280),
    );
    expect(
      LiveOverlayMapping.uprightImageSize(frame, 270),
      const Size(720, 1280),
    );
    expect(LiveOverlayMapping.uprightImageSize(frame, 0), frame);
  });

  group('transformFor', () {
    test('9:16 영상을 3:4 카드에 cover로 맞추면 위아래를 같은 만큼 잘라 낸다', () {
      final transform = LiveOverlayMapping.transformFor(
        imageSize: const Size(720, 1280),
        cardSize: const Size(300, 400),
        previewAspect: 9 / 16,
      )!;

      expect(transform.origin, const Offset(0, 160));
      expect(transform.scale, closeTo(300 / 720, 1e-9));

      final visible = transform.map(const Rect.fromLTRB(0, 160, 720, 1120));
      expect(visible.left, closeTo(0, 1e-9));
      expect(visible.top, closeTo(0, 1e-9));
      expect(visible.right, closeTo(300, 1e-9));
      expect(visible.bottom, closeTo(400, 1e-9));
    });

    test('미리보기 비율이 영상과 다르면 먼저 미리보기 화각으로 자른다', () {
      final transform = LiveOverlayMapping.transformFor(
        imageSize: const Size(960, 1280),
        cardSize: const Size(300, 400),
        previewAspect: 9 / 16,
      )!;

      expect(transform.origin, const Offset(120, 160));
      expect(transform.scale, closeTo(300 / 720, 1e-9));
    });

    test('크기가 0이면 null', () {
      expect(
        LiveOverlayMapping.transformFor(
          imageSize: Size.zero,
          cardSize: const Size(300, 400),
        ),
        isNull,
      );
    });
  });
}
