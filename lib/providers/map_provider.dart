import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/place_model.dart';
import 'auth/auth_provider.dart';
import '../repositories/auth/auth_repository.dart';
import '../services/place_api_service.dart';
import '../utils/map/place_distance.dart';
import '../utils/map/search_query_normalizer.dart';

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

/// 상세 캐시 항목. 저장 시각으로 만료 여부를 판단한다.
class _CachedPlaceDetails {
  const _CachedPlaceDetails({required this.place, required this.storedAt});

  final PlaceModel place;
  final DateTime storedAt;
}

/// 검색 요청 조건. 정리된 검색어와 실제로 보낸 중심 좌표가 모두 같아야 같은 조건이다.
///
/// [origin]은 결과를 거리순으로 정렬할 기기 위치다. 서버에 보내지 않으므로 같은 조건
/// 판단에는 쓰지 않는다(다시 시도는 처음 검색할 때의 위치를 그대로 쓴다).
@immutable
class _SearchRequest {
  const _SearchRequest({required this.query, this.center, this.origin});

  final String query;
  final LatLng? center;
  final LatLng? origin;

  @override
  bool operator ==(Object other) =>
      other is _SearchRequest && other.query == query && other.center == center;

  @override
  int get hashCode => Object.hash(query, center);
}

/// 장소 검색·상세 조회 서버 API.
final placeApiServiceProvider = Provider<PlaceApiService>((ref) {
  final service = PlaceApiService();
  ref.onDispose(service.dispose);
  return service;
});

/// 상세 캐시 만료 판단에 쓰는 현재 시각. 테스트에서 바꾼다.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

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
        clock().difference(fetchedAt) >= MapNotifier.placeDetailsCacheTtl;
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
  /// 결과가 하나면 남서·북동 꼭짓점이 같다.
  ///
  /// 경도는 모든 좌표를 담는 가장 짧은 구간을 고른다. 정렬한 경도 사이 간격
  /// (마지막과 첫째 사이는 360을 더한 순환 간격) 중 가장 큰 간격의 반대쪽이 범위다.
  /// 날짜변경선을 넘는 범위는 west > east로 만든다(예: west 179.9, east -179.9).
  /// 가장 큰 간격이 여럿이면 날짜변경선을 넘지 않는 순환 간격을 먼저 고르고,
  /// 그다음은 서쪽(작은 경도)에 있는 간격을 고른다. 예: -90과 90이면 west -90, east 90.
  LatLngBounds? get searchResultBounds {
    double? south;
    double? north;
    final longitudes = <double>[];

    for (final place in searchResults) {
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

  // 검색 결과 마커. 선택한 장소는 색과 겹침 순서로 구분한다.
  Set<Marker> get markers {
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
            onSearchResultMarkerTap(place);
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
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          zIndexInt: 2,
        ),
      );
    }

    return markers;
  }
}

/// 지도 화면에서 장소 검색, 선택한 장소, 상세 조회를 관리한다.
///
/// 검색·상세 요청은 [authorizedRequestRunnerProvider]로 토큰과 함께 실행한다.
/// 로그인 세션이 바뀌면([AuthState.sessionId]) 검색 결과·선택·상세 캐시를 비운다.
///
/// 작업 중인 값은 이 Notifier의 필드에 두고, 알릴 때마다 [MapState]를 새로 만든다.
class MapNotifier extends Notifier<MapState> {
  /// 상세 결과를 기억해 두는 최대 장소 수. 넘으면 가장 오래 안 쓴 것부터 지운다.
  static const int maxCachedPlaceDetails = 50;

  /// 상세 결과(영업 여부 등)를 재사용하는 시간. 지나면 다시 조회한다.
  static const Duration placeDetailsCacheTtl = Duration(minutes: 30);

  late AuthorizedRequestRunner _authorizedRequest;
  late PlaceApiService _placeApiService;
  late DateTime Function() _now;

