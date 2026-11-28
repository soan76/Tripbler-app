import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/schedule/schedule_item.dart';
import '../../providers/schedule/schedule_draft_provider.dart';
import '../../providers/schedule/schedule_provider.dart';
import '../../screens/place_picker_screen.dart';
import 'schedule_editor_fields.dart';
import 'schedule_pickers.dart';
import 'schedule_sheet_parts.dart';
import 'schedule_time_wheel.dart';

/// 일정 입력 카드와 수정 화면(docs/mockups/schedule.md 2-3·2-4·3-1절).
///
/// 입력값은 [scheduleDraftProvider]에 있고 이 위젯은 표시와 입력만 맡는다.
/// - 새 일정: 머리글 "일정 추가", 하단 `취소 | 저장`.
/// - 수정: 머리글 왼쪽 뒤로 가기와 "일정 수정", 하단 `삭제 | 수정`.
///
/// 저장하면 저장한 [ScheduleItem]을 돌려주며 닫힌다. 취소·뒤로 가기·삭제는 null.
class ScheduleEditorSheet extends ConsumerStatefulWidget {
  const ScheduleEditorSheet({super.key});

  static const String titleRequiredMessage = '제목을 입력해 주세요';
  static const String saveFailedMessage = '저장하지 못했어요. 다시 시도해 주세요';
  static const String deleteFailedMessage = '삭제하지 못했어요. 다시 시도해 주세요';
  static const String archiveFailedMessage = '보관함으로 옮기지 못했어요. 다시 시도해 주세요';
  static const String alarmPassedMessage = ScheduleAlarmField.passedMessage;
  static const String alarmNotSentMessage = ScheduleAlarmField.notSentMessage;
  static const String discardQuestion = '작성 중인 내용을 버릴까요?';
  static const String discardEditQuestion = '수정한 내용을 버릴까요?';
  static const String deleteQuestion = '이 일정을 삭제할까요?';

  /// 새 작성을 시작하고 입력 카드를 연다.
  static Future<ScheduleItem?> open(BuildContext context, WidgetRef ref) {
    ref.read(scheduleDraftProvider.notifier).start();
    return _show(context);
  }

  /// 저장한 [item]의 값을 채워 수정 화면을 연다.
  static Future<ScheduleItem?> openEdit(
    BuildContext context,
    WidgetRef ref,
    ScheduleItem item,
  ) {
    ref.read(scheduleDraftProvider.notifier).startEdit(item);
    return _show(context);
  }

  static Future<ScheduleItem?> _show(BuildContext context) {
    return ScheduleSheetFrame.show<ScheduleItem>(
      context,
      (_) => const ScheduleEditorSheet(),
    );
  }

