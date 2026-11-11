import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/place_model.dart';
import '../providers/auth_provider.dart';
import '../repositories/auth/auth_repository.dart';
import '../services/place_api_service.dart';
import '../utils/map/search_query_normalizer.dart';

enum MapPlaceStatus { idle, loading, success, failure }

/// 장소 검색 진행 상태. 주변 장소·지도 탭용 [MapPlaceStatus]와 따로 관리한다.
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
@immutable
class _SearchRequest {
  const _SearchRequest({required this.query, this.center});

  final String query;
  final LatLng? center;

  @override
  bool operator ==(Object other) =>
      other is _SearchRequest && other.query == query && other.center == center;

  @override
  int get hashCode => Object.hash(query, center);
}

/// 지도 화면에서 주변 장소, 장소 검색, 선택한 장소를 관리하는 Provider 클래스
class MapProvider extends ChangeNotifier {
  /// [authorizedRequest]: 로그인이 필요한 검색 요청을 토큰과 함께 실행한다
  /// (보통 [AuthProvider.runAuthorizedRequest]).
  /// [authState]와 [isAuthenticated]를 주면 로그인이 풀릴 때 검색 상태를 비운다.
  /// [now]는 상세 캐시 만료 판단에 쓰는 현재 시각이다(테스트용, 기본 [DateTime.now]).
  MapProvider({
    required AuthorizedRequestRunner authorizedRequest,
    PlaceApiService? placeApiService,
    Listenable? authState,
    bool Function()? isAuthenticated,
    DateTime Function()? now,
  }) : _authorizedRequest = authorizedRequest,
       _placeApiService = placeApiService ?? PlaceApiService(),
       _authState = authState,
       _isAuthenticated = isAuthenticated,
       _now = now ?? DateTime.now {
    _authState?.addListener(_handleAuthStateChanged);
  }

  /// 상세 결과를 기억해 두는 최대 장소 수. 넘으면 오래된 것부터 지운다.
  static const int maxCachedPlaceDetails = 50;

  /// 상세 결과(영업 여부 등)를 재사용하는 시간. 지나면 다시 조회한다.
  static const Duration placeDetailsCacheTtl = Duration(minutes: 30);

  final AuthorizedRequestRunner _authorizedRequest;
  final PlaceApiService _placeApiService;
  final Listenable? _authState;
  final bool Function()? _isAuthenticated;
  final DateTime Function() _now;

  bool _isDisposed = false;

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

  // ----- 세션 만료 안내 -----
  // 사용자 검색에서 만료가 확정됐을 때만, 만료된 세션당 한 번 안내한다.
  // 검색 중 만료되면 AuthProvider가 로그인 상태를 먼저 해제하고 그 알림으로 검색 상태가
  // 비워진 뒤에 만료 예외가 도착한다. 그래서 로그인이 풀린 순간 진행 중이던 검색 요청을
  // 따로 기억해 두고, 그 요청이 만료로 끝나면 안내한다.

  /// 응답을 기다리는 검색 요청 번호들(최신이 아닌 요청 포함).
  final Set<int> _inFlightSearchIds = <int>{};

  /// 로그인이 풀린 순간 진행 중이던 검색 요청 번호들.
  final Set<int> _signedOutSearchIds = <int>{};

  /// 이미 안내했거나 안내를 기다리는 만료 세션 번호들.
  final Set<int> _noticedExpiredSessionIds = <int>{};

  bool _hasSessionExpiryNotice = false;

  // ----- 상세 조회 상태 -----
  PlaceDetailsStatus _detailsStatus = PlaceDetailsStatus.idle;
  String? _detailsErrorMessage;
  int _detailsRequestId = 0;
  final LinkedHashMap<String, _CachedPlaceDetails> _detailsCache =
      LinkedHashMap<String, _CachedPlaceDetails>();

  // 선택한 장소의 상세 결과가 만료되는 순간 화면에 알리는 타이머
  Timer? _detailsExpiryTimer;

