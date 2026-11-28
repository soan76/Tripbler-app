import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/schedule/schedule_item.dart';
import 'schedule_provider.dart';

/// 입력 카드에서 작성 중인 일정(docs/mockups/schedule.md 2-3·2-4·3-1절).
///
/// 새 일정이거나, 저장한 일정([editing])을 고치는 중이다. 화면 위젯이 아니라
/// [ScheduleDraftNotifier]가 갖고 있어 장소 고르기 화면에 다녀와도 그대로 남는다.
class ScheduleDraft {
  const ScheduleDraft({
    required this.date,
    required this.hour,
    this.minute = 0,
    this.title = '',
    this.placeText = '',
    this.pickedPlace,
    this.alarm = ScheduleAlarm.none,
    this.memo = '',
    this.titleError = false,
    this.isSaving = false,
    this.saveFailed = false,
    this.deleteFailed = false,
    this.archiveFailed = false,
    this.editing,
  });

  /// 저장한 일정의 값으로 수정을 시작한다. 지도에서 고른 장소면 주소·좌표도 그대로 둔다.
  factory ScheduleDraft.fromItem(ScheduleItem item) {
    final place = item.place;
    final startsAt = item.startsAt;
    return ScheduleDraft(
      date: DateTime(startsAt.year, startsAt.month, startsAt.day),
      hour: startsAt.hour,
      minute: startsAt.minute,
      title: item.title,
      placeText: place?.name ?? '',
      // 이름 말고 다른 값(주소·좌표·장소 id)이 하나라도 있으면 그대로 둔다. 이름만 다시 만들면
      // 수정 저장 때 그 값을 잃는다.
      pickedPlace: place != null && (place.isFromMap || place.hasCoordinates)
          ? place
          : null,
      alarm: item.alarm,
      memo: item.memo,
      editing: item,
    );
  }

  final String title;

  /// 날짜(시각은 0시).
  final DateTime date;

  /// 시작 시(0~23).
  final int hour;

  /// 시작 분(0~59, 1분 단위).
  final int minute;

  /// 장소 칸에 보이는 글자.
  final String placeText;

  /// 지도에서 고른 장소. 장소 칸 글자를 고치면 지운다(직접 입력으로 바뀜).
  final ScheduledPlace? pickedPlace;
  final ScheduleAlarm alarm;
  final String memo;

  /// 저장하려 했는데 제목이 비어 있었는지.
  final bool titleError;
  final bool isSaving;

  /// 마지막 저장 시도가 기기 저장소 오류로 실패했는지.
  final bool saveFailed;

  /// 마지막 삭제 시도가 기기 저장소 오류로 실패했는지.
  final bool deleteFailed;

  /// 마지막 보관함 이동 시도가 기기 저장소 오류로 실패했는지.
  final bool archiveFailed;

  /// 고치는 중인 저장한 일정. 새 일정이면 null.
  final ScheduleItem? editing;

  bool get isEditing => editing != null;

  DateTime get startsAt =>
      DateTime(date.year, date.month, date.day, hour, minute);

  /// 버릴지 물어볼 내용이 있는지. 새 일정은 무엇이든 입력했으면(날짜·시간은 기본값이 있어
  /// 보지 않는다), 수정은 저장한 값과 달라졌으면 true.
  bool get isDirty {
    final editing = this.editing;
    if (editing != null) {
      return _signature != ScheduleDraft.fromItem(editing)._signature;
    }
    return title.trim().isNotEmpty ||
        placeText.trim().isNotEmpty ||
        memo.trim().isNotEmpty ||
        alarm != ScheduleAlarm.none;
  }

  /// 저장했을 때 결과가 같은지 비교하는 값(앞뒤 공백은 저장 때 빠지므로 무시한다).
  Object get _signature => (
    title.trim(),
    startsAt,
    placeText.trim(),
    pickedPlace?.placeId,
    pickedPlace?.address,
    pickedPlace?.latitude,
    pickedPlace?.longitude,
    alarm,
    memo.trim(),
  );

  /// 고른 알림 시각이 이미 지났는지. 일정 저장은 막지 않는다.
  bool isAlarmPassed(DateTime now) {
    final alertAt = alarm.alertAt(startsAt);
    return alertAt != null && !alertAt.isAfter(now);
  }

