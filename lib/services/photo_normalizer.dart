import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 방향을 반영해 줄이고 JPEG로 저장한 기준 사진. OCR·업로드·화면 표시가 모두 이 사진의 픽셀 좌표를 쓴다.
@immutable
class NormalizedPhoto {
  const NormalizedPhoto({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;
}

/// 사진을 읽지 못한 경우(HEIC 등 지원하지 않는 형식, 손상된 파일, 사진이 아닌 파일).
class UnsupportedPhotoException implements Exception {
  const UnsupportedPhotoException();

  @override
  String toString() => 'UnsupportedPhotoException';
}

/// 선택한 사진을 기준 사진 하나로 만든다. EXIF 방향을 픽셀에 반영하고(결과에는 방향 정보가 남지 않는다),
/// 긴 변을 [maxLongSide] 이하로 줄이고, JPEG로 저장한다. 무거운 처리는 별도 Isolate에서 한다.
class PhotoNormalizer {
  // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
  static const int maxLongSide = 2048;
  // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
  static const int jpegQuality = 85;

  Future<NormalizedPhoto> normalize({
    required String sourcePath,
    required String outputDirectory,
  }) async {
    final outputPath =
        '$outputDirectory/photo_${DateTime.now().microsecondsSinceEpoch}.jpg';

    final size = await Isolate.run(
      () => _normalizeFile(sourcePath, outputPath),
    );
    if (size == null) {
      throw const UnsupportedPhotoException();
    }

    return NormalizedPhoto(path: outputPath, width: size.$1, height: size.$2);
  }

  /// 기준 사진 파일을 지운다. 파일이 없어도 오류 없이 넘어간다.
  Future<void> delete(NormalizedPhoto photo) async {
    try {
      final file = File(photo.path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // 이미 지워졌거나 지울 수 없는 파일은 무시한다.
    }
  }
}

/// Isolate 안에서 실행한다. 성공하면 (가로, 세로), 읽지 못하면 null.
(int, int)? _normalizeFile(String sourcePath, String outputPath) {
  try {
    final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (decoded == null) {
      return null;
    }

    var image = img.bakeOrientation(decoded);
    final longSide = image.width > image.height ? image.width : image.height;
    if (longSide > PhotoNormalizer.maxLongSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: PhotoNormalizer.maxLongSide)
          : img.copyResize(image, height: PhotoNormalizer.maxLongSide);
    }

    File(outputPath).writeAsBytesSync(
      img.encodeJpg(image, quality: PhotoNormalizer.jpegQuality),
    );
    return (image.width, image.height);
  } on Object {
    // 파일을 읽지 못하거나 디코딩 중 오류가 나도 앱이 죽지 않게 지원하지 않는 사진으로 다룬다.
    return null;
  }
}
