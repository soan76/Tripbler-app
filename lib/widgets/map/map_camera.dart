import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/place_model.dart';

/// 지도 화면의 카메라 상태와 이동.
///
/// [GoogleMapController]를 갖고, `onCameraMove`로 받은 현재 중심·줌을 기억한다.
/// 컨트롤러가 아직 없으면(지도 생성 전) 이동 요청은 아무것도 하지 않는다.
/// 이동 실패(지도가 아직 배치되지 않은 경우 등)는 로그만 남기고 무시한다.
class MapCamera {
  // 위치를 가져오지 못했을 때 사용할 기본 위치
  static const LatLng defaultTarget = LatLng(37.5665, 126.9780);

  static const double defaultZoom = 13;

  // 지도 최초 카메라 위치
  static const CameraPosition initialPosition = CameraPosition(
    target: defaultTarget,
    zoom: defaultZoom,
  );

  // 검색 결과가 1개일 때 줌, 결과를 고를 때 최소 줌
  static const double singleResultZoom = 16;
  static const double selectedPlaceMinZoom = 15;

  // 결과 전체를 맞출 때 가장자리 여백(px)
  static const double resultsBoundsPadding = 64;

  // 현재 위치로 이동할 때 줌
  static const double currentLocationZoom = 17;

  GoogleMapController? _controller;

  LatLng _target = defaultTarget;
  double _zoom = defaultZoom;

  /// 지도가 만들어져 카메라를 움직일 수 있는지.
  bool get isReady => _controller != null;

  /// 현재 지도 카메라 중심 좌표.
  LatLng get target => _target;

  /// 현재 지도 줌 레벨.
  double get zoom => _zoom;

  /// 지도 생성 완료 시 받은 컨트롤러를 연결한다.
  void attach(GoogleMapController controller) {
    _controller = controller;
  }

  /// 지도 이동/확대/축소로 바뀐 카메라 위치를 기억한다.
  void updatePosition(CameraPosition position) {
    _target = position.target;
    _zoom = position.zoom;
  }

  /// 장소를 고를 때의 줌. 지금 줌이 [selectedPlaceMinZoom]보다 작으면 그만큼 확대한다.
  static double zoomForSelectedPlace(double currentZoom) {
    return currentZoom < selectedPlaceMinZoom
        ? selectedPlaceMinZoom
        : currentZoom;
  }

  /// 현재 위치로 지도 카메라 이동
  Future<void> moveToCurrentLocation(LatLng position) async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: position, zoom: currentLocationZoom),
        ),
      );
    } catch (error) {
      debugPrint('현재 위치 카메라 이동 실패: $error');
    }
  }

  /// 결과 전체가 보이게 카메라를 맞춘다. 결과가 1개면(남서·북동이 같음) 그 장소로 이동한다.
  Future<void> fitToResults(LatLngBounds? bounds) async {
    final controller = _controller;

    if (controller == null || bounds == null) {
      return;
    }

    try {
      if (bounds.southwest == bounds.northeast) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(bounds.southwest, singleResultZoom),
        );
      } else {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, resultsBoundsPadding),
        );
      }
    } catch (error) {
      // 지도가 아직 배치되지 않았을 때 생기는 예외는 무시한다.
      debugPrint('검색 결과로 카메라 이동 실패: $error');
    }
  }

  /// 고른 장소로 카메라를 옮긴다. 좌표가 없으면 옮기지 않는다.
  Future<void> moveToPlace(PlaceModel place) async {
    final controller = _controller;

    if (controller == null || !place.hasCoordinates) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(place.latitude!, place.longitude!),
          zoomForSelectedPlace(_zoom),
        ),
      );
    } catch (error) {
      debugPrint('선택한 장소로 카메라 이동 실패: $error');
    }
  }

  /// Google Map Controller 종료
  void dispose() {
    _controller?.dispose();
  }
}
