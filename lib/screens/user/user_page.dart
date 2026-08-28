import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../settings_screen.dart';

class UserPage extends StatelessWidget {
  const UserPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    final nickname = authProvider.nickname;
    final loginId = authProvider.loginId;

    final displayName = nickname?.trim().isNotEmpty == true
        ? nickname!
        : (loginId ?? '사용자');

    final displayLoginId = loginId ?? '';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('사용자', style: TextStyle(color: colorScheme.onSurface)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              _buildProfileSection(
                context,
                displayName: displayName,
                loginId: displayLoginId,
              ),

              const SizedBox(height: 32),

              Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant,
              ),

              const SizedBox(height: 24),

              _buildSectionTitle(context, '계정'),

              _buildActionRow(
                context,
                title: '아이디',
                value: displayLoginId,
                actionText: '변경',
                onTap: () {
                  // 추후 아이디 변경 기능 연결
                },
              ),

              _buildArrowRow(
                context,
                title: '비밀번호',
                value: '비밀번호 변경',
                onTap: () {
                  // 추후 비밀번호 변경 화면 연결
                },
              ),

              _buildActionRow(
                context,
                title: '연동된 계정',
                value: 'Google · 연동 안 됨',
                actionText: '변경',
                onTap: () {
                  // 추후 계정 연동 관리 기능 연결
                },
              ),

              const SizedBox(height: 32),

              _buildSectionTitle(context, '앱'),

              _buildArrowRow(
                context,
                title: '설정',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),

              const SizedBox(height: 32),

              _buildTextButton(
                context,
                text: '로그아웃',
                onTap: authProvider.isLoading
                    ? null
                    : () async {
                        await authProvider.logout();

                        if (!context.mounted) {
                          return;
                        }

                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('로그아웃되었습니다.')),
                        );
                      },
              ),

              _buildTextButton(
                context,
                text: '계정 탈퇴',
                isDestructive: true,
                onTap: () {
                  // 추후 계정 탈퇴 기능 연결
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection(
    BuildContext context, {
    required String displayName,
    required String loginId,
  }) {
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
            onTap: () {
              // 추후 프로필 및 닉네임 편집 기능 연결
            },
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

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: TextStyle(color: colorScheme.onSurface)),
          subtitle: Text(
            value,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          trailing: OutlinedButton(onPressed: onTap, child: Text(actionText)),
        ),

        Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
      ],
    );
  }

  Widget _buildArrowRow(
    BuildContext context, {
    required String title,
    String? value,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: TextStyle(color: colorScheme.onSurface)),
          subtitle: value == null
              ? null
              : Text(
                  value,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
          trailing: Icon(
            Icons.chevron_right,
            color: colorScheme.onSurfaceVariant,
          ),
          onTap: onTap,
        ),

        Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
      ],
    );
  }

  Widget _buildTextButton(
    BuildContext context, {
    required String text,
    required VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onTap,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                color: isDestructive ? colorScheme.error : colorScheme.primary,
              ),
            ),
          ),
        ),

        Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
      ],
    );
  }
}