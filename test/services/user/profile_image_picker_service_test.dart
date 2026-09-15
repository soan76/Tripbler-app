import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tripbler/services/user/profile_image_picker_service.dart';

class FakeImagePicker extends ImagePicker {
  FakeImagePicker(this.image);

  final XFile? image;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return image;
  }
}

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'tripbler_profile_image_test_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<XFile> createTestFile(String fileName, {int size = 10}) async {
    final file = File('${tempDirectory.path}/$fileName');

    final randomAccessFile = await file.open(mode: FileMode.write);

    await randomAccessFile.truncate(size);
    await randomAccessFile.close();

    return XFile(file.path);
  }

  group('ProfileImagePickerService 파일 형식 검사', () {
    test('JPG 파일을 허용한다', () async {
      final image = await createTestFile('profile.jpg');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      final result = await service.pickFromGallery();

      expect(result, image.path);
    });

    test('PNG 파일을 허용한다', () async {
      final image = await createTestFile('profile.png');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      final result = await service.pickFromGallery();

      expect(result, image.path);
    });

    test('WebP 파일을 허용한다', () async {
      final image = await createTestFile('profile.webp');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      expect(await service.pickFromGallery(), image.path);
    });

    test('GIF 파일을 허용한다', () async {
      final image = await createTestFile('profile.gif');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      expect(await service.pickFromGallery(), image.path);
    });

    test('BMP 파일을 거부한다', () async {
      final image = await createTestFile('profile.bmp');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      await expectLater(
        service.pickFromGallery(),
        throwsA(isA<ProfileImageUnsupportedFormatException>()),
      );
    });

    test('HEIC 파일을 거부한다', () async {
      final image = await createTestFile('profile.heic');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      await expectLater(
        service.pickFromGallery(),
        throwsA(isA<ProfileImageUnsupportedFormatException>()),
      );
    });

    test('TIFF 파일을 거부한다', () async {
      final image = await createTestFile('profile.tiff');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      await expectLater(
        service.pickFromGallery(),
        throwsA(isA<ProfileImageUnsupportedFormatException>()),
      );
    });

    test('확장자가 없으면 MIME 타입이 허용되어도 거부한다', () async {
      final file = File('${tempDirectory.path}/profile');

      await file.writeAsBytes(List<int>.filled(10, 0));

      final image = XFile(file.path, mimeType: 'image/jpeg');

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      await expectLater(
        service.pickFromGallery(),
        throwsA(isA<ProfileImageUnsupportedFormatException>()),
      );
    });
  });

  group('ProfileImagePickerService 파일 크기 검사', () {
    test('5MB보다 1바이트 작은 이미지는 허용한다', () async {
      final image = await createTestFile(
        'profile.jpg',
        size: ProfileImagePickerService.maxFileSizeBytes - 1,
      );

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      final result = await service.pickFromGallery();

      expect(result, image.path);
    });

    test('정확히 5MB인 이미지는 허용한다', () async {
      final image = await createTestFile(
        'profile.jpg',
        size: ProfileImagePickerService.maxFileSizeBytes,
      );

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      final result = await service.pickFromGallery();

      expect(result, image.path);
    });

    test('5MB보다 1바이트 큰 이미지는 거부한다', () async {
      final image = await createTestFile(
        'profile.jpg',
        size: ProfileImagePickerService.maxFileSizeBytes + 1,
      );

      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(image),
      );

      await expectLater(
        service.pickFromGallery(),
        throwsA(isA<ProfileImageTooLargeException>()),
      );
    });
  });

  group('ProfileImagePickerService 이미지 선택', () {
    test('사용자가 이미지 선택을 취소하면 null을 반환한다', () async {
      final service = ProfileImagePickerService(
        imagePicker: FakeImagePicker(null),
      );

      final result = await service.pickFromGallery();

      expect(result, isNull);
    });
  });
}