  /// 저장할 장소. 지도에서 고른 장소가 있으면 그것, 직접 입력했으면 이름만, 비었으면 null.
  ScheduledPlace? get place {
    final text = placeText.trim();
    if (text.isEmpty) return null;
    return pickedPlace ?? ScheduledPlace(name: text);
  }

  ScheduleDraft copyWith({
    String? title,
    DateTime? date,
    int? hour,
    int? minute,
    String? placeText,
    ScheduledPlace? pickedPlace,
    bool clearPickedPlace = false,
    ScheduleAlarm? alarm,
    String? memo,
    bool? titleError,
    bool? isSaving,
    bool? saveFailed,
    bool? deleteFailed,
    bool? archiveFailed,
  }) {
    return ScheduleDraft(
      title: title ?? this.title,
      date: date ?? this.date,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      placeText: placeText ?? this.placeText,
      pickedPlace: clearPickedPlace ? null : (pickedPlace ?? this.pickedPlace),
      alarm: alarm ?? this.alarm,
      memo: memo ?? this.memo,
      titleError: titleError ?? this.titleError,
      isSaving: isSaving ?? this.isSaving,
      saveFailed: saveFailed ?? this.saveFailed,
      deleteFailed: deleteFailed ?? this.deleteFailed,
      archiveFailed: archiveFailed ?? this.archiveFailed,
      editing: editing,
    );
  }
}

/// 작성 중인 일정. 입력 카드가 닫혀 있으면 null.
class ScheduleDraftNotifier extends Notifier<ScheduleDraft?> {
  /// 작성을 새로 시작하거나 버릴 때마다 올린다. 앞선 작성의 저장 결과는 반영하지 않는다.
  int _generation = 0;

  /// 일정 id가 같은 마이크로초에 겹치지 않게 붙인다.
  int _idSequence = 0;

  @override
  ScheduleDraft? build() => null;

  DateTime _now() => ref.read(scheduleClockProvider)();

  /// 기본값으로 새 작성을 시작한다.
  ///
  /// 기본 날짜·시간: 마지막 일정이 아직 지나지 않았고 23시 전이면 그 날짜의 한 시간 뒤
  /// (분은 그대로), 아니면 오늘 "지금 다음 정시"(23시가 넘으면 내일 오전 9:00).
  void start() {
    _generation++;
    final now = _now();
    final items = ref.read(scheduleProvider).items;
    final last = items.isEmpty ? null : items.last;
    final DateTime date;
    final int hour;
    var minute = 0;
    if (last != null &&
        !last.startsAt.isBefore(now) &&
        last.startsAt.hour < 23) {
      date = DateTime(
        last.startsAt.year,
        last.startsAt.month,
        last.startsAt.day,
      );
      hour = last.startsAt.hour + 1;
      minute = last.startsAt.minute;
    } else if (now.hour < 23) {
      date = DateTime(now.year, now.month, now.day);
      hour = now.hour + 1;
    } else {
      date = DateTime(now.year, now.month, now.day + 1);
      hour = 9;
    }
    state = ScheduleDraft(date: date, hour: hour, minute: minute);
  }

  /// 저장한 [item]을 고치기 시작한다.
  void startEdit(ScheduleItem item) {
    _generation++;
    state = ScheduleDraft.fromItem(item);
  }

  /// 작성을 버린다(취소).
  void discard() {
    _generation++;
    state = null;
  }

  void _update(ScheduleDraft Function(ScheduleDraft draft) change) {
    final draft = state;
    if (draft == null || draft.isSaving) return;
    state = change(draft);
  }

  void setTitle(String title) => _update(
    (d) => d.copyWith(
      title: title,
      titleError: d.titleError && title.trim().isEmpty,
    ),
  );

  void setDate(DateTime date) => _update(
    (d) => d.copyWith(date: DateTime(date.year, date.month, date.day)),
  );

  /// 시작 시각(시 0~23, 분 0~59)을 바꾼다. 범위를 벗어나면 무시한다.
  void setTime(int hour, int minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return;
    _update((d) => d.copyWith(hour: hour, minute: minute));
  }

