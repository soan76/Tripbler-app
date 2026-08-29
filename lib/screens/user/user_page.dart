import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../settings_screen.dart';
import '../../widgets/user/user_account_section.dart';
import '../../widgets/user/user_app_section.dart';
import '../../widgets/user/user_info_section.dart';

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
              UserProfileSection(
                displayName: displayName,
                loginId: displayLoginId,
                onEdit: () {
                  // 추후 프로필 편집 기능 연결
                },
              ),

              const SizedBox(height: 32),

              _buildDivider(context),

              const SizedBox(height: 24),

              UserAccountSection(
                loginId: displayLoginId,
                googleLinked: false,
                onChangeLoginId: () {
                  // 추후 아이디 변경 기능 연결
                },
                onChangePassword: () {
                  // 추후 비밀번호 변경 기능 연결
                },
                onChangeSocialAccount: () {
                  // 추후 Google 연동 기능 연결
                },
              ),

              const SizedBox(height: 24),

              _buildDivider(context),

              const SizedBox(height: 24),

              UserAppSection(
                onOpenSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),

              const SizedBox(height: 24),

              _buildDivider(context),

              const SizedBox(height: 24),

              UserAccountActions(
                isLoading: authProvider.isLoading,
                onLogout: () async {
                  await authProvider.logout();

                  if (!context.mounted) {
                    return;
                  }

                  Navigator.of(context).popUntil((route) => route.isFirst);

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('로그아웃되었습니다.')));
                },
                onDeleteAccount: () {
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

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}