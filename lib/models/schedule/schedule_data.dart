import 'schedule_item.dart';

/// 보관함에 옮긴 일정(docs/mockups/schedule.md 4절 "보관함"). 타임라인에서 빠지고, 사용자가
/// 직접 지우기 전에는 지우지 않는다.
class ArchivedScheduleItem {
  const ArchivedScheduleItem({required this.item, required this.archivedAt});

  final ScheduleItem item;
  final DateTime archivedAt;

  Map<String, Object?> toJson() => {
    ...item.toJson(),
    'archivedAt': archivedAt.toIso8601String(),
  };

  static ArchivedScheduleItem? tryParse(Object? json) {
    if (json is! Map) return null;
    final archivedAt = _date(json['archivedAt']);
    final item = ScheduleItem.tryParse(json);
    if (item == null || archivedAt == null) return null;
    return ArchivedScheduleItem(item: item, archivedAt: archivedAt);
  }

  /// 다시 저장해도 같은 뜻인지([ScheduleItem.matchesJson]과 같은 기준).
  bool matchesJson(Map<Object?, Object?> json) {
    final rest = {...json}..remove('archivedAt');
    return item.matchesJson(rest) &&
        _date(json['archivedAt'])?.toIso8601String() ==
            archivedAt.toIso8601String();
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// 기기에 저장하는 일정 전체: 타임라인([items], 사용자가 정한 순서)과 보관함([archived]).
class ScheduleData {
  const ScheduleData({this.items = const [], this.archived = const []});

  static const ScheduleData empty = ScheduleData();

  /// 타임라인 순서(위에서 아래). 날짜·시간 순과 다를 수 있다.
  final List<ScheduleItem> items;
  final List<ArchivedScheduleItem> archived;
}

/// 백업을 만든 이유.
enum ScheduleBackupKind {
  /// 사용자가 `지금 백업`으로 만든 복사본. 최근 몇 개만 남긴다.
  manual,

  /// 기기 저장값을 읽지 못하거나 읽으며 바꿔야 해서 원래 내용을 보관한 것. 사용자가 직접
  /// 지우기 전에는 지우지 않는다.
  auto,
}

/// 기기에 보관한 백업 하나. [raw]는 그 시점의 저장값 원문이다.
class ScheduleBackup {
  const ScheduleBackup({
    required this.id,
    required this.savedAt,
    required this.kind,
    required this.raw,
    this.seen = false,
  });

  final String id;
  final DateTime savedAt;
  final ScheduleBackupKind kind;
  final String raw;

  /// 읽지 못해 보관한 백업을 사용자가 확인했는지(알림을 다시 띄우지 않는다).
  final bool seen;

  ScheduleBackup copyWith({bool? seen}) => ScheduleBackup(
    id: id,
    savedAt: savedAt,
    kind: kind,
    raw: raw,
    seen: seen ?? this.seen,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'savedAt': savedAt.toIso8601String(),
    'kind': kind.name,
    'seen': seen,
    'raw': raw,
  };

  /// 형식이 틀리면 null. id·종류가 없는 예전 항목(읽지 못한 값 백업만 있던 때)은 읽지 못해
  /// 보관한 백업으로 보고 보관 시각으로 id를 만든다.
  static ScheduleBackup? tryParse(Object? json) {
    if (json is! Map) return null;
    final savedAtText = json['savedAt'];
    final raw = json['raw'];
    if (savedAtText is! String || raw is! String) return null;
    final savedAt = DateTime.tryParse(savedAtText);
    if (savedAt == null) return null;
    final kindName = json['kind'];
    final kind = kindName == ScheduleBackupKind.manual.name
        ? ScheduleBackupKind.manual
        : ScheduleBackupKind.auto;
    final id = json['id'];
    final seen = json['seen'];
    return ScheduleBackup(
      id: id is String && id.isNotEmpty ? id : 'auto-$savedAtText',
      savedAt: savedAt,
      kind: kind,
      raw: raw,
      seen: seen is bool && seen,
    );
  }
}

/// 저장값(또는 백업 원문)을 읽은 결과.
enum ScheduleReadStatus {
  ok,

  /// JSON이 깨졌거나 형식이 아니다.
  corrupt,

  /// 이 앱보다 새 버전의 형식이다(앱을 업데이트하면 읽을 수 있다).
  newerVersion,
}

/// [ScheduleReadStatus]와 살린 값.
class ScheduleReadResult {
  const ScheduleReadResult({
    required this.status,
    this.data = ScheduleData.empty,
    this.unreadable = 0,
    this.changed = false,
  });

  final ScheduleReadStatus status;
  final ScheduleData data;

  /// 버린 항목 수(형식 오류·겹친 id).
  final int unreadable;

  /// 다시 저장하면 원래 내용을 잃는지(항목을 버렸거나, 살린 값이 바뀌었거나, 예전 형식이 아닌
  /// 손상·새 버전 값).
  final bool changed;
}
