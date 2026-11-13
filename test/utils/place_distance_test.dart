import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/utils/map/place_distance.dart';

PlaceModel _place(String id, {double? latitude, double? longitude}) {
  return PlaceModel(
    id: id,
    name: '장소 $id',
    latitude: latitude,
    longitude: longitude,
    address: '',
    rating: null,
    category: '',
    openNow: null,
  );
}

void main() {
  const seoulCityHall = LatLng(37.5663, 126.9779);

  group('metersBetween', () {
    test('같은 좌표는 0m', () {
      expect(PlaceDistance.metersBetween(seoulCityHall, seoulCityHall), 0);
    });

    test('적도에서 경도 1도는 지구 둘레의 1/360(약 111.2km)', () {
      final meters = PlaceDistance.metersBetween(
        const LatLng(0, 0),
        const LatLng(0, 1),
      );

      expect(meters, closeTo(2 * 3.141592653589793 * 6371008.8 / 360, 0.01));
    });

    test('위도 0.001도는 약 111m', () {
      final meters = PlaceDistance.metersBetween(
        const LatLng(37.0, 127.0),
        const LatLng(37.001, 127.0),
      );

      expect(meters, closeTo(111.2, 0.5));
    });

    test('날짜변경선을 건너는 짧은 거리도 가깝게 계산한다', () {
      final meters = PlaceDistance.metersBetween(
        const LatLng(0, 179.999),
        const LatLng(0, -179.999),
      );

      expect(meters, closeTo(222.4, 1));
    });
  });

  group('metersTo', () {
    test('기준 위치나 장소 좌표가 없으면 null', () {
      expect(
        PlaceDistance.metersTo(
          null,
          _place('a', latitude: 37.5, longitude: 127),
        ),
        isNull,
      );
      expect(PlaceDistance.metersTo(seoulCityHall, _place('a')), isNull);
      expect(
        PlaceDistance.metersTo(seoulCityHall, _place('a', latitude: 37.5)),
        isNull,
      );
    });
  });

  group('sortByDistance', () {
    test('가까운 순으로 정렬하고 좌표 없는 장소는 원래 순서대로 맨 뒤', () {
      final places = [
        _place('noCoord1'),
        _place('far', latitude: 37.60, longitude: 126.9779),
        _place('near', latitude: 37.567, longitude: 126.9779),
        _place('noCoord2'),
        _place('mid', latitude: 37.58, longitude: 126.9779),
      ];

      final sorted = PlaceDistance.sortByDistance(places, seoulCityHall);

      expect(sorted.map((p) => p.id), [
        'near',
        'mid',
        'far',
        'noCoord1',
        'noCoord2',
      ]);
      // 원본 목록은 바꾸지 않는다.
      expect(places.first.id, 'noCoord1');
    });

    test('거리가 같으면 원래 순서를 유지한다', () {
      final places = [
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          _place(id, latitude: 37.57, longitude: 126.9779),
      ];

      final sorted = PlaceDistance.sortByDistance(places, seoulCityHall);

      expect(sorted.map((p) => p.id), ['a', 'b', 'c', 'd', 'e']);
    });

    test('기준 위치가 없으면 원래 순서 그대로', () {
      final places = [
        _place('far', latitude: 37.60, longitude: 126.9779),
        _place('near', latitude: 37.567, longitude: 126.9779),
      ];

      expect(PlaceDistance.sortByDistance(places, null).map((p) => p.id), [
        'far',
        'near',
      ]);
    });
  });

  group('format', () {
    final cases = <double, String>{
      0: '0m',
      4: '0m',
      5: '10m',
      123: '120m',
      985: '990m',
      994: '990m',
      995: '1.0km',
      999.9: '1.0km',
      1000: '1.0km',
      1249: '1.2km',
      1250: '1.3km',
      9949: '9.9km',
      9950: '10km',
      12345: '12km',
      325000: '325km',
    };

    cases.forEach((meters, expected) {
      test('$meters m → $expected', () {
        expect(PlaceDistance.format(meters), expected);
      });
    });
  });
}
