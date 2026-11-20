import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/network/api_exception.dart';
import '../../models/place_model.dart';
import '../../repositories/auth/auth_repository.dart';
import '../../services/place_api_service.dart';
import '../../utils/map/place_distance.dart';
import '../../utils/map/search_query_normalizer.dart';
import '../auth/auth_provider.dart';
import 'map_search_request.dart';
import 'map_state.dart';
import 'place_details_cache.dart';
import 'session_expiry_notice.dart';

export 'map_state.dart';

/// 장소 검색·상세 조회 서버 API.
final placeApiServiceProvider = Provider<PlaceApiService>((ref) {
  final service = PlaceApiService();
  ref.onDispose(service.dispose);
  return service;
});

/// 상세 캐시 만료 판단에 쓰는 현재 시각. 테스트에서 바꾼다.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// 지도 화면에서 장소 검색, 선택한 장소, 상세 조회를 관리한다.
///
/// 검색·상세 요청은 [authorizedRequestRunnerProvider]로 토큰과 함께 실행한다.
/// 로그인 세션이 바뀌면([AuthState.sessionId]) 검색 결과·선택·상세 캐시를 비운다.
///
/// 작업 중인 값은 이 Notifier의 필드에 두고, 알릴 때마다 [MapState]를 새로 만든다.
class MapNotifier extends Notifier<MapState> {
  /// 상세 결과를 기억해 두는 최대 장소 수. 넘으면 가장 오래 안 쓴 것부터 지운다.
  static const int maxCachedPlaceDetails = PlaceDetailsCache.maxEntries;

  /// 상세 결과(영업 여부 등)를 재사용하는 시간. 지나면 다시 조회한다.
  static const Duration placeDetailsCacheTtl = PlaceDetailsCache.ttl;

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
  MapSearchRequest? _resultsRequest;

  /// 마지막으로 실패한 검색 요청. [retrySearch]가 같은 조건으로 다시 보낸다.
  MapSearchRequest? _lastFailedRequest;

  /// 가장 최근 검색 요청 번호. 이보다 앞선 요청의 응답은 버린다.
  int _searchRequestId = 0;

  /// 가장 최근에 보낸 검색 조건. [_searchRequestId]가 아직 진행 중일 때만 중복 판단에 쓴다.
  MapSearchRequest? _currentSearchRequest;

  // ----- 세션 만료 안내 -----
  // 진행 중인 검색 번호와 세션당 한 번 띄우는 만료 안내를 관리한다.
  final SessionExpiryNotice _sessionExpiryNotice = SessionExpiryNotice();

  // ----- 상세 조회 상태 -----
  PlaceDetailsStatus _detailsStatus = PlaceDetailsStatus.idle;
  String? _detailsErrorMessage;
  int _detailsRequestId = 0;

  /// 장소별 상세 결과. 시계는 쓸 때마다 [now]로 읽는다.
  late final PlaceDetailsCache _detailsCache = PlaceDetailsCache(now);

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
  CachedPlaceDetails? get _selectedCacheEntry {
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
      hasSessionExpiryNotice: _sessionExpiryNotice.isPending,
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
      MapSearchRequest(
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

  Future<void> _runSearch(MapSearchRequest request) async {
    // 같은 검색어·같은 지도 중심의 최신 검색이 아직 진행 중이면 다시 보내지 않는다
    // (버튼 연타 등으로 같은 Google 호출이 반복되지 않게). 다른 검색은 그대로 보낸다.
    if (_currentSearchRequest == request &&
        _sessionExpiryNotice.isSearchInFlight(_searchRequestId)) {
      return;
    }

    final requestId = ++_searchRequestId;
    _currentSearchRequest = request;

    _lastSearchQuery = request.query;
    _searchStatus = MapSearchStatus.loading;
    _searchError = null;
    _clearSelectionState();
    _sessionExpiryNotice.searchStarted(requestId);
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
      final confirmedBySearch = _sessionExpiryNotice.confirmsExpiry(
        requestId,
        isCurrentSearch: _isCurrentSearch(requestId),
      );

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

      _searchError = toMapSearchError(error);
      _searchStatus = MapSearchStatus.failure;
      _notify();
    } finally {
      _sessionExpiryNotice.searchFinished(requestId);
    }
  }

  /// 지금 로그인돼 있는지. 화면 밖에서 구독이 멈춰 있어도 현재 값을 읽는다.
  bool get _isSignedIn => ref.read(authProvider).isAuthenticated;

  /// 만료된 세션의 안내를 한 번만 대기시킨다.
  /// 이미 다시 로그인했다면(이전 세션의 늦은 예외) 새 화면에 띄우지 않는다.
  void _raiseSessionExpiryNotice(int? sessionId) {
    final raised = _sessionExpiryNotice.raise(
      sessionId,
      isSignedIn: _isSignedIn,
      currentSessionId: () => ref.read(authProvider).sessionId,
    );

    if (raised) {
      _notify();
    }
  }

  /// 화면이 세션 만료 안내를 표시했음을 알린다(지도 탭이 활성일 때만 부른다).
  void consumeSessionExpiryNotice() {
    if (_sessionExpiryNotice.consume()) {
      _notify();
    }
  }

  bool _isCurrentSearch(int requestId) {
    return ref.mounted && requestId == _searchRequestId;
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
    if (_sessionExpiryNotice.authChanged(
      sessionId: sessionId,
      isAuthenticated: isAuthenticated,
    )) {
      _notify();
    }
  }

  void _onSessionChanged() {
    // 세션이 바뀐 순간 진행 중이던 검색: 만료로 끝나면 사용자 검색이 만료를 확정한 것이다.
    _sessionExpiryNotice.sessionChanged();

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

    final cachedPlace = _detailsCache.fresh(selectedPlace.id);

    if (cachedPlace != null) {
      _detailsCache.markUsed(selectedPlace.id);
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
      _detailsCache.store(detailPlace);
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

    if (!_detailsCache.isExpired(entry)) {
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

    _detailsCache.markUsed(placeId);
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