  @override
  ConsumerState<ScheduleEditorSheet> createState() =>
      _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends ConsumerState<ScheduleEditorSheet> {
  late final ScheduleDraftNotifier _draft = ref.read(
    scheduleDraftProvider.notifier,
  );
  late final TextEditingController _title;
  late final TextEditingController _place;
  late final TextEditingController _memo;
  final FocusNode _titleFocus = FocusNode();

  /// 시간 휠. 굴리는 중에는 멈춰야 값을 알리므로, 입력값을 읽거나 카드를 떠나기 전에
  /// [_flushTime]으로 지금 보이는 값을 먼저 반영한다.
  final GlobalKey<ScheduleTimeWheelState> _timeWheel = GlobalKey();

  /// 휠이 굴러가는 중이면 가운데 값으로 멈추고 draft에 바로 넣는다(동기). 저장 중에는
  /// 휠이 꺼져 있어 아무것도 하지 않는다.
  void _flushTime() => _timeWheel.currentState?.flush();

  /// 지금 진행 중인 일이 삭제인지. 저장과 삭제는 같은 isSaving을 쓰므로, 진행 표시를
  /// 누른 버튼 쪽에 두려고 화면에서만 따로 기억한다.
  bool _deleting = false;

  /// 처음 열 때 새 일정이었는지. 새 일정만 제목에 바로 초점을 둔다(수정은 키보드 없이 값을 본다).
  late final bool _isNew;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(scheduleDraftProvider);
    _isNew = !(draft?.isEditing ?? false);
    _title = TextEditingController(text: draft?.title ?? '');
    _place = TextEditingController(text: draft?.placeText ?? '');
    _memo = TextEditingController(text: draft?.memo ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _memo.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  DateTime _now() => ref.read(scheduleClockProvider)();

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    _flushTime();
    final saved = await _draft.save();
    if (!mounted) return;
    if (saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
    if (ref.read(scheduleDraftProvider)?.titleError ?? false) {
      _titleFocus.requestFocus();
    }
  }

  /// 취소·뒤로 가기·바깥 누르기. 버릴 내용이 있으면 한 번 묻는다
  /// (새 일정은 입력한 게 있으면, 수정은 저장한 값과 달라졌으면).
  Future<void> _close() async {
    _flushTime();
    final draft = ref.read(scheduleDraftProvider);
    if (draft == null || draft.isSaving) return;
    if (draft.isDirty) {
      final discard = draft.isEditing
          ? await confirmScheduleAction(
              context,
              title: ScheduleEditorSheet.discardEditQuestion,
              message: '뒤로 가면 바꾼 내용은 저장되지 않아요.',
              cancelLabel: '계속 수정',
              confirmLabel: '버리기',
            )
          : await confirmScheduleAction(
              context,
              title: ScheduleEditorSheet.discardQuestion,
              message: '취소하면 이 일정은 만들어지지 않아요.',
              cancelLabel: '계속 쓰기',
              confirmLabel: '버리기',
            );
      if (!discard) return;
    }
    if (!mounted) return;
    _draft.discard();
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    _flushTime();
    final confirmed = await confirmScheduleAction(
      context,
      title: ScheduleEditorSheet.deleteQuestion,
      message: '삭제한 일정은 되돌릴 수 없어요.',
      cancelLabel: '취소',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    final deleted = await _draft.delete();
    if (!mounted) return;
    setState(() => _deleting = false);
    if (deleted) Navigator.of(context).pop();
  }

  /// 저장된 값 그대로 보관함으로 옮긴다. 고치던 내용이 있으면 저장되지 않는다고 먼저 묻는다.
  Future<void> _archive() async {
    FocusScope.of(context).unfocus();
    _flushTime();
    final draft = ref.read(scheduleDraftProvider);
    if (draft == null || draft.isSaving) return;
    if (draft.isDirty &&
        !await confirmScheduleAction(
          context,
          title: '보관함으로 옮길까요?',
          message: '수정한 내용은 저장되지 않고, 저장된 일정 그대로 보관함으로 옮겨요.',
          cancelLabel: '계속 수정',
          confirmLabel: '옮기기',
        )) {
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final moved = await _draft.archiveEditing();
    if (!moved || !mounted) return;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('보관함으로 옮겼어요 · 보관함에서 다시 꺼낼 수 있어요')),
      );
  }

  Future<void> _pickAlarm(ScheduleDraft draft) async {
    _flushTime();
    final alarm = await SchedulePickers.pickAlarm(
      context,
      selected: draft.alarm,
    );
    if (alarm != null) _draft.setAlarm(alarm);
  }

  /// 지도에서 장소를 고른다. 닫기·뒤로 가기로 돌아오면 장소는 그대로다.
  Future<void> _pickPlace() async {
    FocusScope.of(context).unfocus();
    _flushTime();
    final place = await PlacePickerScreen.open(context);
    if (place == null || !mounted) return;
    _draft.pickPlace(place);
    _place.text = place.name;
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(scheduleDraftProvider);
    if (draft == null) return const SizedBox.shrink();
    final enabled = !draft.isSaving;
    final editing = draft.isEditing;
    final failure = draft.saveFailed
        ? ScheduleEditorSheet.saveFailedMessage
        : draft.deleteFailed
        ? ScheduleEditorSheet.deleteFailedMessage
        : draft.archiveFailed
        ? ScheduleEditorSheet.archiveFailedMessage
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ScheduleSheetFrame(
        title: editing ? '일정 수정' : '일정 추가',
        leading: editing
            ? IconButton(
                onPressed: enabled ? _close : null,
                tooltip: '뒤로 가기',
                style: IconButton.styleFrom(minimumSize: const Size.square(48)),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        banner: failure == null
            ? null
            : ScheduleFailureBanner(message: failure),
        rows: [
          ScheduleSheetRow(
            icon: Icons.title,
            label: '제목 (필수)',
            child: ScheduleFieldLabel(
              label: '제목, 필수',
              child: TextField(
                key: const ValueKey('schedule-title'),
                controller: _title,
                focusNode: _titleFocus,
                enabled: enabled,
                autofocus: _isNew,
                maxLength: ScheduleItem.titleMaxLength,
                textInputAction: TextInputAction.next,
                onChanged: _draft.setTitle,
                decoration: InputDecoration(
                  hintText: '예: 센소지 구경',
                  counterText: '',
                  errorText: draft.titleError
                      ? ScheduleEditorSheet.titleRequiredMessage
                      : null,
                ),
              ),
            ),
          ),
          ScheduleSheetRow(
            icon: Icons.event,
            label: '날짜·시간',
            child: ScheduleDateTimeField(
              draft: draft,
              today: _now(),
              onDate: enabled ? _draft.setDate : null,
              onTime: enabled ? _draft.setTime : null,
              timeWheelKey: _timeWheel,
            ),
          ),
          ScheduleSheetRow(
            icon: Icons.place_outlined,
            label: '장소',
            child: SchedulePlaceField(
              controller: _place,
              pickedPlace: draft.pickedPlace,
              enabled: enabled,
              onPickOnMap: _pickPlace,
              onChanged: _draft.setPlaceText,
            ),
          ),
          ScheduleSheetRow(
            icon: Icons.notifications_none,
            label: '알림',
            child: ScheduleAlarmField(
              alarm: draft.alarm,
              isPassed: draft.isAlarmPassed(_now()),
              onPressed: enabled ? () => _pickAlarm(draft) : null,
            ),
          ),
          ScheduleSheetRow(
            icon: Icons.notes,
            label: '메모',
            child: ScheduleFieldLabel(
              label: '메모',
              child: TextField(
                key: const ValueKey('schedule-memo'),
                controller: _memo,
                enabled: enabled,
                minLines: 3,
                maxLines: null,
                maxLength: ScheduleItem.memoMaxLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                keyboardType: TextInputType.multiline,
                onChanged: _draft.setMemo,
                decoration: const InputDecoration(hintText: '예약 번호, 준비물 등'),
              ),
            ),
          ),
          if (editing)
            ScheduleSheetRow(
              icon: Icons.inventory_2_outlined,
              label: '보관함',
              child: ScheduleFlatButton(
                key: const ValueKey('schedule-move-to-archive'),
                label: '보관함으로 이동',
                semanticsLabel: '보관함으로 이동, 타임라인에서 빼고 보관함에 둬요',
                onPressed: enabled ? _archive : null,
              ),
            ),
        ],
        footer: editing
            ? [
                _footerButton(
                  context,
                  label: '삭제',
                  onPressed: enabled ? _delete : null,
                  destructive: true,
                  busyLabel: _deleting && draft.isSaving ? '삭제 중' : null,
                ),
                _primaryButton(
                  draft,
                  label: '수정',
                  busyLabel: _deleting ? null : '수정 중',
                ),
              ]
            : [
                _footerButton(
                  context,
                  label: '취소',
                  onPressed: enabled ? _close : null,
                ),
                _primaryButton(draft, label: '저장', busyLabel: '저장 중'),
              ],
      ),
    );
  }

  /// 하단 강조 버튼. 저장 중이면 [busyLabel]이 있을 때만 진행 표시를 보인다
  /// (삭제 중에는 꺼지기만 하고 진행 표시는 삭제 버튼에 둔다).
  Widget _primaryButton(
    ScheduleDraft draft, {
    required String label,
    required String? busyLabel,
  }) {
    return FilledButton(
      onPressed: draft.isSaving ? null : _save,
      style: _footerStyle(FilledButton.styleFrom()),
      child: draft.isSaving && busyLabel != null
          ? _progress(context, busyLabel)
          : Text(label),
    );
  }

  /// 버튼 안 진행 표시. 꺼진 버튼 바탕 위에서도 보이게 보조 글자색으로 그린다.
  static Widget _progress(BuildContext context, String label) {
    return SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        semanticsLabel: label,
      ),
    );
  }

  static Widget _footerButton(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
    String? busyLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: _footerStyle(
        destructive
            ? OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
              ).copyWith(
                // 꺼졌을 때는 다른 꺼진 버튼처럼 흐린 테두리로 둬서, 오류색 테두리와
                // 흐린 글자가 섞여 눌리는 버튼처럼 보이지 않게 한다.
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.disabled)
                        ? colorScheme.onSurface.withValues(alpha: 0.12)
                        : colorScheme.error,
                  ),
                ),
              )
            : OutlinedButton.styleFrom(),
      ),
      child: busyLabel != null ? _progress(context, busyLabel) : Text(label),
    );
  }

  static ButtonStyle _footerStyle(ButtonStyle base) => base.copyWith(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}
