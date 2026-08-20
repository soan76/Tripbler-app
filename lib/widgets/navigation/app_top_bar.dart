import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.showBackButton = false,
  });

  final String title;

  // 설정 화면처럼 뒤로가기 버튼이 필요한 경우 사용
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      height: kToolbarHeight,
      color: colorScheme.surface,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showBackButton)
            // 설정 화면: 뒤로가기 + 왼쪽 제목
            Positioned(
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    iconSize: 26,
                    color: colorScheme.onSurface,
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),

                  const SizedBox(width: 4),

                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // 일반 화면 제목
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),

            // 일반 화면 햄버거 메뉴
            Positioned(
              left: 8,
              child: Builder(
                builder: (context) {
                  return IconButton(
                    icon: const Icon(Icons.menu),
                    iconSize: 28,
                    color: colorScheme.onSurface,
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
