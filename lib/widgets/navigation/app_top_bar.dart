import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.title});

  final String title;

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
          // 화면 이름
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),

          // 햄버거 메뉴
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
      ),
    );
  }
}
