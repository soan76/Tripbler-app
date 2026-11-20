import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/place_model.dart';

/// 좌표가 있는 [places]를 모두 감싸는 범위. 좌표가 있는 장소가 없으면 null이다.
/// 카메라 이동은 화면이 맡는다. 장소가 하나면 남서·북동 꼭짓점이 같다.
///
/// 경도는 모든 좌표를 담는 가장 짧은 구간을 고른다. 정렬한 경도 사이 간격
/// (마지막과 첫째 사이는 360을 더한 순환 간격) 중 가장 큰 간격의 반대쪽이 범위다.
/// 날짜변경선을 넘는 범위는 west > east로 만든다(예: west 179.9, east -179.9).
/// 가장 큰 간격이 여럿이면 날짜변경선을 넘지 않는 순환 간격을 먼저 고르고,
/// 그다음은 서쪽(작은 경도)에 있는 간격을 고른다. 예: -90과 90이면 west -90, east 90.
LatLngBounds? placeBounds(List<PlaceModel> places) {
  double? south;
  double? north;
  final longitudes = <double>[];

  for (final place in places) {
    if (!place.hasCoordinates) {
      continue;
    }

    final latitude = place.latitude!;

    south = south == null || latitude < south ? latitude : south;
    north = north == null || latitude > north ? latitude : north;
    longitudes.add(place.longitude!);
  }

  if (south == null || north == null || longitudes.isEmpty) {
    return null;
  }

  longitudes.sort();

  // 순환 간격(날짜변경선 쪽)이 가장 크면 날짜변경선을 넘지 않는 일반 범위다.
  var west = longitudes.first;
  var east = longitudes.last;
  var largestGap = longitudes.first + 360 - longitudes.last;

  for (var i = 0; i < longitudes.length - 1; i++) {
    final gap = longitudes[i + 1] - longitudes[i];

    if (gap > largestGap) {
      largestGap = gap;
      west = longitudes[i + 1];
      east = longitudes[i];
    }
  }

  return LatLngBounds(
    southwest: LatLng(south, west),
    northeast: LatLng(north, east),
  );
}
