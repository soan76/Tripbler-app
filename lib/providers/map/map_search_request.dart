import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/network/api_exception.dart';
import 'map_state.dart';

/// 검색 요청 조건. 정리된 검색어와 실제로 보낸 중심 좌표가 모두 같아야 같은 조건이다.
///
/// [origin]은 결과를 거리순으로 정렬할 기기 위치다. 서버에 보내지 않으므로 같은 조건
/// 판단에는 쓰지 않는다(다시 시도는 처음 검색할 때의 위치를 그대로 쓴다).
@immutable
class MapSearchRequest {
  const MapSearchRequest({required this.query, this.center, this.origin});

  final String query;
  final LatLng? center;
  final LatLng? origin;

  @override
  bool operator ==(Object other) =>
      other is MapSearchRequest &&
      other.query == query &&
      other.center == center;

  @override
  int get hashCode => Object.hash(query, center);
}

/// 검색 실패를 화면 문구용 오류로 바꾼다.
MapSearchError toMapSearchError(Object error) {
  if (error is ApiException) {
    final MapSearchErrorType type;

    if (error.isNetworkError) {
      type = MapSearchErrorType.network;
    } else if (error.statusCode == 400) {
      type = MapSearchErrorType.invalidQuery;
    } else if (error.statusCode == 503) {
      type = MapSearchErrorType.providerUnavailable;
    } else {
      type = MapSearchErrorType.unknown;
    }

    return MapSearchError(type: type, message: error.message);
  }

  debugPrint('장소 검색 실패: $error');

  return const MapSearchError(
    type: MapSearchErrorType.unknown,
    message: '장소를 검색하지 못했습니다. 잠시 후 다시 시도해 주세요.',
  );
}