  @override
  MapState build() {
    _authorizedRequest = ref.read(authorizedRequestRunnerProvider);
    _placeApiService = ref.read(placeApiServiceProvider);
    _now = ref.read(clockProvider);

    // 화면 밖에서 구독이 멈추면 중간 전이(로그아웃→재로그인)가 마지막 값 하나로
    // 합쳐질 수 있다. 그래서 로그인 여부만이 아니라 세션 번호가 바뀌었는지를 본다.
    ref.listen(
      authProvider.select((auth) => (auth.sessionId, auth.isAuthenticated)),
      _onAuthChanged,
    );

    ref.onDispose(() {
      _detailsDisplayTimer?.cancel();
      _detailsDisplayTimer = null;
    });

    return _snapshot();
  }

  // ----- 장소 검색 상태 -----
  MapSearchStatus _searchStatus = MapSearchStatus.idle;
  List<PlaceModel> _searchResults = const [];
  MapSearchError? _searchError;
  String? _lastSearchQuery;

  /// 지금 화면에 있는 검색 결과의 조건.
  _SearchRequest? _resultsRequest;

  /// 마지막으로 실패한 검색 요청. [retrySearch]가 같은 조건으로 다시 보낸다.
  _SearchRequest? _lastFailedRequest;

  /// 가장 최근 검색 요청 번호. 이보다 앞선 요청의 응답은 버린다.
  int _searchRequestId = 0;

  /// 가장 최근에 보낸 검색 조건. [_searchRequestId]가 아직 진행 중일 때만 중복 판단에 쓴다.
  _SearchRequest? _currentSearchRequest;

  // ----- 세션 만료 안내 -----
  // 사용자 검색에서 만료가 확정됐을 때만, 만료된 세션당 한 번 안내한다.
  // 검색 중 만료되면 AuthNotifier가 로그인 상태를 먼저 해제하고 그 알림으로 검색 상태가
  // 비워진 뒤에 만료 예외가 도착한다. 그래서 로그인이 풀린 순간 진행 중이던 검색 요청을
  // 따로 기억해 두고, 그 요청이 만료로 끝나면 안내한다.

  /// 응답을 기다리는 검색 요청 번호들(최신이 아닌 요청 포함).
  final Set<int> _inFlightSearchIds = <int>{};

  /// 로그인이 풀린 순간 진행 중이던 검색 요청 번호들.
  final Set<int> _signedOutSearchIds = <int>{};

  /// 이미 안내했거나 안내를 기다리는 만료 세션 번호들.
  final Set<int> _noticedExpiredSessionIds = <int>{};

  bool _hasSessionExpiryNotice = false;

  /// 기다리는 만료 안내를 띄울 때의 세션 번호. 그 뒤 세션이 또 바뀌면(다시 로그인,
  /// 로그아웃 등) 안내는 지난 일이라 표시하지 않는다.
  int? _noticeSessionId;

  // ----- 상세 조회 상태 -----
  PlaceDetailsStatus _detailsStatus = PlaceDetailsStatus.idle;
  String? _detailsErrorMessage;
  int _detailsRequestId = 0;
  final LinkedHashMap<String, _CachedPlaceDetails> _detailsCache =
      LinkedHashMap<String, _CachedPlaceDetails>();

  // 선택한 장소의 상세 표시가 바뀌는 순간(만료, 오래된 정보의 날짜 표시가 바뀌는
  // 자정) 화면에 알리는 타이머
  Timer? _detailsDisplayTimer;

  // 지금 열린 카드에서 사용자가 "평점·영업 정보"를 누른 장소 id. 카드를 새로 열 때
  // (닫기, 다른 장소 선택) 비워, 받아 둔 결과가 있어도 버튼부터 다시 보이게 한다.
  String? _detailsRevealedPlaceId;

  /// 이 Notifier가 만료 판단에 쓰는 현재 시각. 카드의 날짜 표시도 같은 시계를 쓴다.
  DateTime now() => _now();

  /// 지금 열린 카드에 보여줄 상세 결과. 이 카드에서 버튼을 누르기 전이면 받아 둔
  /// 결과가 있어도 null이다.
  _CachedPlaceDetails? get _selectedCacheEntry {
    final selectedId = _selectedPlace?.id;

    if (selectedId == null || selectedId != _detailsRevealedPlaceId) {
      return null;
    }

    return _detailsCache[selectedId];
  }

  PlaceModel? _selectedPlace;

  /// 지도의 장소 아이콘에서 고른 장소의 거리 기준(고른 순간의 기기 위치).
  LatLng? _mapPlaceOrigin;

