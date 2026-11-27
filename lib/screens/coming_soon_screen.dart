import 'package:flutter/material.dart';

/// 아직 만들지 않은 화면(일정·면세)의 자리. 하단 메뉴 배치부터 확인하려고 둔다(bottom-nav.md 10-5절).
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  static const String message = '준비 중이에요';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 화면 이름은 상단 바가 이미 보여 주므로 되풀이하지 않고, 다른 화면으로 가는 방법을 알려 준다.
    // 메뉴를 고른 뒤에는 아래 가운데 점만 남아 찾기 어려우므로 그 점을 가리킨다.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$title 화면은 아직 만들고 있어요.\n아래 가운데 점을 눌러 다른 화면으로 갈 수 있어요.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
