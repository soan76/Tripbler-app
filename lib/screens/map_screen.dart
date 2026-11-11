import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/place_model.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../providers/tab_provider.dart';
import '../services/map/location_service.dart';
import '../services/map/map_location_controller.dart';
import '../services/map/map_marker_icon_service.dart';
import '../utils/map/scale_bar_calculator.dart';
import '../utils/map/search_query_normalizer.dart';
import 'auth/login_screen.dart';
import '../widgets/map/current_location_button.dart';
import '../widgets/map/map_overlay_layout.dart';
import '../widgets/map/map_scale_bar.dart';
import '../widgets/map/map_search_view_rules.dart';
import '../widgets/map/place_detail_card.dart';
import '../widgets/map/place_search_bar.dart';
import '../widgets/map/place_search_results_panel.dart';
import '../widgets/map/session_expiry_notice_listener.dart';
import '../widgets/map/tripbler_google_map.dart';

/// 구글 맵 화면을 구성하는 StatefulWidget 클래스
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// 구글 맵 화면을 구성하는 State 클래스
class _MapScreenState extends State<MapScreen> {
  // 위치를 가져오지 못했을 때 사용할 기본 위치
  static const LatLng _seoulCityHall = LatLng(37.5665, 126.9780);

  // 지도 최초 카메라 위치
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: _seoulCityHall,
    zoom: 13,
  );

  // 현재 위치 방향 아이콘 경로
  static const String _currentLocationIconPath =
      'assets/images/current_location_arrow.png';

  // 현재 위치 방향 아이콘 크기
  static const int _currentLocationIconSize = 72;

  // 하단 탭에서 지도 탭의 인덱스(TabProvider)
  static const int _mapTabIndex = 1;

  // 검색 결과가 1개일 때 줌, 결과를 고를 때 최소 줌
  static const double _singleResultZoom = 16;
  static const double _selectedPlaceMinZoom = 15;

  // 결과 전체를 맞출 때 가장자리 여백(px)
  static const double _resultsBoundsPadding = 64;

  // 펼친 결과 목록 높이(화면 비율)
  static const double _expandedPanelFraction = 0.45;

  // 하단 패널 위에 놓이는 축척 표시·현재 위치 버튼 영역 높이(버튼 56 + 아래 여백 24)
  static const double _mapControlsHeight = 80;

  // 장소 검색 입력
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 결과 목록 펼침 여부
  bool _resultsExpanded = false;

  // 가장 최근 검색 제출 번호(늦게 끝난 이전 제출의 카메라 이동을 막는다)
  int _searchSubmitId = 0;

  // 구독하는 Provider(로그인 해제·장소 선택 순간을 감지한다)
  late final AuthProvider _authProvider;
  late final MapProvider _mapProvider;

  // 마지막으로 확인한 검색 가능 상태와 선택 장소 id
  late PlaceSearchAvailability _lastAvailability;
  String? _lastSelectedPlaceId;

  // 현재 위치와 방향 상태를 관리하는 Controller
  final MapLocationController _locationController = MapLocationController();

  // 현재 위치 마커 아이콘 생성 Service
  final MapMarkerIconService _markerIconService = const MapMarkerIconService();

  // Google Map Controller
  GoogleMapController? _mapController;

  // 현재 지도 카메라 중심 좌표
  LatLng _currentCameraTarget = _seoulCityHall;

  // 현재 지도 줌 레벨
  double _currentZoom = 13;

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

    _authProvider = context.read<AuthProvider>();
    _mapProvider = context.read<MapProvider>();
    _lastAvailability = _availabilityOf(_authProvider);
    _lastSelectedPlaceId = _mapProvider.selectedPlace?.id;
    _authProvider.addListener(_onAuthStateChanged);
    _mapProvider.addListener(_onMapStateChanged);
  }

  @override
  void dispose() {
    // Controller Listener 해제
    _locationController.removeListener(_onLocationStateChanged);
    _authProvider.removeListener(_onAuthStateChanged);
    _mapProvider.removeListener(_onMapStateChanged);

    // 위치 Stream, Compass Stream, Timer 등을
    // MapLocationController 내부에서 정리함.
    _locationController.dispose();

    // Google Map Controller 종료
    _mapController?.dispose();

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

    setState(() {});
  }

  /// Google Map 생성 완료 처리
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

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
        await _moveCameraToCurrentLocation(position);

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
        await _moveCameraToCurrentLocation(position);

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

  /// 현재 위치로 지도 카메라 이동
  Future<void> _moveCameraToCurrentLocation(LatLng position) async {
    final controller = _mapController;

    if (controller == null) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: position, zoom: 17),
        ),
      );
    } catch (error) {
      debugPrint('현재 위치 카메라 이동 실패: $error');
    }
  }

  /// 현재 위치 방향 마커를 생성함.
  Marker? _buildCurrentLocationMarker() {
    final currentUserPosition = _locationController.currentPosition;

    // 아직 현재 위치를 알 수 없다면
    // 현재 위치 마커를 표시하지 않음.
    if (currentUserPosition == null) {
      return null;
    }

    return Marker(
      markerId: const MarkerId('current_user_location'),

      // 사용자의 현재 위치
      position: currentUserPosition,

      // Compass 방향에 따라 마커 회전
      rotation: _locationController.currentHeading,

      // 아이콘 중심을 실제 위치와 맞춤
      anchor: const Offset(0.5, 0.5),

      // 지도 위에 평평하게 배치하여
      // 방향 회전을 자연스럽게 표시함.
      flat: true,

      // 커스텀 아이콘 로딩 전에는
      // 기본 파란 마커를 임시 표시함.
      icon:
          _currentLocationIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),

      // 장소 마커보다 위에 표시
      zIndex: 9999,
    );
  }

  /// 지도 관련 안내 메시지 표시
  void _showMapSnackBar(String message) {
    if (!mounted) {
      return;
    }

    /*
     * 기존 SnackBar가 남아있으면 제거하고
     * 새로운 메시지만 표시함.
     *
     * 같은 위치 오류 메시지가 화면에
     * 여러 개 쌓이는 것을 방지함.
     */
    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  // ----- 장소 검색 -----

  bool _isMapTabActive(BuildContext context) {
    return context.read<TabProvider>().selectedIndex == _mapTabIndex;
  }

  PlaceSearchAvailability _availabilityOf(AuthProvider authProvider) {
    return MapSearchViewRules.availabilityOf(
      isAuthenticated: authProvider.isAuthenticated,
      sessionRestoreFailed: authProvider.sessionRestoreFailed,
    );
  }

  /// 로그아웃·세션 만료·비로그인 확인 순간: MapProvider가 검색 결과를 비우므로
  /// 화면의 검색어·목록 펼침도 비우고, 진행 중이던 제출의 카메라 이동을 막는다.
  /// 비로그인 검색창은 읽기 전용이라 남은 검색어를 사용자가 지울 수 없기 때문이다.
  void _onAuthStateChanged() {
    final availability = _availabilityOf(_authProvider);
    final previous = _lastAvailability;
    _lastAvailability = availability;

    if (!mounted ||
        !MapSearchViewRules.shouldResetSearchInput(
          previous: previous,
          current: availability,
        )) {
      return;
    }

    _searchSubmitId++;
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
  void _onMapStateChanged() {
    final selectedId = _mapProvider.selectedPlace?.id;
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
    final authProvider = context.read<AuthProvider>();

    if (authProvider.sessionRestoreFailed) {
      _showMapSnackBar('로그인 정보를 확인하지 못해 검색할 수 없습니다. 위쪽 배너의 다시 시도를 눌러 주세요.');
      return;
    }

    _searchFocusNode.unfocus();

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('로그인하면 장소를 검색할 수 있습니다.'),
          duration: SessionExpiryNoticeListener.displayDuration,
          action: SnackBarAction(label: '로그인', onPressed: _openLogin),
        ),
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

    final mapProvider = context.read<MapProvider>();
    final submitId = ++_searchSubmitId;

    // 지도가 준비되지 않았으면 중심 좌표 없이 검색한다.
    final center = _mapController != null ? _currentCameraTarget : null;

    setState(() {
      _resultsExpanded = true;
    });

    await mapProvider.search(text, center: center);

    if (!mounted || submitId != _searchSubmitId) {
      return;
    }

    if (mapProvider.searchStatus == MapSearchStatus.success &&
        mapProvider.lastSearchQuery == normalizedQuery) {
      await _fitCameraToResults(mapProvider);
    }
  }

  Future<void> _retrySearch() async {
    final mapProvider = context.read<MapProvider>();
    final submitId = ++_searchSubmitId;

    await mapProvider.retrySearch();

    if (!mounted || submitId != _searchSubmitId) {
      return;
    }

    if (mapProvider.searchStatus == MapSearchStatus.success) {
      await _fitCameraToResults(mapProvider);
    }
  }

  void _clearSearch() {
    _searchSubmitId++;
    _searchController.clear();
    context.read<MapProvider>().clearSearch();

    setState(() {
      _resultsExpanded = false;
    });
  }

  /// 결과 전체가 보이게 카메라를 맞춘다. 결과가 1개면 그 장소로 이동한다.
  Future<void> _fitCameraToResults(MapProvider mapProvider) async {
    final controller = _mapController;
    final bounds = mapProvider.searchResultBounds;

    if (controller == null || bounds == null) {
      return;
    }

    try {
      if (bounds.southwest == bounds.northeast) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(bounds.southwest, _singleResultZoom),
        );
      } else {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, _resultsBoundsPadding),
        );
      }
    } catch (error) {
      // 지도가 아직 배치되지 않았을 때 생기는 예외는 무시한다.
      debugPrint('검색 결과로 카메라 이동 실패: $error');
    }
  }

  /// 목록에서 결과를 고르면 선택하고, 목록을 접고, 그 장소로 카메라를 옮긴다.
  Future<void> _selectSearchResult(PlaceModel place) async {
    // 키보드가 열려 있으면 상세 카드가 숨겨지므로, 장소를 고르면 키보드를 내린다.
    _searchFocusNode.unfocus();

    context.read<MapProvider>().selectSearchResult(place);

    setState(() {
      _resultsExpanded = false;
    });

    final controller = _mapController;

    if (controller == null || !place.hasCoordinates) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(place.latitude!, place.longitude!),
          _currentZoom < _selectedPlaceMinZoom
              ? _selectedPlaceMinZoom
              : _currentZoom,
        ),
      );
    } catch (error) {
      debugPrint('선택한 장소로 카메라 이동 실패: $error');
    }
  }

  /// 지도 빈 곳 탭: 키보드를 내리고 열린 카드만 닫는다. 검색 결과는 유지한다.
  void _onMapTapped() {
    _searchFocusNode.unfocus();
    context.read<MapProvider>().clearSelectedPlace();
  }

  /// Android 뒤로가기: 카드 닫기 → 목록 접기 → 검색 해제 → 기본 동작.
  /// 지도 탭이 선택돼 있을 때만 가로챈다(다른 탭에서는 MapScreen이 숨어 있어도 살아 있음).
  bool _hasBackStep(MapProvider mapProvider) {
    return mapProvider.selectedPlace != null ||
        _resultsExpanded ||
        mapProvider.searchStatus != MapSearchStatus.idle ||
        _searchController.text.isNotEmpty;
  }

  void _handleBack(MapProvider mapProvider) {
    if (mapProvider.selectedPlace != null) {
      mapProvider.clearSelectedPlace();
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
    final mapProvider = context.watch<MapProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isMapTabActive =
        context.watch<TabProvider>().selectedIndex == _mapTabIndex;

    // 현재 선택된 장소
    final selectedPlace = mapProvider.selectedPlace;
    final hasSearch = mapProvider.searchStatus != MapSearchStatus.idle;

    // 현재 위치 마커
    final currentLocationMarker = _buildCurrentLocationMarker();

    // 현재 지도 줌 상태에 따른 Scale Bar 계산
    final scaleBarData = ScaleBarCalculator.calculate(
      currentLatitude: _currentCameraTarget.latitude,
      currentZoom: _currentZoom,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 펼친 목록은 화면의 약 45%까지. 검색창 아래 남은 높이가 모자라면
        // (키보드, 상세 카드, 검색창 안내 문구·큰 글자) MapOverlayLayout이 더 줄인다.
        final expandedHeight = constraints.maxHeight * _expandedPanelFraction;

        return PopScope(
          canPop: !(isMapTabActive && _hasBackStep(mapProvider)),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || !_isMapTabActive(context)) {
              return;
            }

            _handleBack(context.read<MapProvider>());
          },
          child: SessionExpiryNoticeListener(
            isActive: isMapTabActive,
            hasNotice: mapProvider.hasSessionExpiryNotice,
            onConsume: context.read<MapProvider>().consumeSessionExpiryNotice,
            onLogin: _openLogin,
            child: Stack(
              children: [
                // Google Map
                TripblerGoogleMap(
                  initialCameraPosition: _initialCameraPosition,

                  onMapCreated: _onMapCreated,

                  markers: {
                    ...mapProvider.markers,

                    if (currentLocationMarker != null) currentLocationMarker,
                  },

                  // 빈 곳 탭: 열린 카드만 닫고 검색 결과는 유지한다.
                  onTap: (_) => _onMapTapped(),

                  // 지도 이동/확대/축소 시
                  // Scale Bar 계산 기준과 검색 기준 좌표 갱신
                  onCameraMove: (CameraPosition position) {
                    setState(() {
                      _currentCameraTarget = position.target;

                      _currentZoom = position.zoom;
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
                      availability: _availabilityOf(authProvider),
                      isSearching: mapProvider.isSearching,
                      onSubmitted: _submitSearch,
                      onCleared: _clearSearch,
                      onUnavailable: _onSearchUnavailable,
                    ),
                    mapControlsHeight: _mapControlsHeight,
                    mapControls: SizedBox(
                      height: _mapControlsHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 지도 축척 표시
                          Positioned(
                            right: 88,
                            bottom: 38,
                            child: MapScaleBar(
                              data: scaleBarData,
                              label: ScaleBarCalculator.formatDistance(
                                scaleBarData.distanceMeters,
                              ),
                            ),
                          ),

                          // 현재 위치 버튼
                          CurrentLocationButton(
                            isLoading: _locationController.isLoading,
                            bottom: 24,
                            onPressed: _onCurrentLocationPressed,
                          ),
                        ],
                      ),
                    ),
                    resultsPanel: hasSearch
                        ? PlaceSearchResultsPanel(
                            status: mapProvider.searchStatus,
                            results: mapProvider.searchResults,
                            error: mapProvider.searchError,
                            canRetry: mapProvider.canRetrySearch,
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
                            detailsStatus: mapProvider.detailsStatus,
                            detailsLoaded:
                                mapProvider.selectedPlaceDetailsLoaded,
                            detailsStale: mapProvider.selectedPlaceDetailsStale,
                            detailsFetchedAt:
                                mapProvider.selectedPlaceDetailsFetchedAt,
                            detailsErrorMessage:
                                mapProvider.detailsErrorMessage,

                            // 장소 선택 해제
                            onClose: context
                                .read<MapProvider>()
                                .clearSelectedPlace,

                            // 평점·영업 정보 조회와 다시 시도
                            onDetailPressed: () {
                              context
                                  .read<MapProvider>()
                                  .loadSelectedPlaceDetails();
                            },

                            // 길찾기는 5단계에서 연결한다. 그때까지 버튼은 꺼 둔다.
                            onRoutePressed: null,
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