  /// 선택한 장소를 지도의 장소 아이콘에서 골랐는지.
  bool _isSelectedPlaceFromMap = false;

  /// 지금 값으로 화면에 줄 상태를 만든다.
  MapState _snapshot() {
    return MapState(
      searchStatus: _searchStatus,
      searchResults: List.unmodifiable(_searchResults),
      searchResultsOrigin: _resultsRequest?.origin,
      searchError: _searchError,
      lastSearchQuery: _lastSearchQuery,
      canRetrySearch: _lastFailedRequest != null,
      hasSessionExpiryNotice: _hasSessionExpiryNotice,
      detailsStatus: _detailsStatus,
      detailsErrorMessage: _detailsErrorMessage,
      selectedPlaceDetailsFetchedAt: _selectedCacheEntry?.storedAt,
      selectedPlace: _selectedPlace,
      selectedPlaceDistanceOrigin: _selectedPlace == null
          ? null
          : _isSelectedPlaceFromMap
          ? _mapPlaceOrigin
          : _resultsRequest?.origin,
      isSelectedPlaceFromMap: _selectedPlace != null && _isSelectedPlaceFromMap,
      clock: _now,
      onSearchResultMarkerTap: selectSearchResult,
    );
  }

  // ----- 장소 검색 -----

  /// 검색어로 장소를 검색한다.
  ///
  /// [center]는 검색 버튼을 누른 순간의 지도 중심이다. 없으면 좌표 없이 검색한다.
  /// [userLocation]은 그 순간의 기기 위치다. 있으면 결과를 가까운 순으로 정렬한다.
  /// 검색어를 정리한 뒤 비었거나 100자를 넘으면 서버를 호출하지 않는다.
  /// 새 검색은 기존 선택과 상세 카드를 해제한다.
  Future<void> search(
    String query, {
    LatLng? center,
    LatLng? userLocation,
  }) async {
    final normalizedQuery = SearchQueryNormalizer.normalize(query);

    if (normalizedQuery == null) {
      return;
    }

    // 장소 검색은 로그인이 필요하다. 비로그인·세션 복구 대기 안내는 화면이 맡는다.
    if (!_isSignedIn) {
      return;
    }

    await _runSearch(
      _SearchRequest(
        query: normalizedQuery,
        center: center,
        origin: userLocation,
      ),
    );
  }

  /// 마지막으로 실패한 검색을 같은 조건으로 다시 보낸다.
  Future<void> retrySearch() async {
    final request = _lastFailedRequest;

    if (request == null || !_isSignedIn) {
      return;
    }

    await _runSearch(request);
  }