  /// 장소 칸을 직접 고쳤을 때. 지도에서 고른 이름과 달라지면 고른 장소를 지운다.
  void setPlaceText(String text) => _update((d) {
    final picked = d.pickedPlace;
    return d.copyWith(
      placeText: text,
      clearPickedPlace: picked != null && picked.name != text,
    );
  });

  /// 장소 고르기 화면에서 고른 장소로 장소 칸을 채운다.
  void pickPlace(ScheduledPlace place) =>
      _update((d) => d.copyWith(placeText: place.name, pickedPlace: place));

  void setAlarm(ScheduleAlarm alarm) =>
      _update((d) => d.copyWith(alarm: alarm));

  void setMemo(String memo) => _update((d) => d.copyWith(memo: memo));

  /// 저장한다. 새 일정은 추가하고, 수정 중이면 같은 id·만든 시각으로 바꿔 저장한다.
  /// 성공하면 작성을 끝내고(state null) 저장한 일정을 돌려준다.
  ///
  /// 제목이 비었거나 저장에 실패하면 null을 돌려주고 입력값은 그대로 둔다.
  Future<ScheduleItem?> save() async {
    final draft = state;
    if (draft == null || draft.isSaving) return null;
    final title = draft.title.trim();
    if (title.isEmpty) {
      state = draft.copyWith(titleError: true);
      return null;
    }

    final generation = _generation;
    final now = _now();
    final editing = draft.editing;
    final item = ScheduleItem(
      id: editing?.id ?? '${now.microsecondsSinceEpoch}-${_idSequence++}',
      title: ScheduleItem.limitTitle(title),
      startsAt: draft.startsAt,
      place: draft.place,
      alarm: draft.alarm,
      memo: ScheduleItem.limitMemo(draft.memo),
      createdAt: editing?.createdAt ?? now,
    );
    state = draft.copyWith(
      isSaving: true,
      saveFailed: false,
      deleteFailed: false,
      archiveFailed: false,
      titleError: false,
    );

    try {
      final schedules = ref.read(scheduleProvider.notifier);
      await (editing == null ? schedules.add(item) : schedules.update(item));
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = state?.copyWith(isSaving: false, saveFailed: true);
      }
      return null;
    }

    if (!ref.mounted || generation != _generation) return item;
    _generation++;
    state = null;
    return item;
  }

  /// 고치는 중인 일정을 지운다. 성공하면 작성을 끝내고(state null) true.
  ///
  /// 수정 중이 아니거나 저장소에서 지우지 못하면 false를 돌려주고 입력값은 그대로 둔다.
  Future<bool> delete() async {
    final draft = state;
    final editing = draft?.editing;
    if (draft == null || editing == null || draft.isSaving) return false;

    final generation = _generation;
    state = draft.copyWith(
      isSaving: true,
      saveFailed: false,
      deleteFailed: false,
      archiveFailed: false,
    );
    try {
      await ref.read(scheduleProvider.notifier).remove(editing.id);
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = state?.copyWith(isSaving: false, deleteFailed: true);
      }
      return false;
    }

    if (!ref.mounted || generation != _generation) return true;
    _generation++;
    state = null;
    return true;
  }

  /// 고치는 중인 일정을 저장된 값 그대로 보관함으로 옮긴다(고치던 값은 저장하지 않는다).
  /// 성공하면 작성을 끝내고(state null) true. 실패하면 false를 돌려주고 입력값은 그대로 둔다.
  Future<bool> archiveEditing() async {
    final draft = state;
    final editing = draft?.editing;
    if (draft == null || editing == null || draft.isSaving) return false;

    final generation = _generation;
    state = draft.copyWith(
      isSaving: true,
      saveFailed: false,
      deleteFailed: false,
      archiveFailed: false,
    );
    try {
      await ref.read(scheduleProvider.notifier).archive(editing.id);
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = state?.copyWith(isSaving: false, archiveFailed: true);
      }
      return false;
    }

    if (!ref.mounted || generation != _generation) return true;
    _generation++;
    state = null;
    return true;
  }
}

final scheduleDraftProvider =
    NotifierProvider<ScheduleDraftNotifier, ScheduleDraft?>(
      ScheduleDraftNotifier.new,
    );
