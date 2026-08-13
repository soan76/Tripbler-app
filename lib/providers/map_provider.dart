import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

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
  String? _tapSelectedPlaceId;

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

    if (selectedPlace != null && _tapSelectedPlaceId != null) {
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
    _tapSelectedPlaceId = null;
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

  // 사용자가 지도 위를 탭했을 때 호출됨.
  // 핵심:
  // 1. 마커 위치는 백엔드가 반환한 장소 좌표가 아니라 사용자가 실제로 탭한 좌표를 사용함.
  // 2. 백엔드 nearest 결과는 장소 이름/주소/카테고리 같은 정보 참고용으로만 사용함.
  // 3. nearest 결과가 탭 좌표와 너무 멀면 잘못 선택된 장소로 보고 버림.
  Future<void> selectNearestPlaceByLatLng({
    required double latitude,
    required double longitude,
  }) async {
    _status = MapPlaceStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final nearestPlace = await _placeApiService.fetchNearestPlace(
        latitude: latitude,
        longitude: longitude,
        radius: 40,
      );
      debugPrint('nearestPlace id: ${nearestPlace?.id}');
      debugPrint('nearestPlace name: ${nearestPlace?.name}');

      PlaceModel selectedPlace;

      if (nearestPlace == null) {
        // 백엔드에서 주변 장소를 찾지 못한 경우에도
        // 사용자가 탭한 위치 자체를 선택 위치로 표시함.
        selectedPlace = PlaceModel(
          id: 'tap_${latitude}_$longitude',
          name: '선택한 위치',
          latitude: latitude,
          longitude: longitude,
          address:
              '위도 ${latitude.toStringAsFixed(6)}, 경도 ${longitude.toStringAsFixed(6)}',
          rating: null,
          category: 'selected_location',
          openNow: null,
        );
      } else {
        final distanceFromTap = Geolocator.distanceBetween(
          latitude,
          longitude,
          nearestPlace.latitude,
          nearestPlace.longitude,
        );

        // nearest 결과가 탭한 좌표에서 40m보다 멀면
        // 사용자가 누른 위치와 다른 장소가 선택된 것으로 판단함.
        if (distanceFromTap > 40) {
          selectedPlace = PlaceModel(
            id: 'tap_${latitude}_$longitude',
            name: '선택한 위치',
            latitude: latitude,
            longitude: longitude,
            address:
                '위도 ${latitude.toStringAsFixed(6)}, 경도 ${longitude.toStringAsFixed(6)}',
            rating: null,
            category: 'selected_location',
            openNow: null,
          );
        } else {
          // nearest 결과가 탭 좌표와 충분히 가까운 경우에만
          // 장소 정보는 nearestPlace를 사용하되,
          // 마커 좌표는 사용자가 실제로 탭한 좌표를 사용함.
          selectedPlace = PlaceModel(
            id: nearestPlace.id,
            name: nearestPlace.name,
            latitude: latitude,
            longitude: longitude,
            address: nearestPlace.address,
            rating: nearestPlace.rating,
            category: nearestPlace.category,
            openNow: nearestPlace.openNow,
          );
        }
      }

      // 기존 선택 마커를 제거하고 새로 탭한 위치 마커만 추가함.
      // 이렇게 해야 예전에 잘못 찍힌 마커가 계속 남지 않음.
      _places = _places.where((place) => !place.id.startsWith('tap_')).toList();

      _selectedPlace = selectedPlace;
      _tapSelectedPlaceId = selectedPlace.id;

      _status = MapPlaceStatus.success;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('지도 탭 장소 선택 실패: $error');
      debugPrint('$stackTrace');

      // API가 실패해도 사용자가 탭한 좌표에는 마커를 표시함.
      // 서버 오류 때문에 지도 클릭 자체가 무반응처럼 보이지 않도록 하기 위함.
      final selectedPlace = PlaceModel(
        id: 'tap_${latitude}_$longitude',
        name: '선택한 위치',
        latitude: latitude,
        longitude: longitude,
        address:
            '위도 ${latitude.toStringAsFixed(6)}, 경도 ${longitude.toStringAsFixed(6)}',
        rating: null,
        category: 'selected_location',
        openNow: null,
      );

      // API가 실패해도 사용자가 탭한 좌표에는 선택 마커를 표시함.
      // 단, 이 선택 마커는 _places에 누적하지 않고 _selectedPlace로만 관리함.
      _places = _places.where((place) => !place.id.startsWith('tap_')).toList();

      _selectedPlace = selectedPlace;
      _tapSelectedPlaceId = selectedPlace.id;

      _errorMessage = error.toString();
      _status = MapPlaceStatus.failure;
      notifyListeners();
    }
  }

  // 현재 선택된 장소의 placeId를 기준으로 상세 정보를 다시 조회함.
  // 상세 조회 성공 시 selectedPlace를 더 정확한 상세 정보로 교체함.
  Future<void> loadSelectedPlaceDetails() async {
    final selectedPlace = _selectedPlace;

    if (selectedPlace == null) {
      return;
    }

    // 지도 탭으로 생성한 임시 위치는 실제 Google placeId가 아닐 수 있으므로 상세 조회하지 않음.
    if (selectedPlace.id.startsWith('tap_')) {
      _errorMessage = '선택한 위치는 상세 정보를 조회할 수 없습니다.';
      notifyListeners();
      return;
    }

    _status = MapPlaceStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final detailPlace = await _placeApiService.fetchPlaceDetails(
        placeId: selectedPlace.id,
      );

      // 상세 정보로 selectedPlace 갱신
      _selectedPlace = detailPlace;

      // 기존 places 목록에 같은 id가 있으면 상세 정보로 교체
      _places = _places.map((place) {
        if (place.id == detailPlace.id) {
          return detailPlace;
        }

        return place;
      }).toList();

      _status = MapPlaceStatus.success;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('장소 상세 조회 실패: $error');
      debugPrint('$stackTrace');

      _errorMessage = error.toString();
      _status = MapPlaceStatus.failure;
      notifyListeners();
    }
  }

  void selectPlace(PlaceModel place) {
    _selectedPlace = place;
    _tapSelectedPlaceId = null;
    notifyListeners();
  }

  void clearSelectedPlace() {
    if (_selectedPlace == null) {
      return;
    }

    _selectedPlace = null;
    _tapSelectedPlaceId = null;

    // _places에 들어갔던 tap_ 마커가 남아 있을 수 있으므로 정리함.
    _places = _places.where((place) => !place.id.startsWith('tap_')).toList();

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
