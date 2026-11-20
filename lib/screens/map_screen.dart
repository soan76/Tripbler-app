import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/place_model.dart';
import '../providers/auth/auth_provider.dart';
import '../providers/map/map_provider.dart';
import '../providers/tab_provider.dart';
import '../services/map/location_service.dart';
import '../services/map/map_location_controller.dart';
import '../services/map/map_marker_icon_service.dart';
import '../services/map/route_launcher.dart';
import '../utils/map/place_distance.dart';
import '../utils/map/place_markers.dart';
import '../utils/map/point_of_interest_place.dart';
import '../utils/map/search_query_normalizer.dart';
import 'auth/login_screen.dart';
import '../widgets/map/map_camera.dart';
import '../widgets/map/map_controls.dart';
import '../widgets/map/map_overlay_layout.dart';
import '../widgets/map/map_search_view_rules.dart';
import '../widgets/map/place_detail_card.dart';
import '../widgets/map/place_search_bar.dart';
import '../widgets/map/place_search_results_panel.dart';
import '../widgets/map/session_expiry_notice_listener.dart';
import '../widgets/map/tab_scoped_snack_bar.dart';
import '../widgets/map/tripbler_google_map.dart';

/// 구글 맵 화면을 구성하는 StatefulWidget 클래스
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

/// 구글 맵 화면을 구성하는 State 클래스
class _MapScreenState extends ConsumerState<MapScreen> {
  // 현재 위치 방향 아이콘 경로
  static const String _currentLocationIconPath =
      'assets/images/current_location_arrow.png';

  // 현재 위치 방향 아이콘 크기
  static const int _currentLocationIconSize = 72;

  // 하단 탭에서 지도 탭의 인덱스(tabProvider)
  static const int _mapTabIndex = 1;

  // 펼친 결과 목록 높이(화면 비율)
  static const double _expandedPanelFraction = 0.45;

  // 장소 검색 입력
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 결과 목록 펼침 여부
  bool _resultsExpanded = false;

  // 검색창에 글자가 있는지. 뒤로가기 판정(PopScope.canPop)에 쓰며, 비었다↔찼다가
  // 바뀔 때만 다시 그린다.
  bool _hasSearchText = false;

  // 가장 최근 검색 제출 번호(늦게 끝난 이전 제출의 카메라 이동을 막는다)
  int _searchSubmitId = 0;

  // 다른 탭에 있는 동안 검색이 끝나 아직 결과에 카메라를 맞추지 못했는지.
  // 지도가 보이지 않으면 카메라 이동이 조용히 실패하므로, 지도 탭에 돌아왔을 때 맞춘다.
  bool _pendingResultsFit = false;

  // 지도 탭이 아닐 때 생긴 안내 중 지도 탭에 들어올 때 보여줄 마지막 한 건.
  // 앱은 홈 탭으로 시작하지만 MapScreen은 바로 만들어져, 시작 때 위치 안내가 여기 남는다.
  String? _pendingMapMessage;

  // 지도 화면이 띄운 안내. 지도 탭을 떠나면 닫는다(만료 안내는 리스너가 따로 맡는다).
  late final TabScopedSnackBar _snackBar = TabScopedSnackBar(
    isActive: () => mounted && _isMapTabActive(),
  );

  // 마지막으로 확인한 검색 가능 상태, 로그인 세션 번호, 선택 장소 id
  // (로그인 해제·장소 선택 순간을 감지한다)
  late PlaceSearchAvailability _lastAvailability;
  late int _lastSessionId;
  String? _lastSelectedPlaceId;

  // 현재 위치와 방향 상태를 관리하는 Controller
  final MapLocationController _locationController = MapLocationController();

  // 현재 위치 마커 아이콘 생성 Service
  final MapMarkerIconService _markerIconService = const MapMarkerIconService();

  // Google 지도 길찾기를 외부 앱으로 여는 Service
  final RouteLauncher _routeLauncher = RouteLauncher();

  // 지도 카메라(컨트롤러, 현재 중심·줌, 이동)
  final MapCamera _camera = MapCamera();

  // 현재 위치 방향 아이콘
  BitmapDescriptor? _currentLocationIcon;

