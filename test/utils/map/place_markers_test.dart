import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/utils/map/place_markers.dart';

void main() {
  group('currentLocationMarker', () {
    const position = LatLng(37.5665, 126.9780);

    test('위치를 아직 모르면 마커를 만들지 않는다', () {
      expect(
        currentLocationMarker(position: null, heading: 90, icon: null),
        isNull,
      );
    });

    test('현재 위치·방향으로 평평한 가운데 기준 마커를 장소 마커보다 위에 만든다', () {
      final icon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      );

      final marker = currentLocationMarker(
        position: position,
        heading: 45,
        icon: icon,
      )!;

      expect(marker.markerId, const MarkerId('current_user_location'));
      expect(marker.position, position);
      expect(marker.rotation, 45);
      expect(marker.anchor, const Offset(0.5, 0.5));
      expect(marker.flat, isTrue);
      expect(marker.icon, icon);
      expect(marker.zIndexInt, 9999);
    });

    test('아이콘을 아직 불러오지 못했으면 기본 파란 마커로 표시한다', () {
      final marker = currentLocationMarker(
        position: position,
        heading: 0,
        icon: null,
      )!;

      expect(
        marker.icon.toJson(),
        BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ).toJson(),
      );
    });
  });
}
