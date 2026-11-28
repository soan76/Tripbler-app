import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/place_model.dart';
import '../models/schedule/schedule_item.dart';
import '../providers/auth/auth_provider.dart';
import '../providers/map/map_provider.dart';
import '../providers/map/place_picker_provider.dart';
import '../services/map/location_service.dart';
import '../services/map/map_location_controller.dart';
import '../utils/map/place_markers.dart';
import '../utils/map/point_of_interest_place.dart';
import '../utils/map/search_query_normalizer.dart';
import '../widgets/map/map_camera.dart';
import '../widgets/map/map_controls.dart';
import '../widgets/map/map_overlay_layout.dart';
import '../widgets/map/map_search_view_rules.dart';
import '../widgets/map/place_search_bar.dart';
import '../widgets/map/place_search_results_panel.dart';
import '../widgets/map/tripbler_google_map.dart';
import '../widgets/schedule/place_picker_card.dart';
import 'auth/login_screen.dart';

/// 일정에 넣을 장소를 지도에서 고르는 화면(docs/mockups/schedule.md 3-2절).
///
/// 지도 탭과 같은 지도·검색창을 쓰지만 검색 상태는 [placePickerMapProvider]에 따로 둔다.
/// "이 장소 선택"을 누르면 [ScheduledPlace]를 돌려주며 닫히고, 닫기·뒤로 가기는 null을 돌려준다.
class PlacePickerScreen extends ConsumerStatefulWidget {
  const PlacePickerScreen({super.key});

  static const String title = '장소 고르기';

  /// 장소 고르기 화면을 열고 고른 장소를 받는다.
  static Future<ScheduledPlace?> open(BuildContext context) {
    return Navigator.of(context).push<ScheduledPlace>(
      MaterialPageRoute(builder: (_) => const PlacePickerScreen()),
    );
  }

  /// 지도 검색 결과·장소 아이콘을 일정 장소로 바꾼다. 비어 있거나 기본 글자인 주소는 뺀다.
  static ScheduledPlace toScheduledPlace(PlaceModel place) {
    final address = place.address.trim();
    return ScheduledPlace(
      name: place.name,
      address: address.isEmpty || address == '주소 정보 없음' ? null : address,
      latitude: place.latitude,
      longitude: place.longitude,
      placeId: place.id,
    );
  }

