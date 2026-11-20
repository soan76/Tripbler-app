import 'dart:ui' show Offset;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/place_model.dart';

/// 지도에 그릴 장소 마커. 선택한 장소는 색과 겹침 순서로 구분한다.
///
/// - [searchResults]: 좌표가 있는 결과마다 `search_<id>` 마커를 만든다. 탭하면
///   [onSearchResultTap]으로 그 결과를 넘긴다.
/// - [selectedPlace]: [isSelectedPlaceFromMap]이 true면(지도의 장소 아이콘에서 고름)
///   검색 결과 마커가 없으므로 `map_<id>` 마커를 따로 만든다.
Set<Marker> placeMarkers({
  required List<PlaceModel> searchResults,
  required PlaceModel? selectedPlace,
  required bool isSelectedPlaceFromMap,
  required void Function(PlaceModel place) onSearchResultTap,
}) {
  final markers = <Marker>{};

  // 검색 결과 마커. 탭하면 그 결과를 선택하고, 선택된 마커는 색과 겹침 순서로 구분한다.
  // 모양은 화면 디자인 단계에서 다듬는다.
  final selectedId = selectedPlace?.id;

  for (final place in searchResults) {
    if (!place.hasCoordinates) {
      continue;
    }

    final isSelected = place.id == selectedId;

    markers.add(
      Marker(
        markerId: MarkerId('search_${place.id}'),
        position: LatLng(place.latitude!, place.longitude!),
        icon: isSelected
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
            : BitmapDescriptor.defaultMarker,
        zIndexInt: isSelected ? 2 : 1,
        onTap: () {
          onSearchResultTap(place);
        },
      ),
    );
  }

  // 지도의 장소 아이콘에서 고른 장소. 검색 결과 마커처럼 선택 색으로 표시한다.
  final selected = selectedPlace;

  if (isSelectedPlaceFromMap && selected != null && selected.hasCoordinates) {
    markers.add(
      Marker(
        markerId: MarkerId('map_${selected.id}'),
        position: LatLng(selected.latitude!, selected.longitude!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        zIndexInt: 2,
      ),
    );
  }

  return markers;
}

/// 기기의 현재 위치와 방향을 나타내는 마커. 위치를 아직 모르면 null.
///
/// [heading]만큼 회전하고, [icon]이 아직 없으면(아이콘 로딩 전) 기본 파란 마커로
/// 임시 표시한다. 장소 마커보다 위에 그린다.
Marker? currentLocationMarker({
  required LatLng? position,
  required double heading,
  required BitmapDescriptor? icon,
}) {
  if (position == null) {
    return null;
  }

  return Marker(
    markerId: const MarkerId('current_user_location'),
    position: position,

    // Compass 방향에 따라 마커 회전
    rotation: heading,

    // 아이콘 중심을 실제 위치와 맞춤
    anchor: const Offset(0.5, 0.5),

    // 지도 위에 평평하게 배치하여 방향 회전을 자연스럽게 표시함.
    flat: true,
    icon:
        icon ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    zIndexInt: 9999,
  );
}
