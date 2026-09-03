import 'package:flutter/material.dart';

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
            onPressed: isLoading ? null : onDeleteAccount,
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