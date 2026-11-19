import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/place_model.dart';

/// 장소 이름이 비었을 때 쓰는 이름. 서버 응답의 기본값([PlaceModel.fromJson])과 같다.
const String unnamedPlaceName = '이름 없는 장소';

/// 지도에서 누른 장소 아이콘(POI)을 장소 카드에 쓸 [PlaceModel]로 바꾼다.
///
/// 지도 SDK는 장소 ID·이름·좌표만 주므로 주소·분류는 비워 두고(카드가 숨긴다),
/// 평점·영업 여부는 카드의 "평점·영업 정보" 버튼으로 조회한다. SDK 이름에는 줄바꿈이
/// 들어 있을 수 있어 한 줄로 합친다.
PlaceModel placeFromPointOfInterest(TappedPointOfInterest pointOfInterest) {
  final name = pointOfInterest.name.replaceAll(RegExp(r'\s+'), ' ').trim();

  return PlaceModel(
    id: pointOfInterest.placeId.value,
    name: name.isEmpty ? unnamedPlaceName : name,
    latitude: pointOfInterest.position.latitude,
    longitude: pointOfInterest.position.longitude,
    address: '',
    rating: null,
    category: '',
    openNow: null,
  );
}
