import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/utils/map/place_distance.dart';

PlaceModel _place({double? latitude, double? longitude}) {
  return PlaceModel(
    id: 'p',
    name: '장소',
    latitude: latitude,
    longitude: longitude,
    address: '',
    rating: null,
    category: '',
    openNow: null,
  );
}

void main() {
  group('PlaceDistance.labelTo', () {
    const origin = LatLng(37.5663, 126.9779);

    test('기준 위치가 없으면 null', () {
      expect(
        PlaceDistance.labelTo(null, _place(latitude: 37.57, longitude: 126.98)),
        isNull,
      );
    });

    test('장소 좌표가 없으면 null', () {
      expect(PlaceDistance.labelTo(origin, _place()), isNull);
      expect(PlaceDistance.labelTo(origin, _place(latitude: 37.57)), isNull);
    });

    test('같은 위치면 0m', () {
      expect(
        PlaceDistance.labelTo(
          origin,
          _place(latitude: origin.latitude, longitude: origin.longitude),
        ),
        '0m',
      );
    });

    test('거리를 계산해 format과 같은 문구를 돌려준다', () {
      final place = _place(latitude: 37.5796, longitude: 126.9770);
      final meters = PlaceDistance.metersTo(origin, place)!;

      expect(
        PlaceDistance.labelTo(origin, place),
        PlaceDistance.format(meters),
      );
      expect(PlaceDistance.labelTo(origin, place), endsWith('km'));
    });
  });
}