  MapSearchStatus get searchStatus => _searchStatus;
  List<PlaceModel> get searchResults => List.unmodifiable(_searchResults);
  MapSearchError? get searchError => _searchError;
  String? get lastSearchQuery => _lastSearchQuery;
  bool get isSearching => _searchStatus == MapSearchStatus.loading;
  bool get hasSearchResults => _searchResults.isNotEmpty;
  bool get canRetrySearch => _lastFailedRequest != null;

  /// 표시를 기다리는 세션 만료 안내가 있는지. 지도 탭이 활성일 때만 표시하고
  /// [consumeSessionExpiryNotice]로 소비한다.
  bool get hasSessionExpiryNotice => _hasSessionExpiryNotice;

  PlaceDetailsStatus get detailsStatus => _detailsStatus;
  String? get detailsErrorMessage => _detailsErrorMessage;

  /// 선택한 장소의 상세 결과를 받아 둔 적이 있는지(만료된 결과 포함).
  ///
  /// 평점·영업 여부가 둘 다 없는 성공 응답도 받아 둔 것으로 본다. true면 카드가
  /// [selectedPlace]의 평점·영업 여부를 표시한다. 만료됐는지는
  /// [selectedPlaceDetailsStale]로 구분한다.
  bool get selectedPlaceDetailsLoaded => _selectedCacheEntry != null;

  /// 선택한 장소의 상세 결과가 30분이 지나 오래된 정보인지.
  ///
  /// 오래돼도 값은 지우지 않는다. 새로 고침하는 동안과 새로 고침이 실패했을 때도
  /// 마지막 성공값과 [selectedPlaceDetailsFetchedAt]을 그대로 보여준다.
  bool get selectedPlaceDetailsStale {
    final entry = _selectedCacheEntry;
    return entry != null && _isExpired(entry);
  }

  /// 선택한 장소의 상세 결과를 받은 시각(기기 현지 시간). 받은 적이 없으면 null.
  DateTime? get selectedPlaceDetailsFetchedAt => _selectedCacheEntry?.storedAt;

  _CachedPlaceDetails? get _selectedCacheEntry {
    final selectedId = _selectedPlace?.id;
    return selectedId == null ? null : _detailsCache[selectedId];
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

    for (final place in _searchResults) {
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

  MapPlaceStatus _status = MapPlaceStatus.idle;
  List<PlaceModel> _places = [];
  PlaceModel? _selectedPlace;
  String? _errorMessage;

  MapPlaceStatus get status => _status;
  List<PlaceModel> get places => List.unmodifiable(_places);
  PlaceModel? get selectedPlace => _selectedPlace;
  String? get errorMessage => _errorMessage;

  bool get isLoading => _status == MapPlaceStatus.loading;
  bool get hasPlaces => _places.isNotEmpty;

  // 주변 장소 마커 + 현재 선택한 장소 마커
  Set<Marker> get markers {
    final markers = <Marker>{};

    // Nearby API로 받아온 장소 마커
    for (final place in _places) {
      // 좌표가 없는 장소는 지도에 표시할 수 없으므로 건너뜀.
      // (place_model의 좌표 파싱 실패 시 더 이상 (0,0)으로 대체하지 않고
      // null을 반환하므로, 여기서 명시적으로 걸러줘야 함)
      if (!place.hasCoordinates) {
        continue;
      }

      markers.add(
        Marker(
          markerId: MarkerId(place.id),
          position: LatLng(place.latitude!, place.longitude!),
          infoWindow: InfoWindow(title: place.name, snippet: place.address),
          onTap: () {
            selectPlace(place);
          },
        ),
      );
    }

    // 검색 결과 마커. 탭하면 그 결과를 선택하고, 선택된 마커는 색과 겹침 순서로 구분한다.
    // 모양은 화면 디자인 단계에서 다듬는다.
    final selectedId = _selectedPlace?.id;

    for (final place in _searchResults) {
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
            selectSearchResult(place);
          },
        ),
      );
    }

