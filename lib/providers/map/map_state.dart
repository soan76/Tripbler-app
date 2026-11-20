/// @docImport 'map_provider.dart';
library;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/place_model.dart';
import '../../utils/map/place_bounds.dart';
import '../../utils/map/place_markers.dart';
import 'place_details_cache.dart';

/// 장소 검색 진행 상태.
enum MapSearchStatus { idle, loading, success, failure }

/// 화면 문구를 고르기 위한 검색 실패 종류.
enum MapSearchErrorType {
  /// 400: 검색어·좌표가 서버 기준에 맞지 않음
  invalidQuery,

  /// 503: Google 장소 서비스 장애
  providerUnavailable,

  /// 시간 초과, 연결 실패
  network,

  /// 그 밖의 실패
  unknown,
}

class MapSearchError {
  const MapSearchError({required this.type, required this.message});

  final MapSearchErrorType type;
  final String message;
}

/// 선택한 장소의 상세 정보(평점·영업 여부) 조회 상태.
enum PlaceDetailsStatus { idle, loading, failure }

/// 지도 화면이 보여 주는 값. [MapNotifier]가 알릴 때마다 새로 만든다.
class MapState {
  const MapState({
    this.searchStatus = MapSearchStatus.idle,
    this.searchResults = const [],
    this.searchResultsOrigin,
    this.searchError,
    this.lastSearchQuery,
    this.canRetrySearch = false,
    this.hasSessionExpiryNotice = false,
    this.detailsStatus = PlaceDetailsStatus.idle,
    this.detailsErrorMessage,
    this.selectedPlaceDetailsFetchedAt,
    this.selectedPlace,
    this.selectedPlaceDistanceOrigin,
    this.isSelectedPlaceFromMap = false,
    required this.clock,
    required this.onSearchResultMarkerTap,
  });

  final MapSearchStatus searchStatus;

  /// 검색 결과. 검색할 때 기기 위치를 알았으면 가까운 순, 몰랐으면 서버가 준 순서다.
  final List<PlaceModel> searchResults;

  /// 지금 결과를 정렬한 기기 위치. 결과의 거리 표시도 이 위치를 기준으로 한다.
  /// 검색할 때 위치를 몰랐으면 null이다.
  final LatLng? searchResultsOrigin;
  final MapSearchError? searchError;
  final String? lastSearchQuery;

  /// 마지막으로 실패한 검색이 있어 [MapNotifier.retrySearch]를 쓸 수 있는지.
  final bool canRetrySearch;

  /// 표시를 기다리는 세션 만료 안내가 있는지. 지도 탭이 활성일 때만 표시하고
  /// [MapNotifier.consumeSessionExpiryNotice]로 소비한다.
  final bool hasSessionExpiryNotice;

  final PlaceDetailsStatus detailsStatus;
  final String? detailsErrorMessage;

  /// 선택한 장소의 상세 결과를 받은 시각(기기 현지 시간). 지금 열린 카드에서 버튼을
  /// 누르기 전이거나 받은 적이 없으면 null.
  final DateTime? selectedPlaceDetailsFetchedAt;

  final PlaceModel? selectedPlace;

  /// 선택한 장소의 거리 기준(기기 위치). 검색 결과는 검색할 때의 위치, 지도에서 고른
  /// 장소는 고른 순간의 위치다. 위치를 몰랐으면 null이다.
  final LatLng? selectedPlaceDistanceOrigin;

  /// 선택한 장소가 검색 결과가 아니라 지도의 장소 아이콘에서 고른 것인지.
  /// 이때는 검색 결과 마커가 없으므로 [markers]가 그 장소의 마커를 따로 만든다.
  final bool isSelectedPlaceFromMap;

  /// 만료 판단에 쓰는 현재 시각([MapNotifier.now]와 같은 시계).
  final DateTime Function() clock;

  /// 검색 결과 마커를 눌렀을 때([MapNotifier.selectSearchResult]).
  final void Function(PlaceModel place) onSearchResultMarkerTap;

  bool get isSearching => searchStatus == MapSearchStatus.loading;
  bool get hasSearchResults => searchResults.isNotEmpty;

