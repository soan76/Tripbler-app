import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/user/user_account_section.dart';
import '../../widgets/user/user_app_section.dart';
import '../../widgets/user/user_info_section.dart';
import '../../widgets/user/user_account_actions.dart';
import '../../widgets/user/account_deletion_dialog.dart';
import '../auth/find_password_screen.dart';
import '../settings_screen.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() =>
      _UserPageState();
}

class _UserPageState
    extends State<UserPage> {
  bool _hasLoadedSocialAccounts = false;
  bool _isDeletingAccount = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_hasLoadedSocialAccounts) {
      return;
    }

    _hasLoadedSocialAccounts = true;

    // 화면 진입 후 소셜 계정 연동 상태를 한 번 조회한다.
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      context
          .read<AuthProvider>()
          .loadLinkedSocialAccounts();
    });
  }

  /// 비밀번호 변경 화면으로 이동한다.
  void _openFindPasswordScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const FindPasswordScreen(),
      ),
    );
  }

  /// 설정 화면으로 이동한다.
  void _openSettingsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const SettingsScreen(),
      ),
    );
  }

  /// Google 계정 연동 또는 연동 해제를 처리한다.
  Future<void> _handleSocialAccountChange(
    AuthProvider authProvider,
  ) async {
    final isLinked =
        authProvider.googleLinked == true;

    final success = isLinked
        ? await authProvider
            .unlinkGoogleAccount()
        : await authProvider
            .linkGoogleAccount();

    if (!mounted) {
      return;
    }

    if (success) {
      _showMessage(
        isLinked
            ? 'Google 계정 연동이 해제되었습니다.'
            : 'Google 계정이 연동되었습니다.',
      );

      return;
    }

    final message =
        authProvider.errorMessage ??
        (
          isLinked
              ? 'Google 계정 연동 해제에 실패했습니다.'
              : 'Google 계정 연동에 실패했습니다.'
        );

    _showMessage(message);
  }

  /// 로그아웃을 처리한다.
  Future<void> _handleLogout(
    AuthProvider authProvider,
  ) async {
    await authProvider.logout();

    if (!mounted) {
      return;
    }

    Navigator.of(context).popUntil(
      (route) => route.isFirst,
    );

    _showMessage(
      '로그아웃되었습니다.',
    );
  }

  /// 계정 탈퇴를 처리한다.
  Future<void> _handleDeleteAccount(AuthProvider authProvider) async {
    if (_isDeletingAccount) {
      return;
    }

    final confirmed = await AccountDeletionDialog.show(context);

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isDeletingAccount = true;
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AccountDeletionLoadingDialog(),
    );

    bool success = false;

    try {
      // API 요청과 최소 로딩 시간을 동시에 시작한다.
      final deleteFuture = authProvider.deleteAccount();

      final minimumLoadingFuture = Future<void>.delayed(
        const Duration(seconds: 2),
      );

      success = await deleteFuture;

      // API가 빨리 끝나도 최소 2초는 로딩을 표시한다.
      await minimumLoadingFuture;
    } catch (error) {
      debugPrint('계정 탈퇴 처리 중 예상하지 못한 오류: $error');

      success = false;
    } finally {
      // 성공/실패/예외와 관계없이
      // 로딩 다이얼로그는 반드시 닫는다.
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        setState(() {
          _isDeletingAccount = false;
        });
      }
    }

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(authProvider.errorMessage ?? '계정 탈퇴에 실패했습니다.');

      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);

    _showMessage('탈퇴가 완료되었습니다.');
  }

  /// 공통 SnackBar 출력
  void _showMessage(
    String message,
  ) {
    final messenger =
        ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final authProvider =
        context.watch<AuthProvider>();

    final colorScheme =
        Theme.of(context).colorScheme;

    final nickname =
        authProvider.nickname;

    final loginId =
        authProvider.loginId;

    final displayName =
        nickname?.trim().isNotEmpty == true
        ? nickname!
        : (loginId ?? '사용자');

    final displayLoginId =
        loginId ?? '';

    return Scaffold(
      backgroundColor:
          colorScheme.surface,
      appBar: AppBar(
        backgroundColor:
            colorScheme.surface,
        surfaceTintColor:
            Colors.transparent,
        title: Text(
          '사용자',
          style: TextStyle(
            color:
                colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
          child: Column(
            children: [
              UserInfoSection(
                displayName:
                    displayName,
                loginId:
                    displayLoginId,
                onEdit: () {
                  // 추후 프로필 편집 기능 연결
                },
              ),

              const SizedBox(
                height: 32,
              ),

              _buildDivider(
                context,
              ),

              const SizedBox(
                height: 24,
              ),

              UserAccountSection(
                googleLinked:
                    authProvider
                        .googleLinked,
                isLoading:
                    authProvider
                        .isLoading,

                onChangePassword:
                    _openFindPasswordScreen,

                onChangeSocialAccount:
                    () {
                  _handleSocialAccountChange(
                    authProvider,
                  );
                },
              ),

              const SizedBox(
                height: 24,
              ),

              _buildDivider(
                context,
              ),

              const SizedBox(
                height: 24,
              ),

              UserAppSection(
                onOpenSettings:
                    _openSettingsScreen,
              ),

              const SizedBox(
                height: 24,
              ),

              _buildDivider(
                context,
              ),

              const SizedBox(
                height: 24,
              ),

              UserAccountActions(
                isLoading:
                    authProvider
                        .isLoading ||
                    _isDeletingAccount,
                onLogout: () {
                  _handleLogout(
                    authProvider,
                  );
                },
                onDeleteAccount: () {
                  _handleDeleteAccount(
                    authProvider,
                  );
                },
              ),

              const SizedBox(
                height: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(
    BuildContext context,
  ) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant,
    );
  }
}