  @override
  ConsumerState<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends ConsumerState<PlacePickerScreen> {
  static const double _expandedPanelFraction = 0.45;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final MapLocationController _locationController = MapLocationController();
  final MapCamera _camera = MapCamera();

  bool _resultsExpanded = false;

  /// 가장 최근 검색 제출 번호(늦게 끝난 이전 제출의 카메라 이동을 막는다).
  int _searchSubmitId = 0;

  @override
  void initState() {
    super.initState();
    _locationController.initialize();
    _locationController.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _locationController.removeListener(_onLocationChanged);
    _locationController.dispose();
    _camera.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  void _onMapCreated(GoogleMapController controller) {
    _camera.attach(controller);
    _moveToCurrentLocation(showErrors: false);
  }

  /// 현재 위치로 카메라를 옮긴다. 처음 열 때는 실패해도 조용히 넘어간다(장소는 검색으로 고를 수 있다).
  Future<void> _moveToCurrentLocation({required bool showErrors}) async {
    try {
      final position = await _locationController.requestCurrentLocation();
      if (!mounted) return;
      if (position != null) {
        await _camera.moveToCurrentLocation(position);
      } else if (showErrors && _locationController.hasShownTimeoutMessage) {
        _showSnackBar('현재 위치를 아직 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } on LocationServiceException catch (error) {
      if (mounted && showErrors) _showSnackBar(error.message);
    } catch (_) {
      if (mounted && showErrors) _showSnackBar('현재 위치로 이동하지 못했습니다.');
    }
  }

  void _showSnackBar(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  PlaceSearchAvailability _availabilityOf(AuthState auth) {
    return MapSearchViewRules.availabilityOf(
      isAuthenticated: auth.isAuthenticated,
      sessionRestoreFailed: auth.sessionRestoreFailed,
    );
  }

  bool _canSearchNow() =>
      _availabilityOf(ref.read(authProvider)) == PlaceSearchAvailability.ready;

  /// 로그인 전이면 지도 탭과 같은 로그인 안내를 보인다. 장소는 일정 카드에서 직접 입력할 수 있다.
  void _onSearchUnavailable() {
    _searchFocusNode.unfocus();
    if (ref.read(authProvider).sessionRestoreFailed) {
      _showSnackBar('로그인 정보를 확인하지 못해 검색할 수 없습니다. 장소는 직접 입력할 수 있어요.');
      return;
    }
    _showSnackBar(
      '로그인하면 장소를 검색할 수 있습니다.',
      action: SnackBarAction(label: '로그인', onPressed: _openLogin),
    );
  }

  void _openLogin() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  Future<void> _submitSearch(String text) async {
    _searchFocusNode.unfocus();
    final query = SearchQueryNormalizer.normalize(text);
    if (query == null) return;
    if (!_canSearchNow()) {
      _onSearchUnavailable();
      return;
    }

    final notifier = ref.read(placePickerMapProvider.notifier);
    final submitId = ++_searchSubmitId;
    setState(() => _resultsExpanded = true);
    await notifier.search(
      text,
      center: _camera.isReady ? _camera.target : null,
      userLocation: _locationController.currentPosition,
    );
    if (!mounted || submitId != _searchSubmitId) return;
    final state = ref.read(placePickerMapProvider);
    if (state.searchStatus == MapSearchStatus.success &&
        state.lastSearchQuery == query) {
      await _camera.fitToResults(state.searchResultBounds);
    }
  }

  Future<void> _retrySearch() async {
    if (!_canSearchNow()) {
      _onSearchUnavailable();
      return;
    }
    final submitId = ++_searchSubmitId;
    setState(() => _resultsExpanded = true);
    await ref.read(placePickerMapProvider.notifier).retrySearch();
    if (!mounted || submitId != _searchSubmitId) return;
    final state = ref.read(placePickerMapProvider);
    if (state.searchStatus == MapSearchStatus.success) {
      await _camera.fitToResults(state.searchResultBounds);
    }
  }

  void _clearSearch() {
    _searchSubmitId++;
    _searchController.clear();
    ref.read(placePickerMapProvider.notifier).clearSearch();
    setState(() => _resultsExpanded = false);
  }

  Future<void> _selectSearchResult(PlaceModel place) async {
    _searchFocusNode.unfocus();
    ref.read(placePickerMapProvider.notifier).selectSearchResult(place);
    setState(() => _resultsExpanded = false);
    await _camera.moveToPlace(place);
  }

  void _onPointOfInterestTapped(TappedPointOfInterest pointOfInterest) {
    _searchFocusNode.unfocus();
    ref
        .read(placePickerMapProvider.notifier)
        .selectMapPlace(
          placeFromPointOfInterest(pointOfInterest),
          userLocation: _locationController.currentPosition,
        );
  }

  void _onMapTapped() {
    _searchFocusNode.unfocus();
    ref.read(placePickerMapProvider.notifier).clearSelectedPlace();
  }

  void _select(PlaceModel place) {
    Navigator.of(context).pop(PlacePickerScreen.toScheduledPlace(place));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(placePickerMapProvider);
    final notifier = ref.read(placePickerMapProvider.notifier);
    final availability = ref.watch(authProvider.select(_availabilityOf));
    final selected = state.selectedPlace;
    final locationMarker = currentLocationMarker(
      position: _locationController.currentPosition,
      heading: _locationController.currentHeading,
      icon: null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(PlacePickerScreen.title),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '닫기',
          icon: const Icon(Icons.close),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            TripblerGoogleMap(
              initialCameraPosition: MapCamera.initialPosition,
              onMapCreated: _onMapCreated,
              markers: {...state.markers, ?locationMarker},
              onTap: (_) => _onMapTapped(),
              onPointOfInterestTap: _onPointOfInterestTapped,
              onCameraMove: (position) =>
                  setState(() => _camera.updatePosition(position)),
            ),
            Positioned.fill(
              child: MapOverlayLayout(
                searchBar: PlaceSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  availability: availability,
                  isSearching: state.isSearching,
                  onSubmitted: _submitSearch,
                  onCleared: _clearSearch,
                  onUnavailable: _onSearchUnavailable,
                ),
                mapControlsHeight: MapControls.height,
                mapControls: MapControls(
                  latitude: _camera.target.latitude,
                  zoom: _camera.zoom,
                  isLoading: _locationController.isLoading,
                  onCurrentLocationPressed: () =>
                      _moveToCurrentLocation(showErrors: true),
                ),
                resultsPanel: state.searchStatus == MapSearchStatus.idle
                    ? null
                    : PlaceSearchResultsPanel(
                        status: state.searchStatus,
                        results: state.searchResults,
                        distanceOrigin: state.searchResultsOrigin,
                        error: state.searchError,
                        canRetry: state.canRetrySearch,
                        expanded: _resultsExpanded,
                        expandedHeight:
                            constraints.maxHeight * _expandedPanelFraction,
                        selectedPlaceId: selected?.id,
                        onToggleExpanded: () => setState(
                          () => _resultsExpanded = !_resultsExpanded,
                        ),
                        onSelect: _selectSearchResult,
                        onRetry: _retrySearch,
                      ),
                detailCard: selected == null
                    ? null
                    : PlacePickerCard(
                        place: PlacePickerScreen.toScheduledPlace(selected),
                        onSelect: () => _select(selected),
                        onClose: notifier.clearSelectedPlace,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
