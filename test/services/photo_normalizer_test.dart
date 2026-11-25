import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tripbler/services/photo_normalizer.dart';

/// 왼쪽 위 모서리에 빨간 점이 있는 JPEG 파일을 만든다([orientation]이 있으면 EXIF 방향을 넣는다).
File _writeJpeg(Directory dir, int width, int height, {int? orientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 39,
    y2: 39,
    color: img.ColorRgb8(255, 0, 0),
  );
  if (orientation != null) {
    image.exif.imageIfd.orientation = orientation;
  }
  final file = File('${dir.path}/source_${width}x$height.jpg');
  file.writeAsBytesSync(img.encodeJpg(image, quality: 95));
  return file;
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var matched = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return i;
    }
  }
  return -1;
}

bool _isReddish(img.Pixel p) => p.r > 180 && p.g < 90 && p.b < 90;

void main() {
  late Directory dir;
  late PhotoNormalizer normalizer;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('photo_normalizer_test');
    normalizer = PhotoNormalizer();
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  Future<img.Image> normalizeAndDecode(File source) async {
    final result = await normalizer.normalize(
      sourcePath: source.path,
      outputDirectory: dir.path,
    );
    final decoded = img.decodeJpg(File(result.path).readAsBytesSync())!;
    expect(decoded.width, result.width);
    expect(decoded.height, result.height);
    return decoded;
  }

  test('orientation6_isBakedUpright', () async {
    final decoded = await normalizeAndDecode(
      _writeJpeg(dir, 400, 300, orientation: 6),
    );

    expect(decoded.width, 300);
    expect(decoded.height, 400);
    // 원본 왼쪽 위 빨간 점이 오른쪽 위로 간다.
    expect(_isReddish(decoded.getPixel(decoded.width - 15, 15)), isTrue);
    expect(_isReddish(decoded.getPixel(15, 15)), isFalse);
  });

  test('orientation8_isBakedUpright', () async {
    final decoded = await normalizeAndDecode(
      _writeJpeg(dir, 400, 300, orientation: 8),
    );

    expect(decoded.width, 300);
    expect(decoded.height, 400);
    // 반시계 90도 회전이면 왼쪽 위 점이 왼쪽 아래로 간다.
    expect(_isReddish(decoded.getPixel(15, decoded.height - 15)), isTrue);
    expect(_isReddish(decoded.getPixel(15, 15)), isFalse);
  });

  test('largePhoto_longSideScaledTo2048', () async {
    final result = await normalizer.normalize(
      sourcePath: _writeJpeg(dir, 4032, 3024).path,
      outputDirectory: dir.path,
    );

    expect(result.width, 2048);
    expect(result.height, 1536);
  });

  test('smallPhoto_notUpscaled', () async {
    final result = await normalizer.normalize(
      sourcePath: _writeJpeg(dir, 400, 300).path,
      outputDirectory: dir.path,
    );

    expect(result.width, 400);
    expect(result.height, 300);
  });

  test('outputHasNoExifOrientation', () async {
    final decoded = await normalizeAndDecode(
      _writeJpeg(dir, 400, 300, orientation: 6),
    );

    expect(decoded.exif.imageIfd.hasOrientation, isFalse);
  });

  test('outputHasNoExifAtAll_evenWithGpsAndCameraInfo', () async {
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    image.exif.imageIfd.orientation = 6;
    image.exif.imageIfd.make = 'TestCamera';
    image.exif.gpsIfd.gpsLatitude = 37.5665;
    image.exif.gpsIfd.gpsLongitude = 126.978;
    final source = File('${dir.path}/source_gps.jpg')
      ..writeAsBytesSync(img.encodeJpg(image, quality: 95));
    // 원본에는 GPS가 실제로 들어 있다(전제 확인).
    final sourceExif = img.decodeJpg(source.readAsBytesSync())!.exif;
    expect(sourceExif.gpsIfd.hasGPSLatitude, isTrue);

    final result = await normalizer.normalize(
      sourcePath: source.path,
      outputDirectory: dir.path,
    );
    final bytes = File(result.path).readAsBytesSync();

    // EXIF APP1 서명("Exif\0\0")이 파일에 없고, 다시 읽어도 EXIF가 비어 있다.
    expect(_indexOf(bytes, const [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]), -1);
    expect(img.decodeJpg(bytes)!.exif.isEmpty, isTrue);
  });

  test('nonImageFile_throwsUnsupportedPhotoException', () async {
    final file = File('${dir.path}/not_image.jpg')
      ..writeAsStringSync('이건 사진이 아니다');

    expect(
      normalizer.normalize(sourcePath: file.path, outputDirectory: dir.path),
      throwsA(isA<UnsupportedPhotoException>()),
    );
  });

  test('delete_missingFileIsNoop', () async {
    await normalizer.delete(
      const NormalizedPhoto(path: 'missing_photo.jpg', width: 1, height: 1),
    );
  });
}
