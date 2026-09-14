import 'package:flutter/material.dart';

enum ProfileImageAction { change, delete }

/// 프로필 이미지 변경/삭제 메뉴를 표시한다.
class ProfileImageActionSheet {
  const ProfileImageActionSheet._();

  static Future<ProfileImageAction?> show(
    BuildContext context, {
    required bool hasProfileImage,
  }) {
    return showModalBottomSheet<ProfileImageAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('사진 변경'),
                onTap: () {
                  Navigator.of(context).pop(ProfileImageAction.change);
                },
              ),

              if (hasProfileImage)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('사진 삭제'),
                  onTap: () {
                    Navigator.of(context).pop(ProfileImageAction.delete);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}