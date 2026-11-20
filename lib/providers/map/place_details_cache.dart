import 'dart:collection';

import '../../models/place_model.dart';

/// 상세 캐시 항목. 저장 시각으로 만료 여부를 판단한다.
class CachedPlaceDetails {
  const CachedPlaceDetails({required this.place, required this.storedAt});

  final PlaceModel place;
  final DateTime storedAt;
}

/// 장소별 상세 결과(평점·영업 여부)를 기억해 둔다.
///
/// 순서는 마지막으로 저장하거나 쓴 순서다. [maxEntries]를 넘으면 가장 오래 안 쓴
/// 것부터 지운다. 만료([ttl])는 저장 시각으로만 판단한다.
class PlaceDetailsCache {
  /// [now]는 만료 판단·저장 시각에 쓰는 시계다. 쓸 때마다 다시 부른다.
  PlaceDetailsCache(this._now);

  /// 상세 결과를 기억해 두는 최대 장소 수. 넘으면 가장 오래 안 쓴 것부터 지운다.
  static const int maxEntries = 50;

  /// 상세 결과(영업 여부 등)를 재사용하는 시간. 지나면 다시 조회한다.
  static const Duration ttl = Duration(minutes: 30);

  final DateTime Function() _now;

  final LinkedHashMap<String, CachedPlaceDetails> _entries =
      LinkedHashMap<String, CachedPlaceDetails>();

  bool get isNotEmpty => _entries.isNotEmpty;

  /// [placeId]의 항목. 만료된 항목도 돌려주며 순서는 바꾸지 않는다.
  CachedPlaceDetails? operator [](String placeId) => _entries[placeId];

  /// 만료되지 않은 상세 결과만 돌려준다. 만료된 항목은 다시 조회해 갱신한다.
  PlaceModel? fresh(String placeId) {
    final entry = _entries[placeId];

    if (entry == null) {
      return null;
    }

    if (isExpired(entry)) {
      return null;
    }

    return entry.place;
  }

  /// 저장한 지 [ttl] 이상 지났는지.
  bool isExpired(CachedPlaceDetails entry) {
    return _now().difference(entry.storedAt) >= ttl;
  }

  /// [place]를 지금 시각으로 저장하고 맨 뒤로 옮긴다. 상한을 넘으면 앞에서부터 지운다.
  void store(PlaceModel place) {
    _entries.remove(place.id);
    _entries[place.id] = CachedPlaceDetails(place: place, storedAt: _now());

    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 받아 둔 상세 결과를 썼다: 맨 뒤로 옮겨 상한을 넘을 때 가장 오래 안 쓴 것부터
  /// 지워지게 한다. 저장 시각(만료 판단 기준)은 그대로 둔다.
  void markUsed(String placeId) {
    final entry = _entries.remove(placeId);

    if (entry != null) {
      _entries[placeId] = entry;
    }
  }

  void clear() => _entries.clear();
}
