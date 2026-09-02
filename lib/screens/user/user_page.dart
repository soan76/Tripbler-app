import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/user/user_account_section.dart';
import '../../widgets/user/user_app_section.dart';
import '../../widgets/user/user_info_section.dart';
import '../auth/find_password_screen.dart';
import '../settings_screen.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  bool _hasLoadedSocialAccounts = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_hasLoadedSocialAccounts) {
      return;
    }

    _hasLoadedSocialAccounts = true;

    // 화면 진입 후 소셜 계정 연동 상태를 한 번 조회한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      context.read<AuthProvider>().loadLinkedSocialAccounts();
    });
  }

  /// 비밀번호 변경 화면으로 이동한다.
  ///
  /// 현재 비밀번호 변경도 비밀번호 찾기와 동일하게
  /// 연동 이메일 인증을 거친 뒤 재설정하도록 한다.
  void _openFindPasswordScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FindPasswordScreen()));
  }

  /// 설정 화면으로 이동한다.
  void _openSettingsScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  /// Google 계정 연동 또는 연동 해제를 처리한다.
  Future<void> _handleSocialAccountChange(AuthProvider authProvider) async {
    final isLinked = authProvider.googleLinked == true;

    final success = isLinked
        ? await authProvider.unlinkGoogleAccount()
        : await authProvider.linkGoogleAccount();

    if (!mounted) {
      return;
    }

    if (success) {
      _showMessage(isLinked ? 'Google 계정 연동이 해제되었습니다.' : 'Google 계정이 연동되었습니다.');

      return;
    }

    final message =
        authProvider.errorMessage ??
        (isLinked ? 'Google 계정 연동 해제에 실패했습니다.' : 'Google 계정 연동에 실패했습니다.');

    _showMessage(message);
  }

  /// 로그아웃을 처리한다.
  Future<void> _handleLogout(AuthProvider authProvider) async {
    await authProvider.logout();

    if (!mounted) {
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);

    _showMessage('로그아웃되었습니다.');
  }

  /// 공통 SnackBar 출력
  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

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
              UserInfoSection(
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
                googleLinked: authProvider.googleLinked,
                isLoading: authProvider.isLoading,

                // 비밀번호 변경
                onChangePassword: _openFindPasswordScreen,

                // Google 계정 연동 / 해제
                onChangeSocialAccount: () {
                  _handleSocialAccountChange(authProvider);
                },
              ),

              const SizedBox(height: 24),

              _buildDivider(context),

              const SizedBox(height: 24),

              UserAppSection(onOpenSettings: _openSettingsScreen),

              const SizedBox(height: 24),

              _buildDivider(context),

              const SizedBox(height: 24),

              _buildAccountActions(context, authProvider),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountActions(BuildContext context, AuthProvider authProvider) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: authProvider.isLoading
                ? null
                : () {
                    _handleLogout(authProvider);
                  },
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
            onPressed: () {
              // 추후 계정 탈퇴 기능 연결
            },
            child: Text(
              '계정 탈퇴',
              style: TextStyle(fontSize: 16, color: colorScheme.error),
            ),
          ),
        ),
      ],
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