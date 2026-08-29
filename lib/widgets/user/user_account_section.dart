import 'package:flutter/material.dart';

class UserAccountSection extends StatelessWidget {
  const UserAccountSection({
    super.key,
    required this.loginId,
    required this.googleLinked,
    required this.onChangeLoginId,
    required this.onChangePassword,
    required this.onChangeSocialAccount,
  });

  final String loginId;
  final bool googleLinked;
  final VoidCallback onChangeLoginId;
  final VoidCallback onChangePassword;
  final VoidCallback onChangeSocialAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSectionTitle(context, '계정'),
        _buildActionRow(
          context,
          title: '아이디',
          value: loginId,
          actionText: '변경',
          onTap: onChangeLoginId,
        ),
        _buildArrowRow(
          context,
          title: '비밀번호',
          value: '비밀번호 변경',
          onTap: onChangePassword,
        ),
        _buildActionRow(
          context,
          title: '연동된 계정',
          value: googleLinked ? 'Google · 연동됨' : 'Google · 연동 안 됨',
          actionText: '변경',
          onTap: onChangeSocialAccount,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context, {
    required String title,
    required String value,
    required String actionText,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: TextStyle(color: colorScheme.onSurface)),
      subtitle: Text(
        value,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: OutlinedButton(onPressed: onTap, child: Text(actionText)),
    );
  }

  Widget _buildArrowRow(
    BuildContext context, {
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: TextStyle(color: colorScheme.onSurface)),
      subtitle: Text(
        value,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}