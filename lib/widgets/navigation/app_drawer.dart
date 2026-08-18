import 'package:flutter/material.dart';

import '../../screens/settings_screen.dart';
/// 앱의 Drawer 위젯
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.settings_outlined,
                color: colorScheme.onSurface,
              ),
              title: Text('설정', style: TextStyle(color: colorScheme.onSurface)),
              onTap: () {
                // Drawer 닫기
                Navigator.pop(context);

                // 설정 화면 이동
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
}
