import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../utils/map/map_style.dart';
/// 구글 맵을 표시하는 위젯 클래스
class TripblerGoogleMap extends StatelessWidget {
  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final void Function(GoogleMapController controller) onMapCreated;
  final void Function(LatLng latLng) onTap;
  final void Function(CameraPosition position) onCameraMove;
  final bool isDarkMode;

  const TripblerGoogleMap({
    super.key,
    required this.initialCameraPosition,
    required this.markers,
    required this.onMapCreated,
    required this.onTap,
    required this.onCameraMove,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: initialCameraPosition,
      onMapCreated: onMapCreated,

      // 시스템 다크 모드에 따라 지도 스타일 변경
      style: isDarkMode ? MapStyle.dark : null,

      // 백엔드에서 받아온 장소 목록 + 현재 위치 방향 마커를 함께 표시함.
      markers: markers,

      // 지도 탭 좌표를 상위 화면으로 전달함.
      onTap: onTap,

      // 지도를 이동/확대/축소할 때마다 카메라 정보를 상위 화면으로 전달함.
      onCameraMove: onCameraMove,

      mapType: MapType.normal,

      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,

      compassEnabled: true,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,

      // 낮은 숫자일수록 줌아웃, 높은 숫자일수록 줌인.
      // Scale Bar는 5m ~ 200km 범위의 표시값을 사용함.
      minMaxZoomPreference: const MinMaxZoomPreference(5, 20),

      // 현재 위치는 직접 만든 방향 마커로 표시하므로
      // GoogleMap 기본 현재 위치 파란 점은 꺼둠.
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
    );
  }
}