  Future<void> _runSearch(_SearchRequest request) async {
    // 같은 검색어·같은 지도 중심의 최신 검색이 아직 진행 중이면 다시 보내지 않는다
    // (버튼 연타 등으로 같은 Google 호출이 반복되지 않게). 다른 검색은 그대로 보낸다.
    if (_currentSearchRequest == request &&
        _inFlightSearchIds.contains(_searchRequestId)) {
      return;
    }

    final requestId = ++_searchRequestId;
    _currentSearchRequest = request;

    _lastSearchQuery = request.query;
    _searchStatus = MapSearchStatus.loading;
    _searchError = null;
    _clearSelectionState();
    _inFlightSearchIds.add(requestId);
    _notify();

    try {
      final places = await _authorizedRequest<List<PlaceModel>>(
        (authorizationHeader) => _placeApiService.searchPlaces(
          query: request.query,
          latitude: request.center?.latitude,
          longitude: request.center?.longitude,
          authorizationHeader: authorizationHeader,
        ),
      );

      if (!_isCurrentSearch(requestId)) {
        return;
      }

      _searchResults = PlaceDistance.sortByDistance(places, request.origin);
      _resultsRequest = request;
      _lastFailedRequest = null;
      _searchStatus = MapSearchStatus.success;
      _notify();
    } on SessionExpiredException catch (error) {
      // 이 검색이 만료를 확정했다: 로그인이 풀리기 전에 시작된 최신 검색이었거나,
      // 로그인이 풀린 순간 진행 중이던 검색이다(최신이 아니어도 같은 세션의 사용자 검색).
      final confirmedBySearch =
          _isCurrentSearch(requestId) ||
          _signedOutSearchIds.contains(requestId);

      if (ref.mounted && confirmedBySearch) {
        _raiseSessionExpiryNotice(error.sessionId);
      }

      if (!_isCurrentSearch(requestId)) {
        return;
      }

      // 로그인 상태는 AuthNotifier가 해제한다(앱은 비로그인으로도 쓸 수 있어 화면은 그대로).
      _resetSearchState();
      _notify();
    } on SessionChangedException {
      // 이전 세션에서 시작한 검색: 결과를 반영하지 않는다.
      // 보통은 로그인 해제 알림으로 이미 요청 번호가 바뀌어 여기까지 오지 않는다.
      if (!_isCurrentSearch(requestId)) {
        return;
      }

      // 화면에 있던 결과와 오류 문구는 그대로 두고 로딩 표시만 거둔다.
      _searchStatus = _resultsRequest != null
          ? MapSearchStatus.success
          : MapSearchStatus.idle;
      _notify();
    } catch (error) {
      if (!_isCurrentSearch(requestId)) {
        return;
      }

      _lastFailedRequest = request;

      // 같은 조건(다시 시도 등)이면 화면의 결과를 유지하고, 조건이 다르면 비운다.
      if (_resultsRequest != request) {
        _searchResults = const [];
        _resultsRequest = null;
      }

      _searchError = _toSearchError(error);
      _searchStatus = MapSearchStatus.failure;
      _notify();
    } finally {
      _inFlightSearchIds.remove(requestId);
      _signedOutSearchIds.remove(requestId);
    }
  }

  /// 지금 로그인돼 있는지. 화면 밖에서 구독이 멈춰 있어도 현재 값을 읽는다.
  bool get _isSignedIn => ref.read(authProvider).isAuthenticated;

  /// 만료된 세션의 안내를 한 번만 대기시킨다.
  /// 이미 다시 로그인했다면(이전 세션의 늦은 예외) 새 화면에 띄우지 않는다.
  void _raiseSessionExpiryNotice(int? sessionId) {
    if (_isSignedIn) {
      return;
    }

    if (sessionId != null && !_noticedExpiredSessionIds.add(sessionId)) {
      return;
    }

    if (_hasSessionExpiryNotice) {
      return;
    }

    _hasSessionExpiryNotice = true;
    _noticeSessionId = ref.read(authProvider).sessionId;
    _notify();
  }

  /// 화면이 세션 만료 안내를 표시했음을 알린다(지도 탭이 활성일 때만 부른다).
  void consumeSessionExpiryNotice() {
    if (!_hasSessionExpiryNotice) {
      return;
    }

    _hasSessionExpiryNotice = false;
    _notify();
  }

  bool _isCurrentSearch(int requestId) {
    return ref.mounted && requestId == _searchRequestId;
  }

