import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, ProviderSubscription;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/providers/map/map_provider.dart';

/// 테스트 컨테이너의 지도 상태를 읽고 바꾼다. 상태가 바뀔 때마다 리스너에 알린다.
class MapHandle extends ChangeNotifier {
  MapHandle(this.container) {
    _subscription = container.listen(mapProvider, (_, _) => notifyListeners());
  }

  final ProviderContainer container;
  late final ProviderSubscription<MapState> _subscription;

  MapNotifier get _notifier => container.read(mapProvider.notifier);
  MapState get state => container.read(mapProvider);

  MapSearchStatus get searchStatus => state.searchStatus;
  List<PlaceModel> get searchResults => state.searchResults;
  LatLng? get searchResultsOrigin => state.searchResultsOrigin;
  MapSearchError? get searchError => state.searchError;
  String? get lastSearchQuery => state.lastSearchQuery;
  bool get isSearching => state.isSearching;
  bool get hasSearchResults => state.hasSearchResults;
  bool get canRetrySearch => state.canRetrySearch;
  bool get hasSessionExpiryNotice => state.hasSessionExpiryNotice;
  PlaceDetailsStatus get detailsStatus => state.detailsStatus;
  String? get detailsErrorMessage => state.detailsErrorMessage;
  bool get selectedPlaceDetailsLoaded => state.selectedPlaceDetailsLoaded;
  bool get selectedPlaceDetailsStale => state.selectedPlaceDetailsStale;
  DateTime? get selectedPlaceDetailsFetchedAt =>
      state.selectedPlaceDetailsFetchedAt;
  LatLngBounds? get searchResultBounds => state.searchResultBounds;
  PlaceModel? get selectedPlace => state.selectedPlace;
  LatLng? get selectedPlaceDistanceOrigin => state.selectedPlaceDistanceOrigin;
  bool get isSelectedPlaceFromMap => state.isSelectedPlaceFromMap;
  Set<Marker> get markers => state.markers;

  DateTime now() => _notifier.now();

  Future<void> search(String query, {LatLng? center, LatLng? userLocation}) =>
      _notifier.search(query, center: center, userLocation: userLocation);

  Future<void> retrySearch() => _notifier.retrySearch();

  void consumeSessionExpiryNotice() => _notifier.consumeSessionExpiryNotice();

  void selectSearchResult(PlaceModel place) =>
      _notifier.selectSearchResult(place);

  void selectMapPlace(PlaceModel place, {LatLng? userLocation}) =>
      _notifier.selectMapPlace(place, userLocation: userLocation);

  void clearSearch() => _notifier.clearSearch();

  Future<void> loadSelectedPlaceDetails() =>
      _notifier.loadSelectedPlaceDetails();

  void clearSelectedPlace() => _notifier.clearSelectedPlace();

  /// 지도 상태가 든 컨테이너를 폐기한다(기존 `MapProvider.dispose`에 해당).
  @override
  void dispose() {
    _subscription.close();
    container.dispose();
    super.dispose();
  }
}
