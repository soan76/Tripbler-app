import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// 프로필 이미지 선택을 담당한다.
class ProfileImagePickerService {
  ProfileImagePickerService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  static const int maxFileSizeBytes = 5 * 1024 * 1024;

  final ImagePicker _imagePicker;

  /// 갤러리에서 이미지를 선택하고 파일 경로를 반환한다.
  Future<String?> pickFromGallery() async {
    final image = await _pickImageFromGallery();

    if (image == null) {
      return null;
    }

    if (!_hasSupportedExtension(image.path)) {
      throw const ProfileImageUnsupportedFormatException();
    }

    final fileSize = await image.length();

    if (fileSize > maxFileSizeBytes) {
      throw const ProfileImageTooLargeException();
    }

    return image.path;
  }

  Future<XFile?> _pickImageFromGallery() async {
    try {
      return await _imagePicker.pickImage(source: ImageSource.gallery);
    } on PlatformException {
      throw const ProfileImagePickerException();
    }
  }

  bool _hasSupportedExtension(String filePath) {
    final normalizedPath = filePath.toLowerCase();

    return normalizedPath.endsWith('.jpg') ||
        normalizedPath.endsWith('.jpeg') ||
        normalizedPath.endsWith('.png') ||
        normalizedPath.endsWith('.webp') ||
        normalizedPath.endsWith('.gif');
  }
}

abstract class ProfileImageException implements Exception {
  const ProfileImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 프로필 이미지 선택 과정에서 플랫폼 오류가 발생했을 때 사용한다.
class ProfileImagePickerException extends ProfileImageException {
  const ProfileImagePickerException() : super('프로필 이미지를 선택하지 못했습니다.');
}

/// 허용된 프로필 이미지 크기를 초과했을 때 발생한다.
class ProfileImageTooLargeException extends ProfileImageException {
  const ProfileImageTooLargeException()
    : super('프로필 이미지는 5MB 이하의 파일만 사용할 수 있습니다.');
}

/// 지원하지 않는 프로필 이미지 형식일 때 발생한다.
class ProfileImageUnsupportedFormatException extends ProfileImageException {
  const ProfileImageUnsupportedFormatException()
    : super('지원하지 않는 프로필 이미지 형식입니다.');
}
