import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/settings_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../providers/auth_provider.dart';
/// 앱의 Drawer 위젯
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authProvider = context.watch<AuthProvider>();

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            if (!authProvider.isAuthenticated) _buildLoginEntry(context),

            if (authProvider.isAuthenticated)
              _buildUserEntry(context, authProvider),

            ListTile(
              leading: Icon(
                Icons.settings_outlined,
                color: colorScheme.onSurface,
              ),
              title: Text('설정', style: TextStyle(color: colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);

                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 미로그인 사용자용 로그인 진입 영역
  Widget _buildLoginEntry(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            // Drawer 닫기
            Navigator.pop(context);

            // 로그인 화면으로 이동
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '로그인하겠습니까? >',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.9,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserEntry(BuildContext context, AuthProvider authProvider) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 40,
            color: colorScheme.onSurface,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              authProvider.nickname ?? '사용자',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, color: colorScheme.onSurface),
            ),
          ),

          const SizedBox(width: 8),

          TextButton(
            onPressed: authProvider.isLoading
                ? null
                : () async {
                    Navigator.pop(context);

                    await authProvider.logout();

                    if (!context.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('로그아웃되었습니다.')));
                  },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '로그아웃',
              style: TextStyle(fontSize: 14, color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