  @override
  void initState() {
    super.initState();

    // 현재 위치 마커용 이미지 로딩
    _loadCurrentLocationIcon();

    // 현재 위치/방향 Controller 초기화
    _locationController.initialize();

    // 위치 또는 방향 상태 변경 시 화면 갱신
    _locationController.addListener(_onLocationStateChanged);

    _searchController.addListener(_onSearchTextChanged);

    final auth = ref.read(authProvider);
    _lastAvailability = _availabilityOf(auth);
    _lastSessionId = auth.sessionId;
    _lastSelectedPlaceId = ref.read(mapProvider).selectedPlace?.id;

    // 구독은 화면이 사라질 때 함께 닫힌다.
    ref.listenManual(authProvider, (_, auth) => _onAuthStateChanged(auth));
    ref.listenManual(mapProvider, (_, map) => _onMapStateChanged(map));
    ref.listenManual(
      tabProvider.select((tab) => tab.selectedIndex == _mapTabIndex),
      (_, isActive) => _onMapTabActiveChanged(isActive),
    );
  }

  /// 지도 탭에 들어오거나 떠날 때.
  void _onMapTabActiveChanged(bool isActive) {
    if (!mounted) {
      return;
    }

    if (!isActive) {
      _snackBar.closeForInactiveTab();
      return;
    }

    _snackBar.cancelPendingClose();

    final pendingMessage = _pendingMapMessage;
    final fitResults = _pendingResultsFit;
    _pendingMapMessage = null;
    _pendingResultsFit = false;

    if (pendingMessage == null && !fitResults) {
      return;
    }

    // 탭 전환으로 지도가 다시 배치된 뒤에 보여주고 맞춘다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isMapTabActive()) {
        return;
      }

      if (pendingMessage != null) {
        _showMapSnackBar(pendingMessage);
      }

      final mapState = ref.read(mapProvider);

