import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/settings_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/user/user_page.dart';
import '../../providers/auth/auth_provider.dart';

/// 햄버거 메뉴로 여는 앱 서랍.
///
/// 위에는 계정(프로필 사진·이름·아이디), 구분선 아래 메뉴, 맨 아래 로그아웃을 둔다.
/// 로그인하지 않았으면 계정 자리에 로그인 진입을 두고 로그아웃은 보이지 않는다.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  static const double _avatarSize = 56;
  static const EdgeInsets _sidePadding = EdgeInsets.symmetric(horizontal: 24);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authProvider);
    final isAuthenticated = auth.isAuthenticated;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        // 글자를 크게 키우거나 가로 화면처럼 높이가 낮을 때는 스크롤되고,
        // 공간이 남으면 로그아웃을 맨 아래에 붙인다.
        child: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                if (isAuthenticated)
                  _buildUserEntry(context, auth)
                else
                  _buildLoginEntry(context),

                Divider(height: 1, color: colorScheme.outlineVariant),
                const SizedBox(height: 8),

                _buildMenuItem(
                  context,
                  icon: Icons.settings_outlined,
                  label: '설정',
                  onTap: () {
                    Navigator.pop(context);

                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: isAuthenticated
                    ? _buildLogout(
                        context,
                        auth,
                        ref.read(authProvider.notifier),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 계정 영역의 공통 배치: 위에 사진, 아래 굵은 이름과 작은 보조 글자.
  Widget _buildAccountHeader(
    BuildContext context, {
    required Widget avatar,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    String? semanticsHint,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 이름과 아이디를 버튼 하나로 묶어 화면 낭독기가 한 번에 읽게 한다.
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: semanticsHint,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: _sidePadding.copyWith(top: 24, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 미로그인 사용자용 로그인 진입 영역
  Widget _buildLoginEntry(BuildContext context) {
    return _buildAccountHeader(
      context,
      avatar: _defaultAvatar(context),
      title: '로그인',
      subtitle: '눌러서 계정에 로그인',
      semanticsHint: '로그인 화면 열기',
      onTap: () {
        // Drawer 닫기
        Navigator.pop(context);

        // 로그인 화면으로 이동
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      },
    );
  }

  Widget _buildUserEntry(BuildContext context, AuthState auth) {
    final nickname = auth.nickname?.trim();
    final loginId = auth.loginId?.trim();
    final hasNickname = nickname != null && nickname.isNotEmpty;
    final hasLoginId = loginId != null && loginId.isNotEmpty;

    return _buildAccountHeader(
      context,
      avatar: _buildUserAvatar(context, auth),
      // 닉네임이 있으면 이름으로, 아이디는 그 아래 보조 글자로 쓴다.
      title: hasNickname ? nickname : (hasLoginId ? loginId : '사용자'),
      subtitle: hasNickname && hasLoginId ? loginId : null,
      semanticsHint: '내 정보 열기',
      onTap: () {
        Navigator.pop(context);

        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UserPage()));
      },
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: _sidePadding,
      minTileHeight: 56,
      horizontalTitleGap: 16,
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      onTap: onTap,
    );
  }

  /// 서랍 맨 아래의 로그아웃. 실수로 누르지 않게 메뉴와 떨어뜨리고 위험 색으로 구분한다.
  ///
  /// 서랍은 닫히면 트리에서 빠지므로 로그아웃은 미리 받아 둔 [notifier]로 부른다.
  Widget _buildLogout(
    BuildContext context,
    AuthState auth,
    AuthNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: TextButton(
        onPressed: auth.isLoading
            ? null
            : () async {
                // 서랍은 닫힘 애니메이션이 끝나면 트리에서 빠지므로, 로그아웃이 끝난 뒤에도
                // 안내를 띄울 수 있게 닫기 전에 화면의 ScaffoldMessenger를 잡아 둔다.
                final messenger = ScaffoldMessenger.of(context);

                Navigator.pop(context);

                await notifier.logout();

                if (!messenger.mounted) {
                  return;
                }

                messenger.showSnackBar(
                  const SnackBar(content: Text('로그아웃되었습니다.')),
                );
              },
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.error,
          textStyle: theme.textTheme.bodyLarge,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: const Text('로그아웃'),
      ),
    );
  }

  Widget _defaultAvatar(BuildContext context) {
    return Icon(
      Icons.account_circle_outlined,
      size: _avatarSize,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  Widget _buildUserAvatar(BuildContext context, AuthState auth) {
    final profileImageUrl = auth.profileImageUrl?.trim();

    if (profileImageUrl == null || profileImageUrl.isEmpty) {
      return _defaultAvatar(context);
    }

    return ClipOval(
      child: SizedBox(
        width: _avatarSize,
        height: _avatarSize,
        child: Image.network(
          profileImageUrl,
          fit: BoxFit.cover,
          // 첫 프레임이 나오기 전(연결·수신·디코딩 중)에는 빈 원 대신 기본 아이콘을 둔다.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }

            return _defaultAvatar(context);
          },
          errorBuilder: (context, error, stackTrace) => _defaultAvatar(context),
        ),
      ),
    );
  }
}
