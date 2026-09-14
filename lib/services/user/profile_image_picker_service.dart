import 'package:image_picker/image_picker.dart';

/// 프로필 이미지 선택을 담당한다.
class ProfileImagePickerService {
  ProfileImagePickerService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// 갤러리에서 이미지를 선택하고 파일 경로를 반환한다.
  Future<String?> pickFromGallery() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);

    return image?.path;
  }
}