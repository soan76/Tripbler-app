import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/duty_free/duty_free_item.dart';
import '../models/duty_free/duty_free_rules.dart';
import '../providers/duty_free/duty_free_provider.dart';
import '../utils/duty_free/duty_free_format.dart';
import '../widgets/duty_free/duty_free_declare_notice.dart';
import '../widgets/duty_free/duty_free_dialogs.dart';
import '../widgets/duty_free/duty_free_item_sheet.dart';
import '../widgets/duty_free/duty_free_list_parts.dart';
import '../widgets/duty_free/duty_free_summary_sections.dart';
import '../widgets/navigation/bottom_menu_capture_marks.dart';
import 'receipt_review_screen.dart';

/// 면세 탭(docs/mockups/duty-free.md): 기준 줄, 일반 한도·별도 기준 요약, 신고 안내, 산 물건 목록,
/// 직접 입력·영수증 찍기.
///
/// 면세 기준·환율은 [dutyFreeRulesProvider]의 값(지금은 앱 안 예시)이고, 저장·계산은
/// [dutyFreeProvider]·[dutyFreeSummaryProvider]가 맡는다. 이 화면은 표시와 입력만 한다.
class DutyFreeScreen extends ConsumerStatefulWidget {
  const DutyFreeScreen({super.key});

  static const String emptyMessage = '산 물건을 추가해 보세요';
  static const String loadFailedMessage = '면세 기록을 불러오지 못했어요';
  static const String rulesFailedMessage =
      '면세 기준과 환율을 불러오지 못했어요. 저장된 기준도 없어 한도를 계산할 수 없어요.';

  /// 아래 가운데 하단 메뉴가 버튼을 가리지 않게 두는 여백.
  ///
  /// 점(지름 48)을 누르면 4초 동안 현재 화면 버튼(지름 74, 아래에서 12)으로 커진다. 그때도 하단 버튼
  /// 줄과 겹치지 않도록 커진 원의 위 끝 + 8을 비운다(번역 화면과 같은 값).
  static const double bottomMenuClearance = BottomMenuMetrics.contentClearance;

  @override
  ConsumerState<DutyFreeScreen> createState() => _DutyFreeScreenState();
}

class _DutyFreeScreenState extends ConsumerState<DutyFreeScreen> {
  /// 카드·촬영이 열려 있는지(두 번 눌러 겹쳐 열리지 않게).
  bool _busy = false;

  void _toast(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy || !ref.read(dutyFreeProvider).isReady) return;
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }

  DutyFreeRules? get _rules => ref.read(dutyFreeRulesProvider).value;

  Future<void> _add() => _guard(() async {
    _toast(await DutyFreeItemSheet.open(context, rules: _rules));
  });

  Future<void> _edit(DutyFreeItem item) => _guard(() async {
    _toast(await DutyFreeItemSheet.open(context, initial: item, rules: _rules));
  });

  Future<void> _newTrip() => _guard(() async {
    final count = ref.read(dutyFreeProvider).items.length;
    if (!await confirmNewDutyFreeTrip(context, count)) return;
    try {
      await ref.read(dutyFreeProvider.notifier).startNewTrip();
      _toast('목록을 비웠어요');
    } catch (_) {
      _toast('목록을 비우지 못했어요');
    }
  });

  /// 영수증을 찍어 검토 화면을 연다. 검토 화면에서 `다시 찍기`를 누르면 촬영부터 다시 하고,
  /// 촬영을 취소하면 이 화면으로 돌아온다.
  Future<void> _scanReceipt() => _guard(() async {
    while (mounted) {
      final String? path;
      try {
        path = await ref.read(receiptPhotoPickerProvider)();
      } catch (_) {
        _toast('카메라를 열지 못했어요');
        return;
      }
      if (path == null || !mounted) return;
      final result = await ReceiptReviewScreen.scanAndOpen(context, path);
      if (result != ReceiptReviewScreen.retakeResult) {
        _toast(result);
        return;
      }
    }
  });

  Future<void> _openCustoms() async {
    var opened = false;
    try {
      opened = await ref.read(customsGuideLauncherProvider)();
    } catch (_) {}
    if (!opened) _toast('관세청 안내를 열지 못했어요');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dutyFreeProvider);
    switch (state.status) {
      case DutyFreeLoadStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case DutyFreeLoadStatus.failed:
        // 일정 탭의 불러오기 실패 화면과 같은 모양(가운데 문구 + 다시 시도).
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              24,
              24,
              24,
              DutyFreeScreen.bottomMenuClearance,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DutyFreeScreen.loadFailedMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: ref.read(dutyFreeProvider.notifier).retry,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        );
      case DutyFreeLoadStatus.ready:
        return _ready(context, state);
    }
  }

  Widget _ready(BuildContext context, DutyFreeState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rulesAsync = ref.watch(dutyFreeRulesProvider);
    final rules = rulesAsync.value;
    final summary = ref.watch(dutyFreeSummaryProvider);
    final now = ref.read(dutyFreeClockProvider)();
    final items = [...state.items]
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));

    final children = <Widget>[
      DutyFreeBasisRow(
        country: rules?.country ?? '한국',
        adult: state.adult,
        onChange: () => _guard(() => DutyFreeBasisSheet.open(context)),
      ),
      if (rulesAsync.isLoading && rules == null)
        const LinearProgressIndicator()
      else if (rules == null || summary == null)
        DutyFreeNotice(
          error: true,
          text: DutyFreeScreen.rulesFailedMessage,
          action: '다시 시도',
          onAction: () => ref.invalidate(dutyFreeRulesProvider),
        )
      else ...[
        if (rules.stale)
          DutyFreeNotice(
            text:
                '저장된 환율로 계산했어요 · ${DutyFreeFormat.dateTime(rules.checkedAt)} 기준. 인터넷에 연결되면 다시 계산해요.',
          ),
        GeneralLimitSection(
          summary: summary.general,
          rules: rules,
          localCurrency: _localCurrency(state.items),
        ),
        SeparateLimitsSection(
          summary: summary,
          rules: rules,
          adult: state.adult,
        ),
        DutyFreeRulesInfoRow(
          rules: rules,
          now: now,
          onOpenCustoms: _openCustoms,
        ),
        if (summary.anyOver)
          DeclareNotice(
            summary: summary,
            rules: rules,
            onOpenCustoms: _openCustoms,
          ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '산 물건 ${items.length}개',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (items.isNotEmpty)
              TextButton(
                key: const ValueKey('duty-free-new-trip'),
                onPressed: _newTrip,
                child: const Text('새 여행 시작'),
              ),
          ],
        ),
      ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
          child: Column(
            children: [
              Text(
                DutyFreeScreen.emptyMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '출국 면세점·기내에서 산 것도 넣어 주세요.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      for (final item in items)
        DutyFreeItemRow(item: item, rules: rules, onTap: () => _edit(item)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('duty-free-list'),
            padding: const EdgeInsets.only(bottom: 16),
            children: children,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              DutyFreeScreen.bottomMenuClearance,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('duty-free-add'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _add,
                    child: const Text('직접 입력'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('duty-free-scan'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _scanReceipt,
                    child: const Text('영수증 찍기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 남은 한도를 바꿔 보일 통화: 일반 물품에서 가장 많이 쓴 원화가 아닌 통화, 없으면 JPY.
  static String _localCurrency(List<DutyFreeItem> items) {
    final counts = <String, int>{};
    for (final i in items) {
      if (i.currency == 'KRW') continue;
      counts[i.currency] = (counts[i.currency] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'JPY';
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
