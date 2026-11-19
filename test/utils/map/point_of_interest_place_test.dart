import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/utils/map/place_category_labels.dart';
import 'package:tripbler/utils/map/point_of_interest_place.dart';

TappedPointOfInterest _poi(String name) => TappedPointOfInterest(
  placeId: const PointOfInterestId('ChIJ-place'),
  name: name,
  position: const LatLng(37.57, 126.98),
);

void main() {
  test('지도 SDK가 준 장소 ID·이름·좌표로 장소를 만든다', () {
    final place = placeFromPointOfInterest(_poi('경복궁'));

    expect(place.id, 'ChIJ-place');
    expect(place.name, '경복궁');
    expect(place.latitude, 37.57);
    expect(place.longitude, 126.98);
    expect(place.hasCoordinates, isTrue);
  });

  test('주소·분류·평점·영업 여부는 비워 둔다(카드가 숨기고 버튼으로 조회)', () {
    final place = placeFromPointOfInterest(_poi('경복궁'));

    expect(place.address, isEmpty);
    expect(PlaceCategoryLabels.labelFor(place.category), isNull);
    expect(place.rating, isNull);
    expect(place.openNow, isNull);
  });

  test('이름의 줄바꿈과 겹친 공백은 한 칸으로 합친다', () {
    expect(
      placeFromPointOfInterest(_poi(' 경복궁\n 국립고궁박물관 ')).name,
      '경복궁 국립고궁박물관',
    );
  });

  test('이름이 비었으면 기본 이름을 쓴다', () {
    expect(placeFromPointOfInterest(_poi(' \n ')).name, unnamedPlaceName);
  });
}
