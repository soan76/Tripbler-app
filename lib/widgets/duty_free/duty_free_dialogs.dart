import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/duty_free/duty_free_item.dart';
import '../../models/duty_free/duty_free_rules.dart';
import '../../providers/duty_free/duty_free_provider.dart';
import '../../utils/duty_free/duty_free_format.dart';
import '../schedule/schedule_impact_dialog.dart';
import '../schedule/schedule_sheet_parts.dart';
import 'duty_free_list_parts.dart';

/// 물건 삭제 확인: 어느 금액이 어떤 계산에서 빠지는지와 되돌릴 수 없음을 알린다.
Future<bool> confirmDutyFreeDelete(
  BuildContext context,
  DutyFreeItem item,
  DutyFreeRules? rules,
) {
  final usd = rules?.toUsd(item.amount, item.currency);
  final money =
      DutyFreeFormat.money(item.amount, item.currency) +
      (usd == null ? '' : ' (≈ ${DutyFreeFormat.usd(usd)})');
  final target = item.category == DutyFreeCategory.general
      ? '일반 물품 한도'
      : '${item.category.label} 기준';
  return confirmScheduleImpact(
    context,
    title: '"${item.name}"을(를) 삭제할까요?',
    lines: [
      ScheduleImpactLine('$money이(가) $target 계산에서 빠져요.'),
      const ScheduleImpactLine('되돌릴 수 없어요.', warning: true),
    ],
    confirmLabel: '삭제',
  );
}

/// 새 여행 시작 확인.
Future<bool> confirmNewDutyFreeTrip(BuildContext context, int count) {
  return confirmScheduleImpact(
    context,
    title: '새 여행을 시작할까요?',
    lines: [
      ScheduleImpactLine('산 물건 $count개가 모두 지워지고 한도 계산이 처음부터 시작돼요.'),
      const ScheduleImpactLine('되돌릴 수 없어요.', warning: true),
    ],
    confirmLabel: '모두 지우기',
  );
}

/// 면세 기준 정보 카드: 입국 국가(지금은 한국만)와 나이(만 19세 이상 여부)만 고른다.
class DutyFreeBasisSheet extends ConsumerWidget {
  const DutyFreeBasisSheet({super.key});

  static Future<void> open(BuildContext context) =>
      ScheduleSheetFrame.show<void>(context, (_) => const DutyFreeBasisSheet());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final adult = ref.watch(dutyFreeProvider.select((s) => s.adult));
    final country = ref.watch(dutyFreeRulesProvider).value?.country ?? '한국';
    return ScheduleSheetFrame(
      title: '면세 기준 정보',
      rows: [
        ScheduleSheetRow(
          icon: Icons.flight_land,
          label: '입국 국가',
          child: Text('$country (지금은 한국 입국 기준만)'),
        ),
        ScheduleSheetRow(
          icon: Icons.person_outline,
          label: '나이',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                key: const ValueKey('duty-free-adult'),
                showSelectedIcon: false,
                style: dutyFreeSegmentStyle(context),
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('만 19세 이상', textAlign: TextAlign.center),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('만 19세 미만', textAlign: TextAlign.center),
                  ),
                ],
                selected: {adult},
                onSelectionChanged: (s) async {
                  try {
                    await ref.read(dutyFreeProvider.notifier).setAdult(s.first);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('저장하지 못했어요')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 4),
              Text(
                '주류·담배 기준에만 써요. 생년월일은 받지 않아요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
      footer: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
