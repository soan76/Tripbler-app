import 'package:flutter/material.dart';

class UserProfileSection extends StatelessWidget {
  const UserProfileSection({
    super.key,
    required this.displayName,
    required this.loginId,
    required this.onEdit,
  });

  final String displayName;
  final String loginId;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.person,
              size: 52,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (loginId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '@$loginId',
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

class UserAccountActions extends StatelessWidget {
  const UserAccountActions({
    super.key,
    required this.isLoading,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final bool isLoading;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: isLoading ? null : onLogout,
            child: Text(
              '로그아웃',
              style: TextStyle(fontSize: 16, color: colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onDeleteAccount,
            child: Text(
              '계정 탈퇴',
              style: TextStyle(fontSize: 16, color: colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}
