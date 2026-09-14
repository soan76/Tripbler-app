import 'package:flutter/material.dart';

import 'profile_image_action_sheet.dart';

class UserInfoSection extends StatelessWidget {
  const UserInfoSection({
    super.key,
    required this.displayName,
    required this.loginId,
    required this.onEditNickname,
    required this.onChangeProfileImage,
    required this.onDeleteProfileImage,
    this.isLoading = false,
    this.profileImage,
  });

  final String displayName;
  final String loginId;
  final VoidCallback onEditNickname;
  final VoidCallback onChangeProfileImage;
  final VoidCallback onDeleteProfileImage;
  final bool isLoading;
  final ImageProvider<Object>? profileImage;

  /// 프로필 이미지 변경/삭제 메뉴를 연다.
  Future<void> _openProfileImageActions(BuildContext context) async {
    final action = await ProfileImageActionSheet.show(
      context,
      hasProfileImage: profileImage != null,
    );

    if (action == null) {
      return;
    }

    switch (action) {
      case ProfileImageAction.change:
        onChangeProfileImage();
        break;

      case ProfileImageAction.delete:
        onDeleteProfileImage();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit = !isLoading;

    return Center(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: colorScheme.surfaceContainerHighest,
                backgroundImage: profileImage,
                child: profileImage == null
                    ? Icon(
                        Icons.person,
                        size: 52,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),

              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: colorScheme.primaryContainer,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: '프로필 이미지 변경',
                    onPressed: canEdit
                        ? () {
                            _openProfileImageActions(context);
                          }
                        : null,
                    icon: Icon(
                      Icons.camera_alt_outlined,
                      size: 18,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 30, height: 30),

              Flexible(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: canEdit
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              SizedBox(
                width: 30,
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  tooltip: '닉네임 변경',
                  onPressed: canEdit ? onEditNickname : null,
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: canEdit
                        ? colorScheme.onSurfaceVariant
                        : Theme.of(context).disabledColor,
                  ),
                ),
              ),
            ],
          ),
          if (loginId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '@$loginId',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}