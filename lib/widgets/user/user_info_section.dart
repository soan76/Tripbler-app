import 'package:flutter/material.dart';

class UserInfoSection extends StatelessWidget {
  const UserInfoSection({
    super.key,
    required this.displayName,
    required this.loginId,
    required this.onEdit,
    this.isLoading = false,
    this.profileImage,
  });

  final String displayName;
  final String loginId;
  final VoidCallback onEdit;
  final bool isLoading;
  final ImageProvider<Object>? profileImage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit = !isLoading;

    return Center(
      child: Column(
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
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: canEdit ? onEdit : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: canEdit
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: canEdit
                        ? colorScheme.onSurfaceVariant
                        : Theme.of(context).disabledColor,
                  ),
                ],
              ),
            ),
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