import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/widgets/map/map_camera.dart';

void main() {
  test('처음에는 서울시청 줌 13이고 지도 생성 전이라 준비되지 않았다', () {
    final camera = MapCamera();

    expect(camera.isReady, isFalse);
    expect(camera.target, const LatLng(37.5665, 126.9780));
    expect(camera.zoom, 13);
    expect(MapCamera.initialPosition.target, camera.target);
    expect(MapCamera.initialPosition.zoom, camera.zoom);
  });

  test('지도 이동으로 받은 카메라 위치를 중심·줌으로 기억한다', () {
    final camera = MapCamera();

    camera.updatePosition(
      const CameraPosition(target: LatLng(35.1, 129.0), zoom: 11.5),
    );

    expect(camera.target, const LatLng(35.1, 129.0));
    expect(camera.zoom, 11.5);
  });

  test('컨트롤러가 없으면 이동 요청은 아무것도 하지 않고 끝난다', () async {
    final camera = MapCamera();
    const place = PlaceModel(
      id: 'p',
      name: '장소',
      latitude: 37.57,
      longitude: 126.98,
      address: '',
      rating: null,
      category: '',
      openNow: null,
    );

    await camera.moveToCurrentLocation(const LatLng(37.5, 127.0));
    await camera.fitToResults(
      LatLngBounds(
        southwest: const LatLng(37.5, 126.9),
        northeast: const LatLng(37.6, 127.0),
      ),
    );
    await camera.fitToResults(null);
    await camera.moveToPlace(place);
    camera.dispose();

    expect(camera.isReady, isFalse);
    expect(camera.target, const LatLng(37.5665, 126.9780));
    expect(camera.zoom, 13);
  });

  group('zoomForSelectedPlace', () {
    test('현재 줌이 15보다 작으면 15로 확대한다', () {
      expect(MapCamera.zoomForSelectedPlace(13), 15);
      expect(MapCamera.zoomForSelectedPlace(14.99), 15);
    });

    test('현재 줌이 15 이상이면 그대로 둔다', () {
      expect(MapCamera.zoomForSelectedPlace(15), 15);
      expect(MapCamera.zoomForSelectedPlace(18.2), 18.2);
    });
  });
}
