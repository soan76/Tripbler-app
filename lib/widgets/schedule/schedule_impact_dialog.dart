import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 확인창의 안내 한 줄. [warning]이면 오류색으로 보인다(잃는 내용).
class ScheduleImpactLine {
  const ScheduleImpactLine(this.text, {this.warning = false});

  final String text;
  final bool warning;
}

/// 지울 대상과 그 영향을 줄마다 알리는 확인창(docs/mockups/schedule.md 4절 "삭제 확인창").
///
/// 확인하면 true, 취소·바깥 누르기·뒤로 가기는 false.
Future<bool> confirmScheduleImpact(
  BuildContext context, {
  required String title,
  required List<ScheduleImpactLine> lines,
  required String confirmLabel,
  String cancelLabel = '취소',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final buttonStyle = TextButton.styleFrom(minimumSize: const Size(64, 48));
      final body = theme.textTheme.bodyMedium;
      // 줄 앞 표시를 글자 한 줄 높이에 맞춘다(큰 글자에서도 첫 줄과 나란하게).
      final markSize = MediaQuery.textScalerOf(
        context,
      ).scale(body?.fontSize ?? 14);
      return AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppTheme.cornerRadius),
          ),
        ),
        // 긴 제목(백업 시각·일정 제목)과 큰 글자에서도 버튼까지 닿게 창 전체를 스크롤한다.
        scrollable: true,
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 잃는 내용은 색만이 아니라 경고 아이콘으로도 구분한다.
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: line.warning
                          ? Icon(
                              Icons.warning_amber_rounded,
                              size: markSize + 2,
                              color: colorScheme.error,
                            )
                          : SizedBox.square(
                              dimension: markSize + 2,
                              child: Center(
                                child: ExcludeSemantics(
                                  child: Text(
                                    '•',
                                    style: body?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line.text,
                        semanticsLabel: line.warning
                            ? '주의, ${line.text}'
                            : null,
                        style: body?.copyWith(
                          color: line.warning
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: buttonStyle,
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? buttonStyle.copyWith(
                    foregroundColor: WidgetStatePropertyAll(colorScheme.error),
                  )
                : buttonStyle,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
