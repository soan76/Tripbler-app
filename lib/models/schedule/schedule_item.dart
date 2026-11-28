/// 일정 화면의 데이터(docs/mockups/schedule.md 4절).
///
/// 기기 저장소에 JSON으로 둔다. 읽을 때 형식이 틀린 값은 [ScheduleItem.tryParse]가
/// null로 돌려 그 항목만 버리게 한다.
///
/// 제목·메모 길이는 입력칸(`TextField.maxLength`)과 같이 글자(grapheme) 수로 센다.
/// UTF-16 단위(`String.length`)로 세면 이모지가 두 배로 세어지고 자를 때 깨진다.
library;

import 'package:flutter/widgets.dart' show StringCharacters;

/// 일정의 장소. 지도에서 고르면 주소·좌표·장소 id가 있고, 직접 입력하면 이름만 있다.
class ScheduledPlace {
  const ScheduledPlace({
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  /// 지도에서 고른 장소인지(직접 입력한 이름만 있는 장소가 아닌지).
  bool get isFromMap => placeId != null || address != null;

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, Object?> toJson() => {
    'name': name,
    if (address != null) 'address': address,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (placeId != null) 'placeId': placeId,
  };

  static ScheduledPlace? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final address = json['address'];
    final placeId = json['placeId'];
    return ScheduledPlace(
      name: name,
      address: address is String ? address : null,
      latitude: _double(json['latitude']),
      longitude: _double(json['longitude']),
      placeId: placeId is String ? placeId : null,
    );
  }

  static double? _double(Object? value) {
    if (value is! num) return null;
    final parsed = value.toDouble();
    return parsed.isFinite ? parsed : null;
  }
}

/// 일정 시작 몇 분 전에 알릴지. 이번 단계에서는 고른 값만 저장하고 알림은 예약하지 않는다.
enum ScheduleAlarm {
  none(null, '알림 없음'),
  atStart(0, '정시'),
  before5(5, '5분 전'),
  before10(10, '10분 전'),
  before30(30, '30분 전'),
  before60(60, '1시간 전');

  const ScheduleAlarm(this.minutesBefore, this.label);

  /// 시작 몇 분 전인지. [none]이면 null.
  final int? minutesBefore;

  /// 선택지에 보이는 이름.
  final String label;

  /// 입력 카드·상세 카드의 값 표시. 예: "30분 전 알림".
  String get summary => this == none ? label : '$label 알림';

  /// 알림 시각. [none]이면 null.
  DateTime? alertAt(DateTime startsAt) {
    final minutes = minutesBefore;
    return minutes == null
        ? null
        : startsAt.subtract(Duration(minutes: minutes));
  }

  static ScheduleAlarm? tryParse(Object? value) {
    for (final alarm in values) {
      if (alarm.name == value) return alarm;
    }
    return null;
  }
}

/// 저장된 일정 하나.
class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.alarm,
    required this.memo,
    required this.createdAt,
    this.place,
  });

  /// 글자(grapheme) 수 한도.
  static const int titleMaxLength = 50;
  static const int memoMaxLength = 500;

  /// 앞뒤 공백을 빼고 [titleMaxLength]글자까지 자른다.
  static String limitTitle(String title) =>
      _limit(title.trim(), titleMaxLength);

  /// 앞뒤 공백을 빼고 [memoMaxLength]글자까지 자른다.
  static String limitMemo(String memo) => _limit(memo.trim(), memoMaxLength);

  static String _limit(String text, int maxLength) {
    final characters = text.characters;
    return characters.length > maxLength
        ? characters.take(maxLength).toString()
        : text;
  }

  final String id;

  /// 앞뒤 공백을 뺀 1~[titleMaxLength]자.
  final String title;

  /// 날짜 + 정시(기기 현지 시각).
  final DateTime startsAt;
  final ScheduledPlace? place;
  final ScheduleAlarm alarm;

  /// 0~[memoMaxLength]자.
  final String memo;
  final DateTime createdAt;

  /// 일정이 끝났다고 보는지. 끝나는 시각이 없으므로 시작 1시간 뒤를 끝으로 본다.
  bool isPast(DateTime now) =>
      startsAt.add(const Duration(hours: 1)).isBefore(now);

  /// 타임라인 순서: 시작 시각, 같으면 먼저 만든 일정이 위.
  static int compare(ScheduleItem a, ScheduleItem b) {
    final byStart = a.startsAt.compareTo(b.startsAt);
    return byStart != 0 ? byStart : a.createdAt.compareTo(b.createdAt);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    // 현지 시각 그대로(시간대 표시 없이) 저장한다.
    'startsAt': startsAt.toIso8601String(),
    if (place != null) 'place': place!.toJson(),
    'alarm': alarm.name,
    'memo': memo,
    'createdAt': createdAt.toIso8601String(),
  };

  /// 형식이 틀리면 null. 한도를 넘은 제목·메모는 버리지 않고 글자 기준으로 자른다.
  static ScheduleItem? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final memo = json['memo'] ?? '';
    final startsAt = _date(json['startsAt']);
    final createdAt = _date(json['createdAt']);
    final alarm = ScheduleAlarm.tryParse(
      json['alarm'] ?? ScheduleAlarm.none.name,
    );
    final rawPlace = json['place'];
    final place = ScheduledPlace.tryParse(rawPlace);
    if (id is! String || id.isEmpty) return null;
    if (title is! String) return null;
    final limitedTitle = limitTitle(title);
    if (limitedTitle.isEmpty) return null;
    if (memo is! String) return null;
    if (startsAt == null || createdAt == null || alarm == null) return null;
    if (rawPlace != null && place == null) return null;
    return ScheduleItem(
      id: id,
      title: limitedTitle,
      startsAt: startsAt,
      place: place,
      alarm: alarm,
      memo: _limit(memo, memoMaxLength),
      createdAt: createdAt,
    );
  }

  /// [tryParse]로 [json]에서 만든 이 일정을 다시 저장해도 같은 뜻인지. 제목을 자르거나
  /// 앞뒤 공백을 뺐거나, 모르는 필드나 읽지 못한 장소 필드를 버렸으면 false다.
  ///
  /// 무해한 차이(키 순서, 정수/실수 좌표, null 필드, 생략한 메모·알림 기본값, 같은 시각의
  /// 다른 날짜 표기)는 같은 것으로 본다. 다시 저장하면 원본을 잃는지 판단할 때 쓴다.
  bool matchesJson(Map<Object?, Object?> json) {
    final normalized = {
      ...json,
      'memo': json['memo'] ?? '',
      'alarm': json['alarm'] ?? ScheduleAlarm.none.name,
      'startsAt': _date(json['startsAt'])?.toIso8601String(),
      'createdAt': _date(json['createdAt'])?.toIso8601String(),
    };
    return _sameJson(toJson(), normalized);
  }

  /// JSON 값 비교. 값이 null인 키는 없는 키로 보고, 숫자는 값으로 비교한다(35 == 35.0).
  static bool _sameJson(Object? a, Object? b) {
    if (a is Map && b is Map) {
      final aKeys = {
        for (final entry in a.entries)
          if (entry.value != null) entry.key,
      };
      final bKeys = {
        for (final entry in b.entries)
          if (entry.value != null) entry.key,
      };
      return aKeys.length == bKeys.length &&
          aKeys.every((k) => bKeys.contains(k) && _sameJson(a[k], b[k]));
    }
    return a == b;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
