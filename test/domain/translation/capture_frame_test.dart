import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/capture_frame.dart';

({String text, Rect box}) _line(String text, double cx, double cy) {
  return (
    text: text,
    box: Rect.fromCenter(center: Offset(cx, cy), width: 40, height: 10),
  );
}

void main() {
  group('regionInPhoto', () {
    test('3:4 사진이면 사진 가운데에 폭 78%·높이 42% 영역', () {
      final region = CaptureFrame.regionInPhoto(const Size(3000, 4000))!;

      expect(region.center, const Offset(1500, 2000));
      expect(region.width, closeTo(3000 * 0.78, 0.001));
      expect(region.height, closeTo(4000 * 0.42, 0.001));
    });

    test('세로로 긴 9:16 사진은 위아래가 잘려 보이므로 보이던 3:4 부분 기준', () {
      final region = CaptureFrame.regionInPhoto(const Size(900, 1600))!;
      // 보이던 부분: 폭 900, 높이 1200.
      expect(region.center, const Offset(450, 800));
      expect(region.width, closeTo(900 * 0.78, 0.001));
      expect(region.height, closeTo(1200 * 0.42, 0.001));
    });

    test('정사각형 사진은 좌우가 잘려 보이므로 보이던 3:4 부분 기준', () {
      final region = CaptureFrame.regionInPhoto(const Size(1200, 1200))!;
      // 보이던 부분: 폭 900, 높이 1200.
      expect(region.width, closeTo(900 * 0.78, 0.001));
      expect(region.height, closeTo(1200 * 0.42, 0.001));
    });

    test('크기가 0이면 null', () {
      expect(CaptureFrame.regionInPhoto(Size.zero), isNull);
    });

    test('3:4 사진 + 9:16 미리보기: 미리보기는 사진 좌우를 덜어 낸 영역이고 카드는 그 위아래를 자른다', () {
      final region = CaptureFrame.regionInPhoto(
        const Size(3000, 4000),
        cameraPreviewAspect: 9 / 16,
      )!;
      // 미리보기 영역: 2250x4000. 카드(3:4)에 보이던 부분: 2250x3000.
      expect(region.center, const Offset(1500, 2000));
      expect(region.width, closeTo(2250 * 0.78, 0.001));
      expect(region.height, closeTo(3000 * 0.42, 0.001));
    });

    test('9:16 사진 + 3:4 미리보기: 미리보기는 사진 위아래를 덜어 낸 영역', () {
      final region = CaptureFrame.regionInPhoto(
        const Size(900, 1600),
        cameraPreviewAspect: 3 / 4,
      )!;
      // 미리보기 영역: 900x1200. 카드와 비율이 같아 그대로 보인다.
      expect(region.center, const Offset(450, 800));
      expect(region.width, closeTo(900 * 0.78, 0.001));
      expect(region.height, closeTo(1200 * 0.42, 0.001));
    });

    test('미리보기 비율이 사진과 같으면 비율을 모를 때와 같다', () {
      expect(
        CaptureFrame.regionInPhoto(
          const Size(900, 1600),
          cameraPreviewAspect: 9 / 16,
        ),
        CaptureFrame.regionInPhoto(const Size(900, 1600)),
      );
    });

    test('미리보기 비율이 0 이하면 모를 때처럼 사진 기준', () {
      expect(
        CaptureFrame.regionInPhoto(
          const Size(3000, 4000),
          cameraPreviewAspect: 0,
        ),
        CaptureFrame.regionInPhoto(const Size(3000, 4000)),
      );
    });
  });

  group('portraitAspectOf', () {
    test('센서 방향(가로가 긴) 미리보기 크기를 세로 기준 비율로 바꾼다', () {
      expect(
        CaptureFrame.portraitAspectOf(const Size(1280, 720)),
        closeTo(9 / 16, 1e-9),
      );
      expect(
        CaptureFrame.portraitAspectOf(const Size(720, 1280)),
        closeTo(9 / 16, 1e-9),
      );
    });

    test('크기를 모르면 null', () {
      expect(CaptureFrame.portraitAspectOf(null), isNull);
      expect(CaptureFrame.portraitAspectOf(Size.zero), isNull);
    });
  });

  group('linesInFrame', () {
    // 3:4 세로 사진 3000x4000: 프레임은 x 330~2670, y 1160~2840.
    final lines = [
      _line('위쪽 간판', 1500, 300),
      _line('醤油ラーメン 980円', 1500, 1800),
      _line('왼쪽 끝 글씨', 100, 2000),
      _line('大盛り +150円', 1500, 2500),
      _line('아래 안내', 1500, 3800),
    ];

    test('가운데 점이 프레임 안에 있는 줄만 순서대로 고른다', () {
      expect(CaptureFrame.linesInFrame(lines, const Size(3000, 4000)), [
        '醤油ラーメン 980円',
        '大盛り +150円',
      ]);
    });

    test('파일에 가로로 저장된(방향 정보로 돌려 보는) 사진도 세로 기준으로 맞춘다', () {
      expect(CaptureFrame.linesInFrame(lines, const Size(4000, 3000)), [
        '醤油ラーメン 980円',
        '大盛り +150円',
      ]);
    });

    test('줄 위치가 세로 사진을 벗어나면(가로로 들고 찍음) 프레임을 쓰지 않는다', () {
      final landscape = [_line('가로 사진 글씨', 3800, 1500)];

      expect(
        CaptureFrame.linesInFrame(landscape, const Size(4000, 3000)),
        isNull,
      );
    });

    test('크기를 모르면 프레임을 쓰지 않는다', () {
      expect(CaptureFrame.linesInFrame(lines, Size.zero), isNull);
    });

    test('미리보기 비율을 주면 미리보기에서 잘려 안 보이던 좌우 줄은 뺀다', () {
      // 3000x4000 + 9:16 미리보기: 프레임은 x 622.5~2377.5, y 1370~2630.
      final wide = [
        _line('가운데', 1500, 2000),
        _line('왼쪽(사진=미리보기면 프레임 안)', 500, 2000),
      ];

      expect(CaptureFrame.linesInFrame(wide, const Size(3000, 4000)), [
        '가운데',
        '왼쪽(사진=미리보기면 프레임 안)',
      ]);
      expect(
        CaptureFrame.linesInFrame(
          wide,
          const Size(3000, 4000),
          cameraPreviewAspect: 9 / 16,
        ),
        ['가운데'],
      );
    });

    test('세로 사진을 벗어난 줄이 10% 미만이면 그 줄만 버리고 프레임을 쓴다', () {
      final withOutlier = [
        for (var i = 0; i < 9; i++) _line('안 $i', 1500, 1300 + i * 150.0),
        // 가운데 점은 프레임 안이지만 오른쪽 끝이 사진 폭을 크게 넘는 이상한 줄.
        (text: '이상한 줄', box: const Rect.fromLTRB(1000, 2000, 3500, 2010)),
      ];

      final result = CaptureFrame.linesInFrame(
        withOutlier,
        const Size(3000, 4000),
      );

      expect(result, hasLength(9));
      expect(result, isNot(contains('이상한 줄')));
    });

    test('세로 사진을 벗어난 줄이 10% 이상이면 프레임을 쓰지 않는다', () {
      final mixed = [
        for (var i = 0; i < 8; i++) _line('안 $i', 1500, 1300 + i * 150.0),
        _line('밖 1', 3800, 1500),
        _line('밖 2', 3800, 1700),
      ];

      expect(CaptureFrame.linesInFrame(mixed, const Size(4000, 3000)), isNull);
    });

    test('프레임 안에 줄이 없으면 빈 목록', () {
      expect(
        CaptureFrame.linesInFrame([
          _line('위쪽', 1500, 100),
        ], const Size(3000, 4000)),
        isEmpty,
      );
    });
  });

  group('selectLines', () {
    final lines = [_line('위쪽', 1500, 300), _line('가운데', 1500, 2000)];

    test('프레임을 맞추면 프레임 안 줄만, 적용 표시', () {
      final result = CaptureFrame.selectLines(lines, const Size(3000, 4000));

      expect(result.lines, ['가운데']);
      expect(result.frameApplied, isTrue);
    });

    test('사진 크기를 모르면 모든 줄, 미적용 표시', () {
      final result = CaptureFrame.selectLines(lines, null);

      expect(result.lines, ['위쪽', '가운데']);
      expect(result.frameApplied, isFalse);
    });

    test('가로로 든 사진이면 모든 줄, 미적용 표시', () {
      final landscape = [_line('가로 1', 3800, 1500), _line('가로 2', 2000, 1500)];
      final result = CaptureFrame.selectLines(
        landscape,
        const Size(4000, 3000),
      );

      expect(result.lines, ['가로 1', '가로 2']);
      expect(result.frameApplied, isFalse);
    });

    test('줄이 하나도 없으면 빈 목록이고 프레임은 적용한 것으로 본다', () {
      final result = CaptureFrame.selectLines(const [], const Size(3000, 4000));

      expect(result.lines, isEmpty);
      expect(result.frameApplied, isTrue);
    });
  });
}