  /// 지금 열린 카드에서 버튼을 눌렀고, 선택한 장소의 상세 결과를 받아 둔 적이
  /// 있는지(만료된 결과 포함). 카드를 새로 열면 버튼을 누르기 전까지 false다.
  ///
  /// 평점·영업 여부가 둘 다 없는 성공 응답도 받아 둔 것으로 본다. true면 카드가
  /// [selectedPlace]의 평점·영업 여부를 표시한다. 만료됐는지는
  /// [selectedPlaceDetailsStale]로 구분한다.
  bool get selectedPlaceDetailsLoaded => selectedPlaceDetailsFetchedAt != null;

  /// 선택한 장소의 상세 결과가 30분이 지나 오래된 정보인지. 읽는 순간의 [clock]으로
  /// 판단한다.
  ///
  /// 오래돼도 값은 지우지 않는다. 새로 고침하는 동안과 새로 고침이 실패했을 때도
  /// 마지막 성공값과 [selectedPlaceDetailsFetchedAt]을 그대로 보여준다.
  bool get selectedPlaceDetailsStale {
    final fetchedAt = selectedPlaceDetailsFetchedAt;
    return fetchedAt != null &&
        clock().difference(fetchedAt) >= PlaceDetailsCache.ttl;
  }

  MapState copyWith({
    MapSearchStatus? searchStatus,
    List<PlaceModel>? searchResults,
    LatLng? searchResultsOrigin,
    bool clearSearchResultsOrigin = false,
    MapSearchError? searchError,
    bool clearSearchError = false,
    String? lastSearchQuery,
    bool clearLastSearchQuery = false,
    bool? canRetrySearch,
    bool? hasSessionExpiryNotice,
    PlaceDetailsStatus? detailsStatus,
    String? detailsErrorMessage,
    bool clearDetailsErrorMessage = false,
    DateTime? selectedPlaceDetailsFetchedAt,
    bool clearSelectedPlaceDetailsFetchedAt = false,
    PlaceModel? selectedPlace,
    bool clearSelectedPlace = false,
    LatLng? selectedPlaceDistanceOrigin,
    bool? isSelectedPlaceFromMap,
  }) {
    return MapState(
      searchStatus: searchStatus ?? this.searchStatus,
      searchResults: searchResults == null
          ? this.searchResults
          : List.unmodifiable(searchResults),
      searchResultsOrigin: clearSearchResultsOrigin
          ? null
          : searchResultsOrigin ?? this.searchResultsOrigin,
      searchError: clearSearchError ? null : searchError ?? this.searchError,
      lastSearchQuery: clearLastSearchQuery
          ? null
          : lastSearchQuery ?? this.lastSearchQuery,
      canRetrySearch: canRetrySearch ?? this.canRetrySearch,
      hasSessionExpiryNotice:
          hasSessionExpiryNotice ?? this.hasSessionExpiryNotice,
      detailsStatus: detailsStatus ?? this.detailsStatus,
      detailsErrorMessage: clearDetailsErrorMessage
          ? null
          : detailsErrorMessage ?? this.detailsErrorMessage,
      selectedPlaceDetailsFetchedAt: clearSelectedPlaceDetailsFetchedAt
          ? null
          : selectedPlaceDetailsFetchedAt ?? this.selectedPlaceDetailsFetchedAt,
      selectedPlace: clearSelectedPlace
          ? null
          : selectedPlace ?? this.selectedPlace,
      // 선택을 지우면 선택에 딸린 거리 기준과 출처도 함께 지운다.
      selectedPlaceDistanceOrigin: clearSelectedPlace
          ? null
          : selectedPlaceDistanceOrigin ?? this.selectedPlaceDistanceOrigin,
      isSelectedPlaceFromMap: clearSelectedPlace
          ? false
          : isSelectedPlaceFromMap ?? this.isSelectedPlaceFromMap,
      clock: clock,
      onSearchResultMarkerTap: onSearchResultMarkerTap,
    );
  }

  /// 좌표가 있는 검색 결과를 모두 감싸는 범위. 카메라 이동은 화면이 맡는다.
  /// 결과가 하나면 남서·북동 꼭짓점이 같다. 날짜변경선·동률 규칙은 [placeBounds]를 따른다.
  LatLngBounds? get searchResultBounds => placeBounds(searchResults);

  // 검색 결과 마커. 선택한 장소는 색과 겹침 순서로 구분한다.
  Set<Marker> get markers => placeMarkers(
    searchResults: searchResults,
    selectedPlace: selectedPlace,
    isSelectedPlaceFromMap: isSelectedPlaceFromMap,
    onSearchResultTap: onSearchResultMarkerTap,
  );
}