      // 그사이 장소를 골라 카드가 열려 있으면 그 장소를 보고 있으므로 옮기지 않는다.
      if (MapSearchViewRules.shouldFitResultsOnTabEnter(
        fitResults: fitResults,
        searchStatus: mapState.searchStatus,
        hasSelectedPlace: mapState.selectedPlace != null,
      )) {
        _fitCameraToResults(mapState);
      }
    });
  }

  @override
  void dispose() {
    // Controller Listener 해제
    _locationController.removeListener(_onLocationStateChanged);

    // 위치 Stream, Compass Stream, Timer 등을
    // MapLocationController 내부에서 정리함.
    _locationController.dispose();

    // Google Map Controller 종료
    _camera.dispose();

    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();

    super.dispose();
  }

  /// 현재 위치 또는 방향 상태가 변경됐을 때
  /// 현재 위치 마커를 다시 그림.
  void _onLocationStateChanged() {
    if (!mounted) {
      return;
    }

    // 위치를 확인했으면 기다리던 위치 안내("확인하고 있습니다" 등)는 지난 일이다.
    if (_locationController.currentPosition != null) {
      _pendingMapMessage = null;
    }

    setState(() {});
  }

  void _onSearchTextChanged() {
    final hasText = _searchController.text.isNotEmpty;

    if (!mounted || hasText == _hasSearchText) {
      return;
    }

    setState(() {
      _hasSearchText = hasText;
    });
  }

  /// Google Map 생성 완료 처리
  void _onMapCreated(GoogleMapController controller) {
    _camera.attach(controller);

    // 지도 생성 후 최초 현재 위치 요청
    _initializeCurrentLocation();
  }

  /// assets에 등록된 현재 위치 방향 아이콘을
  /// Google Map Marker용 BitmapDescriptor로 변환함.
  Future<void> _loadCurrentLocationIcon() async {
    try {
      final icon = await _markerIconService.createResizedBitmapDescriptor(
        assetPath: _currentLocationIconPath,
        targetWidth: _currentLocationIconSize,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentLocationIcon = icon;
      });
    } catch (error, stackTrace) {
      debugPrint('현재 위치 아이콘 로딩 실패: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 지도 생성 후 최초 현재 위치를 요청함.
  Future<void> _initializeCurrentLocation() async {
    try {
      final position = await _locationController.requestCurrentLocation();

      if (!mounted) {
        return;
      }

      // 최근 위치 또는 최신 위치를 얻었다면
      // 해당 위치로 지도 이동
      if (position != null) {
        await _camera.moveToCurrentLocation(position);

        return;
      }

      // 위치를 전혀 확보하지 못하고
      // 실제 최신 위치 요청까지 timeout 된 경우
      if (_locationController.hasShownTimeoutMessage) {
        _showMapSnackBar('현재 위치를 확인하고 있습니다.');
      }
    } on LocationServiceException catch (error) {
      if (!mounted) {
        return;
      }

      /*
       * 최초 권한 요청을 거부한 경우 여기서 끝남.
       *
       * 자동 재시도하지 않기 때문에
       * timeout 요청이 반복되지 않음.
       */
      _showMapSnackBar(error.message);
    } catch (error, stackTrace) {
      debugPrint('현재 위치 초기화 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      _showMapSnackBar('현재 위치를 가져오지 못했습니다.');
    }
  }

  /// 현재 위치 버튼 클릭 처리
  Future<void> _onCurrentLocationPressed() async {
    try {
      /*
       * requestCurrentLocation 내부에서
       *
       * 1. 위치 권한 확인/재요청
       * 2. 기존 위치 확인
       * 3. 최근 위치 확인
       * 4. 실제 최신 위치 요청
       * 5. 위치 Stream 시작
       *
       * 을 처리함.
       */
      final position = await _locationController.requestCurrentLocation();

      if (!mounted) {
        return;
      }

      // 위치를 확보했다면 해당 위치로 이동
      if (position != null) {
        await _camera.moveToCurrentLocation(position);

        return;
      }

      // 위치가 전혀 없는 상태에서 timeout 된 경우에만
      // 안내 메시지를 표시함.
      if (_locationController.hasShownTimeoutMessage) {
        _showMapSnackBar(
          '현재 위치를 아직 확인하지 못했습니다. '
          '잠시 후 다시 시도해 주세요.',
        );
      }
    } on LocationServiceException catch (error) {
      if (!mounted) {
        return;
      }

      /*
       * 사용자가 최초 권한 요청에서 거부했더라도,
       * 현재 위치 버튼을 누르면 LocationService가
       * 다시 권한 상태를 확인함.
       */
      _showMapSnackBar(error.message);
    } catch (error, stackTrace) {
      debugPrint('현재 위치 이동 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      _showMapSnackBar('현재 위치로 이동하지 못했습니다.');
    }
  }

  /// 지도 관련 안내 메시지 표시
  ///
  /// 기존 SnackBar는 내리고 새 메시지만 표시해 같은 안내가 쌓이지 않게 한다.
  /// 지도 탭이 아닐 때는 마지막 한 건을 보관했다가 지도 탭에 들어올 때 띄운다.
  /// [dropWhenHidden]이면(예: 다른 탭으로 옮긴 뒤 끝난 길찾기 실패) 보관하지 않고 버린다.
  void _showMapSnackBar(String message, {bool dropWhenHidden = false}) {
    if (!mounted) {
      return;
    }

    if (!_isMapTabActive()) {
      if (!dropWhenHidden) {
        _pendingMapMessage = message;
      }
      return;
    }

    _snackBar.show(
      ScaffoldMessenger.of(context),
      content: Text(message),
      duration: const Duration(seconds: 3),
    );
  }

  /// 선택한 장소로 Google 지도 길찾기를 연다. 실패하면 카드는 그대로 두고 안내한다.
  Future<void> _openDirections(PlaceModel place) async {
    final result = await _routeLauncher.openDirections(place);

    if (result == RouteLaunchResult.failed) {
      _showMapSnackBar(
        PlaceDetailCard.routeFailedMessage,
        dropWhenHidden: true,
      );
    }
  }

  // ----- 장소 검색 -----

  bool _isMapTabActive() {
    return ref.read(tabProvider).selectedIndex == _mapTabIndex;
  }

  PlaceSearchAvailability _availabilityOf(AuthState auth) {
    return MapSearchViewRules.availabilityOf(
      isAuthenticated: auth.isAuthenticated,
      sessionRestoreFailed: auth.sessionRestoreFailed,
    );
  }

  /// 로그아웃·세션 만료·비로그인 확인 순간: MapNotifier가 검색 결과를 비우므로
  /// 화면의 검색어·목록 펼침도 비우고, 진행 중이던 제출의 카메라 이동을 막는다.
  /// 비로그인 검색창은 읽기 전용이라 남은 검색어를 사용자가 지울 수 없기 때문이다.
  ///
  /// 다른 탭에 있는 동안 로그아웃→재로그인이 하나로 합쳐져 도착하면 검색 가능 상태는
  /// 그대로지만 세션 번호가 바뀐다. 이때도 이전 사용자의 검색어를 비운다.
  void _onAuthStateChanged(AuthState auth) {
    final availability = _availabilityOf(auth);
    final previous = _lastAvailability;
    final sessionChanged = auth.sessionId != _lastSessionId;
    _lastAvailability = availability;
    _lastSessionId = auth.sessionId;

    final shouldReset = MapSearchViewRules.shouldResetOnAuthChange(
      previous: previous,
      current: availability,
      sessionChanged: sessionChanged,
    );

    if (!mounted || !shouldReset) {
      return;
    }

    _searchSubmitId++;
    _pendingResultsFit = false;
    _searchFocusNode.unfocus();
    _searchController.clear();

    if (_resultsExpanded) {
      setState(() {
        _resultsExpanded = false;
      });
    }
  }

  /// 장소가 새로 선택된 순간(목록 항목, 검색 결과 마커)에만 결과 목록을 접는다.
  /// 카드가 열린 채 사용자가 손잡이로 다시 펼친 목록은 그대로 둔다.
  void _onMapStateChanged(MapState map) {
    final selectedId = map.selectedPlace?.id;
    final previousId = _lastSelectedPlaceId;
    _lastSelectedPlaceId = selectedId;

    if (!mounted ||
        !_resultsExpanded ||
        !MapSearchViewRules.isNewSelection(
          previousId: previousId,
          currentId: selectedId,
        )) {
      return;
    }

    setState(() {
      _resultsExpanded = false;
    });
  }

  /// 검색을 쓸 수 없는 상태에서 검색창을 누르거나 제출했을 때 안내한다.
  void _onSearchUnavailable() {
    if (ref.read(authProvider).sessionRestoreFailed) {
      _showMapSnackBar('로그인 정보를 확인하지 못해 검색할 수 없습니다. 위쪽 배너의 다시 시도를 눌러 주세요.');
      return;
    }

    _searchFocusNode.unfocus();

    _snackBar.show(
      ScaffoldMessenger.of(context),
      content: const Text('로그인하면 장소를 검색할 수 있습니다.'),
      duration: SessionExpiryNoticeListener.displayDuration,
      action: SnackBarAction(label: '로그인', onPressed: _openLogin),
    );
  }

  void _openLogin() {
    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  /// 검색 제출: 그 순간의 지도 중심으로 검색하고 결과 목록을 펼친다.
  Future<void> _submitSearch(String text) async {
    _searchFocusNode.unfocus();

    final normalizedQuery = SearchQueryNormalizer.normalize(text);

    if (normalizedQuery == null) {
      return;
    }

    // 검색창이 아직 다시 그려지기 전에 로그인이 풀렸으면 검색이 시작되지 않는다.
    // 목록 펼침만 남지 않게 여기서 멈추고 안내한다.
    if (!_canSearchNow()) {
      _onSearchUnavailable();
      return;
    }

    final mapNotifier = ref.read(mapProvider.notifier);
    final submitId = ++_searchSubmitId;
    _pendingResultsFit = false;

    // 지도가 준비되지 않았으면 중심 좌표 없이 검색한다.
    final center = _camera.isReady ? _camera.target : null;

    setState(() {
      _resultsExpanded = true;
    });

    // 결과를 가까운 순으로 정렬하고 거리를 표시할 기준. 위치를 아직 모르면 서버 순서.
    await mapNotifier.search(
      text,
      center: center,
      userLocation: _locationController.currentPosition,
    );

    if (!mounted || submitId != _searchSubmitId) {
      return;
    }

    final mapState = ref.read(mapProvider);

    if (mapState.searchStatus == MapSearchStatus.success &&
        mapState.lastSearchQuery == normalizedQuery) {
      await _fitCameraToResultsWhenVisible(mapState);
    }
  }

  /// 다시 시도: 처음 검색처럼 결과 목록을 펼치고, 성공하면 결과에 카메라를 맞춘다.
  Future<void> _retrySearch() async {
    if (!_canSearchNow()) {
      _onSearchUnavailable();
      return;
    }

    final mapNotifier = ref.read(mapProvider.notifier);
    final submitId = ++_searchSubmitId;
    _pendingResultsFit = false;

    setState(() {
      _resultsExpanded = true;
    });

    await mapNotifier.retrySearch();

    if (!mounted || submitId != _searchSubmitId) {
      return;
    }

    final mapState = ref.read(mapProvider);

    if (mapState.searchStatus == MapSearchStatus.success) {
      await _fitCameraToResultsWhenVisible(mapState);
    }
  }

  /// 지도 탭이 보이면 바로, 다른 탭에 있으면 지도 탭으로 돌아왔을 때 결과에 카메라를 맞춘다.
  Future<void> _fitCameraToResultsWhenVisible(MapState mapState) async {
    if (!_isMapTabActive()) {
      _pendingResultsFit = true;
      return;
    }

    await _fitCameraToResults(mapState);
  }

  /// 지금 로그인 상태로 검색할 수 있는지. 화면의 검색창 상태는 한 프레임 늦을 수 있어
  /// 제출 순간의 값을 다시 읽는다.
  bool _canSearchNow() {
    return _availabilityOf(ref.read(authProvider)) ==
        PlaceSearchAvailability.ready;
  }

  void _clearSearch() {
    _searchSubmitId++;
    _pendingResultsFit = false;
    _searchController.clear();
    ref.read(mapProvider.notifier).clearSearch();

    setState(() {
      _resultsExpanded = false;
    });
  }

  /// 결과 전체가 보이게 카메라를 맞춘다. 결과가 1개면 그 장소로 이동한다.
  Future<void> _fitCameraToResults(MapState mapState) {
    return _camera.fitToResults(mapState.searchResultBounds);
  }

  /// 목록에서 결과를 고르면 선택하고, 목록을 접고, 그 장소로 카메라를 옮긴다.
  Future<void> _selectSearchResult(PlaceModel place) async {
    // 키보드가 열려 있으면 상세 카드가 숨겨지므로, 장소를 고르면 키보드를 내린다.
    _searchFocusNode.unfocus();

    ref.read(mapProvider.notifier).selectSearchResult(place);

    setState(() {
      _resultsExpanded = false;
    });

    await _camera.moveToPlace(place);
  }

  /// 지도 빈 곳 탭: 키보드를 내리고 열린 카드만 닫는다. 검색 결과는 유지한다.
  void _onMapTapped() {
    _searchFocusNode.unfocus();
    ref.read(mapProvider.notifier).clearSelectedPlace();
  }

  /// 지도에 원래 보이는 장소 아이콘(POI) 탭: 그 장소의 카드를 연다.
  ///
  /// 장소 ID·이름·좌표는 지도 SDK가 준 값이라 서버를 부르지 않는다. 거리는 누른 순간의
  /// 기기 위치에서 잰다. 카메라는 옮기지 않는다(이미 화면에 보이는 곳을 눌렀다).
  void _onPointOfInterestTapped(TappedPointOfInterest pointOfInterest) {
    _searchFocusNode.unfocus();

    ref
        .read(mapProvider.notifier)
        .selectMapPlace(
          placeFromPointOfInterest(pointOfInterest),
          userLocation: _locationController.currentPosition,
        );
  }

  /// Android 뒤로가기: 카드 닫기 → 목록 접기 → 검색 해제 → 기본 동작.
  /// 지도 탭이 선택돼 있을 때만 가로챈다(다른 탭에서는 MapScreen이 숨어 있어도 살아 있음).
  bool _hasBackStep(MapState mapState) {
    return MapSearchViewRules.hasBackStep(
      hasSelectedPlace: mapState.selectedPlace != null,
      resultsExpanded: _resultsExpanded,
      searchStatus: mapState.searchStatus,
      hasSearchText: _hasSearchText,
    );
  }

  void _handleBack() {
    if (ref.read(mapProvider).selectedPlace != null) {
      ref.read(mapProvider.notifier).clearSelectedPlace();
      return;
    }

    if (_resultsExpanded) {
      setState(() {
        _resultsExpanded = false;
      });
      return;
    }

    _clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapProvider);
    final auth = ref.watch(authProvider);
    final mapNotifier = ref.read(mapProvider.notifier);
    final isMapTabActive = ref.watch(tabProvider).selectedIndex == _mapTabIndex;

    // 현재 선택된 장소
    final selectedPlace = mapState.selectedPlace;
    final hasSearch = mapState.searchStatus != MapSearchStatus.idle;

    // 현재 위치 마커(아직 위치를 모르면 표시하지 않음)
    final locationMarker = currentLocationMarker(
      position: _locationController.currentPosition,
      heading: _locationController.currentHeading,
      icon: _currentLocationIcon,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 펼친 목록은 화면의 약 45%까지. 검색창 아래 남은 높이가 모자라면
        // (키보드, 상세 카드, 검색창 안내 문구·큰 글자) MapOverlayLayout이 더 줄인다.
        final expandedHeight = constraints.maxHeight * _expandedPanelFraction;

        return PopScope(
          canPop: !(isMapTabActive && _hasBackStep(mapState)),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || !_isMapTabActive()) {
              return;
            }

            _handleBack();
          },
          child: SessionExpiryNoticeListener(
            isActive: isMapTabActive,
            hasNotice: mapState.hasSessionExpiryNotice,
            onConsume: mapNotifier.consumeSessionExpiryNotice,
            onLogin: _openLogin,
            child: Stack(
              children: [
                // Google Map
                TripblerGoogleMap(
                  initialCameraPosition: MapCamera.initialPosition,

                  onMapCreated: _onMapCreated,

                  markers: {
                    ...mapState.markers,

                    if (locationMarker != null) locationMarker,
                  },

                  // 빈 곳 탭: 열린 카드만 닫고 검색 결과는 유지한다.
                  onTap: (_) => _onMapTapped(),

                  // 장소 아이콘 탭: 그 장소의 카드를 연다.
                  onPointOfInterestTap: _onPointOfInterestTapped,

                  // 지도 이동/확대/축소 시
                  // Scale Bar 계산 기준과 검색 기준 좌표 갱신
                  onCameraMove: (CameraPosition position) {
                    setState(() {
                      _camera.updatePosition(position);
                    });
                  },
                ),

                // 위에서부터 검색창 → 빈 영역 → 지도 위 버튼 → 결과 목록(손잡이) →
                // 상세 카드를 세로로 놓는다. 하단 영역은 검색창 아래 남은 높이 안에서만
                // 자라므로 검색창(안내 문구·큰 글자 포함)을 가리지 않는다. 버튼은 목록·카드의
                // 실제 높이만큼 올라간다. 빈 영역의 터치는 지도로 간다.
                Positioned.fill(
                  child: MapOverlayLayout(
                    searchBar: PlaceSearchBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      availability: _availabilityOf(auth),
                      isSearching: mapState.isSearching,
                      onSubmitted: _submitSearch,
                      onCleared: _clearSearch,
                      onUnavailable: _onSearchUnavailable,
                    ),
                    mapControlsHeight: MapControls.height,
                    mapControls: MapControls(
                      latitude: _camera.target.latitude,
                      zoom: _camera.zoom,
                      isLoading: _locationController.isLoading,
                      onCurrentLocationPressed: _onCurrentLocationPressed,
                    ),
                    resultsPanel: hasSearch
                        ? PlaceSearchResultsPanel(
                            status: mapState.searchStatus,
                            results: mapState.searchResults,
                            distanceOrigin: mapState.searchResultsOrigin,
                            error: mapState.searchError,
                            canRetry: mapState.canRetrySearch,
                            expanded: _resultsExpanded,
                            expandedHeight: expandedHeight,
                            selectedPlaceId: selectedPlace?.id,
                            onToggleExpanded: () {
                              setState(() {
                                _resultsExpanded = !_resultsExpanded;
                              });
                            },
                            onSelect: _selectSearchResult,
                            onRetry: _retrySearch,
                          )
                        : null,

                    // 장소 선택 시 하단 상세 카드 표시
                    detailCard: selectedPlace != null
                        ? PlaceDetailCard(
                            place: selectedPlace,
                            detailsStatus: mapState.detailsStatus,
                            detailsLoaded: mapState.selectedPlaceDetailsLoaded,
                            detailsStale: mapState.selectedPlaceDetailsStale,
                            detailsFetchedAt:
                                mapState.selectedPlaceDetailsFetchedAt,

                            // 만료 판단과 같은 시계로 날짜 표시를 정한다.
                            now: mapNotifier.now,
                            detailsErrorMessage: mapState.detailsErrorMessage,

                            // 장소 선택 해제
                            onClose: mapNotifier.clearSelectedPlace,

                            // 평점·영업 정보 조회와 다시 시도
                            onDetailPressed: () {
                              mapNotifier.loadSelectedPlaceDetails();
                            },

                            // Google 지도 길찾기 열기
                            onRoutePressed: () =>
                                _openDirections(selectedPlace),

                            // 검색 결과는 검색할 때, 지도에서 고른 장소는 고른
                            // 순간의 기기 위치에서의 거리
                            distanceLabel: PlaceDistance.labelTo(
                              mapState.selectedPlaceDistanceOrigin,
                              selectedPlace,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
