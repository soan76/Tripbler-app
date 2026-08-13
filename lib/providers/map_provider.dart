import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/place_model.dart';
import '../services/place_api_service.dart';

enum MapPlaceStatus { idle, loading, success, failure }

class MapProvider extends ChangeNotifier {
  MapProvider({PlaceApiService? placeApiService})
    : _placeApiService = placeApiService ?? PlaceApiService();

  final PlaceApiService _placeApiService;

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
      markers.add(
        Marker(
          markerId: MarkerId(place.id),
          position: LatLng(
            place.latitude,
            place.longitude,
          ),
          infoWindow: InfoWindow(
            title: place.name,
            snippet: place.address,
          ),
          onTap: () {
            selectPlace(place);
          },
        ),
      );
    }

    // 지도 탭으로 선택한 장소 전용 마커
    final selectedPlace = _selectedPlace;

    if (selectedPlace != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected_place'),
          position: LatLng(selectedPlace.latitude, selectedPlace.longitude),
          infoWindow: InfoWindow(
            title: selectedPlace.name,
            snippet: selectedPlace.address,
          ),
          onTap: () {
            selectPlace(selectedPlace);
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
      _errorMessage = error.toString();
      _status = MapPlaceStatus.failure;
      notifyListeners();
    }
  }

  // 사용자가 지도 위 기본 POI 아이콘 근처를 탭했을 때 호출됨.
  // 탭한 좌표 주변에서 가장 가까운 장소를 백엔드에 조회하는 방식.
  Future<void> selectNearestPlaceByLatLng({
    required double latitude,
    required double longitude,
  }) async {
    _status = MapPlaceStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('지도 탭 좌표: latitude=$latitude, longitude=$longitude');
      final nearestPlace = await _placeApiService.fetchNearestPlace(
        latitude: latitude,
        longitude: longitude,
        radius: 40,
      );

      // 탭한 위치 근처에 장소가 없으면 기존 선택만 해제
      if (nearestPlace == null) {
        _selectedPlace = null;
        _status = MapPlaceStatus.success;
        notifyListeners();
        return;
      }

      _selectedPlace = nearestPlace;

      _status = MapPlaceStatus.success;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('지도 탭 장소 선택 실패: $error');
      debugPrint('$stackTrace');

      _errorMessage = error.toString();
      _status = MapPlaceStatus.failure;
      notifyListeners();
    }
  }

  void selectPlace(PlaceModel place) {
    _selectedPlace = place;
    notifyListeners();
  }

  void clearSelectedPlace() {
    if (_selectedPlace == null) {
      return;
    }

    _selectedPlace = null;
    notifyListeners();
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
    _placeApiService.dispose();
    super.dispose();
  }
}