    return markers;
  }

  Future<void> loadNearbyPlaces({
    required double latitude,
    required double longitude,
    String type = 'tourist_attraction',
    int radius = 1500,
  }) async {
    _status = MapPlaceStatus.loading;
    _errorMessage = null;
    _selectedPlace = null;
    _resetDetailsState();
    notifyListeners();

    try {
      final places = await _placeApiService.fetchNearbyPlaces(
        latitude: latitude,
        longitude: longitude,
        type: type,
        radius: radius,
      );

      _places = places;
      _status = MapPlaceStatus.success;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('주변 장소 불러오기 실패: $error');
      debugPrint('$stackTrace');

      _places = [];
      _selectedPlace = null;
      _resetDetailsState();
      _errorMessage = error.toString();
      _status = MapPlaceStatus.failure;
      notifyListeners();
    }
  }

  // ----- 장소 검색 -----

  /// 검색어로 장소를 검색한다.
  ///
  /// [center]는 검색 버튼을 누른 순간의 지도 중심이다. 없으면 좌표 없이 검색한다.
  /// 검색어를 정리한 뒤 비었거나 100자를 넘으면 서버를 호출하지 않는다.
  /// 새 검색은 기존 선택과 상세 카드를 해제한다.
  Future<void> search(String query, {LatLng? center}) async {
    final normalizedQuery = SearchQueryNormalizer.normalize(query);

    if (normalizedQuery == null) {
      return;
    }

    // 장소 검색은 로그인이 필요하다. 비로그인·세션 복구 대기 안내는 화면이 맡는다.
    if (!_isSignedIn) {
      return;
    }

    await _runSearch(_SearchRequest(query: normalizedQuery, center: center));
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
    final requestId = ++_searchRequestId;

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

      _searchResults = places;
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

      if (!_isDisposed && confirmedBySearch) {
        _raiseSessionExpiryNotice(error.sessionId);
      }

      if (!_isCurrentSearch(requestId)) {
        return;
      }

      // 로그인 상태는 AuthProvider가 해제한다(앱은 비로그인으로도 쓸 수 있어 화면은 그대로).
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

  bool get _isSignedIn => _isAuthenticated?.call() ?? true;

  /// 만료된 세션의 안내를 한 번만 대기시킨다.
  /// 이미 다시 로그인했다면(이전 세션의 늦은 예외) 새 화면에 띄우지 않는다.
  void _raiseSessionExpiryNotice(int? sessionId) {
    if (_isAuthenticated?.call() ?? false) {
      return;
    }

    if (sessionId != null && !_noticedExpiredSessionIds.add(sessionId)) {
      return;
    }

    if (_hasSessionExpiryNotice) {
      return;
    }

    _hasSessionExpiryNotice = true;
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
    return !_isDisposed && requestId == _searchRequestId;
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
    if (_selectedPlace?.id == place.id) {
      return;
    }

    // 받아 둔 상세 결과가 있으면 오래됐어도 그 값을 보여준다(오래된 정보로 표시).
    _selectedPlace = _detailsCache[place.id]?.place ?? place;
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

  void _handleAuthStateChanged() {
    final isAuthenticated = _isAuthenticated;

    if (isAuthenticated == null) {
      return;
    }

    if (isAuthenticated()) {
      // 새로 로그인했다: 아직 표시하지 않은 이전 세션의 만료 안내는 무효다.
      if (_hasSessionExpiryNotice) {
        _hasSessionExpiryNotice = false;
        _notify();
      }

      return;
    }

    // 로그인이 풀린 순간 진행 중이던 검색: 만료로 끝나면 사용자 검색이 만료를 확정한 것이다.
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

    final cachedPlace = _freshCachedDetails(selectedPlace.id);

    if (cachedPlace != null) {
      _applyPlaceDetails(cachedPlace);
      _resetDetailsState();
      _notify();
      return;
    }

    final requestId = ++_detailsRequestId;

    _detailsStatus = PlaceDetailsStatus.loading;
    _detailsErrorMessage = null;
    _notify();

    try {
      final detailPlace = await _placeApiService.fetchPlaceDetails(
        placeId: selectedPlace.id,
      );

      if (!_isCurrentDetails(requestId, selectedPlace.id)) {
        return;
      }

      // 새 응답의 값이 비어 있으면 이전 값도 지운다("정보 없음"으로 바뀜).
      _cachePlaceDetails(detailPlace);
      _applyPlaceDetails(detailPlace);
      _detailsStatus = PlaceDetailsStatus.idle;
      _syncDetailsExpiryTimer();
      _notify();
    } catch (error, stackTrace) {
      debugPrint('장소 상세 조회 실패: $error');
      debugPrint('$stackTrace');

      if (!_isCurrentDetails(requestId, selectedPlace.id)) {
        return;
      }

      _detailsStatus = PlaceDetailsStatus.failure;
      _detailsErrorMessage = error is PlaceApiException
          ? error.message
          : '장소 상세 정보를 불러오지 못했습니다.';
      _notify();
    }
  }

  bool _isCurrentDetails(int requestId, String placeId) {
    return !_isDisposed &&
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

  /// 선택한 장소의 상세 결과가 아직 유효하면, 원래 만료 시각(받은 시각 + 30분)에
  /// 화면에 알리도록 타이머를 맞춘다. 선택이 바뀌거나 결과가 없으면 타이머를 끈다.
  void _syncDetailsExpiryTimer() {
    _detailsExpiryTimer?.cancel();
    _detailsExpiryTimer = null;

    final entry = _selectedCacheEntry;

    if (_isDisposed || entry == null || _isExpired(entry)) {
      return;
    }

    final remaining = entry.storedAt
        .add(placeDetailsCacheTtl)
        .difference(_now());

    _detailsExpiryTimer = Timer(remaining, () {
      _detailsExpiryTimer = null;

      if (_isDisposed) {
        return;
      }

      // 기기 시계와 타이머가 어긋나 아직 유효하면 남은 시간만큼 다시 맞춘다.
      _syncDetailsExpiryTimer();
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

  // 상세 결과로 선택한 장소와, 같은 id의 주변 장소·검색 결과 항목을 함께 갱신한다.
  void _applyPlaceDetails(PlaceModel detailPlace) {
    _selectedPlace = detailPlace;

    PlaceModel replace(PlaceModel place) =>
        place.id == detailPlace.id ? detailPlace : place;

    _places = _places.map(replace).toList();
    _searchResults = _searchResults.map(replace).toList();
  }

  void _resetDetailsState() {
    // 진행 중인 상세 조회의 응답은 번호가 달라져 버려진다.
    _detailsRequestId++;
    _detailsStatus = PlaceDetailsStatus.idle;
    _detailsErrorMessage = null;
    _syncDetailsExpiryTimer();
  }

  void selectPlace(PlaceModel place) {
    // 받아 둔 상세 결과가 있으면 그 값을 쓴다(조회 완료 표시와 값이 어긋나지 않게).
    _selectedPlace = _detailsCache[place.id]?.place ?? place;
    _resetDetailsState();
    notifyListeners();
  }

  /// 상세 카드만 닫는다. 검색 결과는 그대로 둔다.
  void clearSelectedPlace() {
    if (_selectedPlace == null) {
      return;
    }

    _clearSelectionState();
    notifyListeners();
  }

  void _clearSelectionState() {
    _selectedPlace = null;
    _resetDetailsState();
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;

    if (_status == MapPlaceStatus.failure) {
      _status = MapPlaceStatus.idle;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _detailsExpiryTimer?.cancel();
    _detailsExpiryTimer = null;
    _authState?.removeListener(_handleAuthStateChanged);
    _placeApiService.dispose();
    super.dispose();
  }
}
