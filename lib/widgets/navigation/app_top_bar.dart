import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.actions = const [],
  });

  /// 제목 양옆 여백 계산용: 왼쪽 메뉴 버튼(여백 8 + 48), 오른쪽 동작 버튼 하나(48)와 끝 여백.
  static const double _menuWidth = 56;
  static const double _actionWidth = 48;
  static const double _actionsInset = 4;

  final String title;

  /// 오른쪽 끝에 두는 동작 버튼(예: 일정 탭의 보관함·백업).
  final List<Widget> actions;

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
            // 일반 화면 제목. 가운데를 지키면서 양옆 버튼(왼쪽 메뉴 56, 오른쪽 동작)과 겹치지 않게
            // 더 넓은 쪽만큼 양옆을 비우고, 넘치면 말줄임한다(폭 320·큰 글자).
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: math.max(
                  _menuWidth,
                  _actionsInset + _actionWidth * actions.length,
                ),
              ),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),

            if (actions.isNotEmpty)
              Positioned(
                right: _actionsInset,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
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
