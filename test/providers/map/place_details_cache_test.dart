import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/providers/map/map_provider.dart';
import 'package:tripbler/providers/map/place_details_cache.dart';

PlaceModel _place(String id, {double? rating}) => PlaceModel(
  id: id,
  name: id,
  latitude: 37.5,
  longitude: 127.0,
  address: '',
  rating: rating,
  category: '',
  openNow: null,
);

void main() {
  late DateTime clock;
  late PlaceDetailsCache cache;

  setUp(() {
    clock = DateTime(2026, 11, 20, 12);
    cache = PlaceDetailsCache(() => clock);
  });

  test('MapNotifier의 상수는 캐시 상수와 같다', () {
    expect(MapNotifier.placeDetailsCacheTtl, PlaceDetailsCache.ttl);
    expect(MapNotifier.placeDetailsCacheTtl, const Duration(minutes: 30));
    expect(MapNotifier.maxCachedPlaceDetails, PlaceDetailsCache.maxEntries);
    expect(MapNotifier.maxCachedPlaceDetails, 50);
  });

  test('저장 후 29분 59초까지는 유효하고 30분이 되면 만료된다', () {
    final place = _place('a');
    cache.store(place);

    clock = clock.add(const Duration(minutes: 29, seconds: 59));
    expect(cache.fresh('a'), same(place));
    expect(cache.isExpired(cache['a']!), isFalse);

    clock = clock.add(const Duration(seconds: 1));
    expect(cache.fresh('a'), isNull);
    expect(cache.isExpired(cache['a']!), isTrue);
    // 만료돼도 항목은 남아 있다.
    expect(cache['a']!.place, same(place));
  });

  test('시계를 호출할 때마다 다시 읽는다', () {
    cache.store(_place('a'));
    final storedAt = cache['a']!.storedAt;

    clock = clock.add(PlaceDetailsCache.ttl);

    expect(storedAt, DateTime(2026, 11, 20, 12));
    expect(cache.fresh('a'), isNull);
  });

  test('없는 장소는 null이다', () {
    expect(cache['missing'], isNull);
    expect(cache.fresh('missing'), isNull);
    expect(cache.isNotEmpty, isFalse);
  });

  test('50곳을 넘으면 가장 오래 안 쓴 것부터 지운다', () {
    for (var i = 0; i < PlaceDetailsCache.maxEntries; i++) {
      cache.store(_place('p$i'));
    }

    // p0을 썼으므로 다음으로 오래된 p1이 지워진다.
    cache.markUsed('p0');
    cache.store(_place('new'));

    expect(cache['p0'], isNotNull);
    expect(cache['p1'], isNull);
    expect(cache['p2'], isNotNull);
    expect(cache['new'], isNotNull);

    cache.store(_place('new2'));

    expect(cache['p2'], isNull);
    expect(cache['p0'], isNotNull);
  });

  test('사용 표시는 순서만 바꾸고 저장 시각은 그대로 둔다', () {
    cache.store(_place('a'));
    final storedAt = cache['a']!.storedAt;

    clock = clock.add(const Duration(minutes: 20));
    cache.markUsed('a');

    expect(cache['a']!.storedAt, storedAt);

    clock = clock.add(const Duration(minutes: 10));
    expect(cache.fresh('a'), isNull);
  });

  test('없는 장소의 사용 표시는 아무것도 하지 않는다', () {
    cache.markUsed('missing');

    expect(cache['missing'], isNull);
    expect(cache.isNotEmpty, isFalse);
  });

  test('같은 id를 다시 저장하면 값·저장 시각을 바꾸고 맨 뒤로 옮긴다', () {
    for (var i = 0; i < PlaceDetailsCache.maxEntries; i++) {
      cache.store(_place('p$i'));
    }

    clock = clock.add(const Duration(minutes: 10));
    final updated = _place('p0', rating: 4.5);
    cache.store(updated);

    expect(cache['p0']!.place, same(updated));
    expect(cache['p0']!.storedAt, clock);

    // p0이 맨 뒤로 갔으므로 넘칠 때 p1이 지워진다.
    cache.store(_place('new'));

    expect(cache['p0'], isNotNull);
    expect(cache['p1'], isNull);
  });

  test('clear는 모든 항목을 지운다', () {
    cache.store(_place('a'));
    cache.store(_place('b'));
    expect(cache.isNotEmpty, isTrue);

    cache.clear();

    expect(cache.isNotEmpty, isFalse);
    expect(cache['a'], isNull);
    expect(cache['b'], isNull);
  });
}