  MapSearchError _toSearchError(Object error) {
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

  /// 검색 결과 목록이나 마커에서 장소를 고른다. 상세 카드에 표시된다.
  void selectSearchResult(PlaceModel place) {
    if (_selectedPlace?.id == place.id && !_isSelectedPlaceFromMap) {
      return;
    }

    _selectPlace(place, fromMap: false);
  }

  /// 지도의 장소 아이콘(POI)을 눌렀을 때. [place]는 지도 SDK가 준 장소 ID·이름·좌표만
  /// 가진다(주소·분류는 비어 있다). 탭 자체로는 서버를 호출하지 않는다.
  ///
  /// 같은 장소가 검색 결과에 있으면 그 결과를 고른 것으로 본다(검색 결과의 이름·주소·
  /// 분류와 검색할 때의 거리 기준을 쓴다). 없으면 [userLocation](고른 순간의 기기
  /// 위치)을 거리 기준으로 카드를 연다. 검색 결과 목록은 그대로 둔다.
  void selectMapPlace(PlaceModel place, {LatLng? userLocation}) {
    for (final result in _searchResults) {
      if (result.id == place.id) {
        selectSearchResult(result);
        return;
      }
    }

    if (_selectedPlace?.id == place.id && _isSelectedPlaceFromMap) {
      return;
    }

    _mapPlaceOrigin = userLocation;
    _selectPlace(place, fromMap: true);
  }

  void _selectPlace(PlaceModel place, {required bool fromMap}) {
    _isSelectedPlaceFromMap = fromMap;

    if (!fromMap) {
      _mapPlaceOrigin = null;
    }

    // 받아 둔 상세 결과로 장소 값과 같은 id의 결과 목록 항목을 함께 맞춰 두되,
    // 카드는 버튼부터 보인다.
    _selectedPlace = place;
    _applyCachedDetails(place.id);
    _detailsRevealedPlaceId = null;
    _resetDetailsState();
    _notify();
  }

  /// 검색어, 결과, 선택, 진행 중인 검색을 모두 지운다(검색창 X 버튼).
  void clearSearch() {
    _resetSearchState();
    _clearSelectionState();
    _notify();
  }

  void _resetSearchState() {
    // 진행 중인 요청의 응답은 번호가 달라져 버려진다.
    _searchRequestId++;
    _searchStatus = MapSearchStatus.idle;
    _searchResults = const [];
    _searchError = null;
    _lastSearchQuery = null;
    _resultsRequest = null;
    _lastFailedRequest = null;
  }

  /// 로그인 세션이나 로그인 여부가 바뀌었을 때.
  ///
  /// 지도 화면이 다른 탭에 있어 구독이 멈춘 동안 로그아웃→재로그인이 일어나면
  /// 두 전이가 하나로 합쳐져 도착할 수 있다. 세션 번호가 다르면 그 사이에
  /// 로그아웃이 있었던 것이므로 이전 세션의 값을 비운다.
  void _onAuthChanged((int, bool)? previous, (int, bool) next) {
    final (sessionId, isAuthenticated) = next;

    if (previous != null && previous.$1 != sessionId) {
      _onSessionChanged();
    }

    // 새로 로그인했거나, 안내를 기다리는 동안 세션이 또 바뀌었다: 아직 표시하지 않은
    // 이전 세션의 만료 안내는 무효다.
    if (_hasSessionExpiryNotice &&
        (isAuthenticated || sessionId != _noticeSessionId)) {
      _hasSessionExpiryNotice = false;
      _notify();
    }
  }

  void _onSessionChanged() {
    // 세션이 바뀐 순간 진행 중이던 검색: 만료로 끝나면 사용자 검색이 만료를 확정한 것이다.
    _signedOutSearchIds.addAll(_inFlightSearchIds);

    // 로그아웃·세션 만료: 다음 사용자에게 이전 검색과 상세 결과가 남지 않게 비운다.
    final hadState =
        _searchStatus != MapSearchStatus.idle ||
        _selectedPlace != null ||
        _detailsCache.isNotEmpty;

    _resetSearchState();
    _clearSelectionState();
    _detailsCache.clear();

    if (hadState) {
      _notify();
    }
  }

  // ----- 선택과 상세 조회 -----

  // 선택한 장소의 상세 정보(평점·영업 여부)를 조회한다. 카드의 버튼을 눌렀을 때만 부른다.
  // 같은 장소를 다시 열면 기억해 둔 결과를 쓰고, 실패해도 검색 결과는 그대로 둔다.
  Future<void> loadSelectedPlaceDetails() async {
    final selectedPlace = _selectedPlace;

    // 이미 조회 중이면 같은 요청을 다시 보내지 않는다.
    if (selectedPlace == null || _detailsStatus == PlaceDetailsStatus.loading) {
      return;
    }

    // 이 카드에서 버튼을 눌렀다: 받아 둔 결과가 있으면 바로 보인다. 오래된 결과는
    // 새로 조회하는 동안 오래된 정보로 함께 보인다.
    _detailsRevealedPlaceId = selectedPlace.id;

    // 보이기 시작한 결과의 만료·자정 표시 변화에 맞춰 타이머를 다시 맞춘다.
    _syncDetailsDisplayTimer();

    final cachedPlace = _freshCachedDetails(selectedPlace.id);

    if (cachedPlace != null) {
      _markCachedDetailsUsed(selectedPlace.id);
      _applyPlaceDetails(cachedPlace);
      _resetDetailsState();
      _notify();
      return;
    }

    // 상세 조회는 로그인이 필요하다. 로그인이 풀렸으면 보내지 않는다(안내는 화면이 맡는다).
    if (!_isSignedIn) {
      return;
    }

    final requestId = ++_detailsRequestId;

    _detailsStatus = PlaceDetailsStatus.loading;
    _detailsErrorMessage = null;
    _notify();

    try {
      final detailPlace = await _authorizedRequest<PlaceModel>(
        (authorizationHeader) => _placeApiService.fetchPlaceDetails(
          placeId: selectedPlace.id,
          authorizationHeader: authorizationHeader,
        ),
      );

      if (!_isCurrentDetails(requestId, selectedPlace.id)) {
        return;
      }

      // 새 응답의 값이 비어 있으면 이전 값도 지운다("정보 없음"으로 바뀜).
      _cachePlaceDetails(detailPlace);
      _applyPlaceDetails(detailPlace);
      _detailsStatus = PlaceDetailsStatus.idle;
      _syncDetailsDisplayTimer();
      _notify();
    } on SessionExpiredException catch (error) {
      // 재발급까지 실패해 세션이 끝났다. 로그인 해제는 AuthNotifier가 했다.
      if (ref.mounted) {
        _raiseSessionExpiryNotice(error.sessionId);
      }

      if (!_isCurrentDetails(requestId, selectedPlace.id)) {
        return;
      }

      _resetDetailsState();
      _notify();
    } on SessionChangedException {
      // 이전 세션에서 시작한 조회: 결과를 반영하지 않고 로딩만 거둔다.
      if (!_isCurrentDetails(requestId, selectedPlace.id)) {
        return;
      }

      _resetDetailsState();
      _notify();
    } catch (error, stackTrace) {
      // 429, 네트워크 오류, 5xx, 재발급 뒤 다시 받은 401 등: 로그인은 유지하고 카드에 실패를 보인다.
      debugPrint('장소 상세 조회 실패: $error');
      debugPrint('$stackTrace');

      if (!_isCurrentDetails(requestId, selectedPlace.id)) {
        return;
      }

      _detailsStatus = PlaceDetailsStatus.failure;
      _detailsErrorMessage = error is ApiException
          ? error.message
          : '장소 상세 정보를 불러오지 못했습니다.';
      _notify();
    }
  }

  bool _isCurrentDetails(int requestId, String placeId) {
    return ref.mounted &&
        requestId == _detailsRequestId &&
        _selectedPlace?.id == placeId;
  }

  /// 만료되지 않은 상세 결과만 돌려준다. 만료된 항목은 다시 조회해 갱신한다.
  PlaceModel? _freshCachedDetails(String placeId) {
    final entry = _detailsCache[placeId];

    if (entry == null) {
      return null;
    }

    if (_isExpired(entry)) {
      return null;
    }

    return entry.place;
  }

  bool _isExpired(_CachedPlaceDetails entry) {
    return _now().difference(entry.storedAt) >= placeDetailsCacheTtl;
  }

  /// 선택한 장소의 상세 표시가 다음에 바뀌는 순간 화면에 알리도록 타이머를 맞춘다.
  ///
  /// - 아직 유효하면 원래 만료 시각(받은 시각 + 30분)에 알린다.
  /// - 오래된 정보이고 받은 날이 오늘이면 다음 현지 자정에 알린다. 자정이 지나면
  ///   "22:00 기준"이 "11월 10일 22:00 기준"으로 바뀌어야 하기 때문이다. 날짜가
  ///   이미 붙었으면 더 바뀌지 않으므로 타이머를 두지 않는다.
  ///
  /// 선택이 바뀌거나 결과가 없으면 타이머를 끈다.
  void _syncDetailsDisplayTimer() {
    _detailsDisplayTimer?.cancel();
    _detailsDisplayTimer = null;

    final entry = _selectedCacheEntry;

    if (!ref.mounted || entry == null) {
      return;
    }

    final now = _now();
    final Duration delay;

    if (!_isExpired(entry)) {
      delay = entry.storedAt.add(placeDetailsCacheTtl).difference(now);
    } else {
      final fetched = entry.storedAt.toLocal();
      final today = now.toLocal();
      final fetchedToday =
          fetched.year == today.year &&
          fetched.month == today.month &&
          fetched.day == today.day;

      if (!fetchedToday) {
        return;
      }

      delay = DateTime(
        today.year,
        today.month,
        today.day + 1,
      ).difference(today);
    }

    _detailsDisplayTimer = Timer(delay, () {
      _detailsDisplayTimer = null;

      if (!ref.mounted) {
        return;
      }

      // 다음 변화 시점으로 다시 맞춘다(기기 시계가 어긋나 아직 그 시점 전이어도 안전).
      _syncDetailsDisplayTimer();
      _notify();
    });
  }

  void _cachePlaceDetails(PlaceModel place) {
    _detailsCache.remove(place.id);
    _detailsCache[place.id] = _CachedPlaceDetails(
      place: place,
      storedAt: _now(),
    );

    while (_detailsCache.length > maxCachedPlaceDetails) {
      _detailsCache.remove(_detailsCache.keys.first);
    }
  }

  /// 받아 둔 상세 결과를 썼다: 맨 뒤로 옮겨 상한을 넘을 때 가장 오래 안 쓴 것부터
  /// 지워지게 한다. 저장 시각(만료 판단 기준)은 그대로 둔다.
  void _markCachedDetailsUsed(String placeId) {
    final entry = _detailsCache.remove(placeId);

    if (entry != null) {
      _detailsCache[placeId] = entry;
    }
  }

  // 상세 결과로 선택한 장소와, 같은 id의 검색 결과 항목을 함께 갱신한다.
  //
  // 상세 조회는 평점·영업 여부만 쓴다. 이름·주소·분류·좌표는 검색 결과 값을 그대로
  // 둔다(상세 응답은 언어 설정이 달라 이름·주소가 영어로 올 수 있다).
  void _applyPlaceDetails(PlaceModel detailPlace) {
    PlaceModel replace(PlaceModel place) =>
        place.id == detailPlace.id ? _withDetails(place, detailPlace) : place;

    final selectedPlace = _selectedPlace;

    if (selectedPlace != null) {
      _selectedPlace = replace(selectedPlace);
    }

    _searchResults = _searchResults.map(replace).toList();
  }

  /// [place]에 상세 결과의 평점·영업 여부만 덮는다. 상세 값이 null이면 null로 바꾼다
  /// ("정보 없음"으로 표시).
  static PlaceModel _withDetails(PlaceModel place, PlaceModel details) {
    return PlaceModel(
      id: place.id,
      name: place.name,
      latitude: place.latitude,
      longitude: place.longitude,
      address: place.address,
      rating: details.rating,
      category: place.category,
      openNow: details.openNow,
    );
  }

  /// 받아 둔 상세 결과가 있으면 선택한 장소와 같은 id의 결과 목록 항목에 평점·영업
  /// 여부를 함께 반영한다. 한쪽만 바꾸면 카드와 목록 값이 어긋날 수 있다.
  void _applyCachedDetails(String placeId) {
    final cached = _detailsCache[placeId]?.place;

    if (cached == null) {
      return;
    }

    _markCachedDetailsUsed(placeId);
    _applyPlaceDetails(cached);
  }

  void _resetDetailsState() {
    // 진행 중인 상세 조회의 응답은 번호가 달라져 버려진다.
    _detailsRequestId++;
    _detailsStatus = PlaceDetailsStatus.idle;
    _detailsErrorMessage = null;
    _syncDetailsDisplayTimer();
  }

  /// 상세 카드만 닫는다. 검색 결과는 그대로 둔다.
  void clearSelectedPlace() {
    if (_selectedPlace == null) {
      return;
    }

    _clearSelectionState();
    _notify();
  }

  void _clearSelectionState() {
    _selectedPlace = null;
    _isSelectedPlaceFromMap = false;
    _mapPlaceOrigin = null;
    _detailsRevealedPlaceId = null;
    _resetDetailsState();
  }

  /// 지금 값으로 상태를 새로 내보낸다. 상태 객체가 폐기된 뒤에는 하지 않는다.
  void _notify() {
    if (ref.mounted) {
      state = _snapshot();
    }
  }
}

final mapProvider = NotifierProvider<MapNotifier, MapState>(MapNotifier.new);
