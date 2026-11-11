import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/providers/map_provider.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';
import 'package:tripbler/services/place_api_service.dart';
import 'package:tripbler/widgets/map/place_detail_card.dart';

PlaceModel _place(
  String id, {
  double? latitude = 37.5,
  double? longitude = 126.9,
  double? rating,
  bool? openNow,
}) {
  return PlaceModel(
    id: id,
    name: '장소 $id',
    latitude: latitude,
    longitude: longitude,
    address: '주소 $id',
    rating: rating,
    category: 'tourist_attraction',
    openNow: openNow,
  );
}

class FakeSearchCall {
  FakeSearchCall(this.query, this.latitude, this.longitude, this.header);

  final String query;
  final double? latitude;
  final double? longitude;
  final String header;
  final Completer<List<PlaceModel>> completer = Completer<List<PlaceModel>>();
}

class FakePlaceApiService extends PlaceApiService {
  final List<FakeSearchCall> searchCalls = <FakeSearchCall>[];
  final List<String> detailCalls = <String>[];
  final List<Completer<PlaceModel>> detailCompleters =
      <Completer<PlaceModel>>[];
  List<PlaceModel> nearbyResult = const [];
  Object? nearbyError;
  final List<Completer<PlaceModel?>> nearestCompleters =
      <Completer<PlaceModel?>>[];

  @override
  Future<List<PlaceModel>> searchPlaces({
    required String query,
    double? latitude,
    double? longitude,
    required String authorizationHeader,
  }) {
    final call = FakeSearchCall(
      query,
      latitude,
      longitude,
      authorizationHeader,
    );
    searchCalls.add(call);
    return call.completer.future;
  }

  @override
  Future<PlaceModel> fetchPlaceDetails({required String placeId}) {
    detailCalls.add(placeId);
    final completer = Completer<PlaceModel>();
    detailCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<List<PlaceModel>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    String type = 'restaurant',
    int radius = 1000,
  }) async {
    final error = nearbyError;

    if (error != null) {
      throw error;
    }

    return nearbyResult;
  }

  @override
  Future<PlaceModel?> fetchNearestPlace({
    required double latitude,
    required double longitude,
    int radius = 40,
  }) {
    final completer = Completer<PlaceModel?>();
    nearestCompleters.add(completer);
    return completer.future;
  }
}

/// AuthProvider.runAuthorizedRequest 대역.
class FakeAuthorizedRunner {
  Object? error;

  Future<T> run<T>(Future<T> Function(String authorizationHeader) request) {
    final currentError = error;

    if (currentError != null) {
      return Future<T>.error(currentError);
    }

    return request('Bearer test-access-token');
  }
}

class FakeAuthState extends ChangeNotifier {
  bool isAuthenticated = true;

  void signOut() {
    isAuthenticated = false;
    notifyListeners();
  }

  void signIn() {
    isAuthenticated = true;
    notifyListeners();
  }
}

/// 마이크로태스크를 비워 await 뒤의 상태 갱신을 반영한다.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakePlaceApiService service;
  late FakeAuthorizedRunner runner;
  late FakeAuthState authState;
  late MapProvider provider;
  late bool disposedInTest;
  late DateTime clock;

  const center = LatLng(37.5665, 126.978);

  setUp(() {
    service = FakePlaceApiService();
    runner = FakeAuthorizedRunner();
    authState = FakeAuthState();
    clock = DateTime(2026, 1, 1, 12);
    provider = MapProvider(
      authorizedRequest: runner.run,
      placeApiService: service,
      authState: authState,
      isAuthenticated: () => authState.isAuthenticated,
      now: () => clock,
    );
    disposedInTest = false;
  });

  tearDown(() {
    if (!disposedInTest) {
      provider.dispose();
    }
    authState.dispose();
  });

  /// 검색을 시작하고 [results]로 성공시킨다.
  Future<void> searchAndSucceed(
    String query,
    List<PlaceModel> results, {
    LatLng? at,
  }) async {
    final pending = provider.search(query, center: at);
    service.searchCalls.last.completer.complete(results);
    await pending;
  }

  /// 검색을 시작하고 [error]로 실패시킨다.
  Future<void> searchAndFail(String query, Object error, {LatLng? at}) async {
    final pending = provider.search(query, center: at);
    service.searchCalls.last.completer.completeError(error);
    await pending;
  }

  group('검색 실행', () {
    test('정리한 검색어와 지도 중심을 토큰과 함께 보내고 결과를 반영한다', () async {
      final pending = provider.search('  경복궁 ', center: center);

      expect(provider.searchStatus, MapSearchStatus.loading);
      expect(provider.isSearching, isTrue);

      final call = service.searchCalls.single;
      expect(call.query, '경복궁');
      expect(call.latitude, 37.5665);
      expect(call.longitude, 126.978);
      expect(call.header, 'Bearer test-access-token');

      call.completer.complete([_place('a'), _place('b')]);
      await pending;

      expect(provider.searchStatus, MapSearchStatus.success);
      expect(provider.searchResults.map((p) => p.id), ['a', 'b']);
      expect(provider.searchError, isNull);
      expect(provider.lastSearchQuery, '경복궁');
    });

    test('지도 중심이 없으면 좌표 없이 보낸다', () async {
      await searchAndSucceed('경복궁', const []);

      expect(service.searchCalls.single.latitude, isNull);
      expect(service.searchCalls.single.longitude, isNull);
    });

    test('정리 후 비었거나 100자를 넘으면 호출하지 않는다', () async {
      await provider.search('   ');
      await provider.search('\u00A0\u200B');
      await provider.search('가' * 101);

      expect(service.searchCalls, isEmpty);
      expect(provider.searchStatus, MapSearchStatus.idle);
    });

    test('결과 0건은 오류가 아닌 성공 + 빈 목록이다', () async {
      await searchAndSucceed('없는장소', const []);

      expect(provider.searchStatus, MapSearchStatus.success);
      expect(provider.searchResults, isEmpty);
      expect(provider.hasSearchResults, isFalse);
      expect(provider.searchError, isNull);
    });
  });

  group('검색 실패 종류', () {
    final cases = <String, (Object, MapSearchErrorType)>{
      '400': (
        const ApiException(
          statusCode: 400,
          code: 'INVALID_REQUEST',
          message: '검색어 오류',
        ),
        MapSearchErrorType.invalidQuery,
      ),
      '503': (
        const ApiException(
          statusCode: 503,
          code: 'PLACES_PROVIDER_UNAVAILABLE',
          message: '장애',
        ),
        MapSearchErrorType.providerUnavailable,
      ),
      '네트워크': (
        const ApiException(message: '연결 실패'),
        MapSearchErrorType.network,
      ),
      '500': (
        const ApiException(statusCode: 500, message: '서버 오류'),
        MapSearchErrorType.unknown,
      ),
      'ApiException이 아닌 오류': (StateError('예상 밖'), MapSearchErrorType.unknown),
    };

    cases.forEach((name, value) {
      final (error, type) = value;

      test('$name → $type', () async {
        await searchAndFail('경복궁', error);

        expect(provider.searchStatus, MapSearchStatus.failure);
        expect(provider.searchError?.type, type);
        expect(provider.searchError?.message, isNotEmpty);
        expect(provider.canRetrySearch, isTrue);
      });
    });

    test('ApiException 문구를 그대로 쓴다', () async {
      await searchAndFail(
        '경복궁',
        const ApiException(
          statusCode: 400,
          message: '검색어는 공백을 제외하고 1~100자여야 합니다.',
        ),
      );

      expect(provider.searchError?.message, '검색어는 공백을 제외하고 1~100자여야 합니다.');
    });
  });

  group('실패 시 이전 결과', () {
    test('같은 조건(검색어·중심 좌표)이 실패하면 이전 결과를 유지한다', () async {
      await searchAndSucceed('경복궁', [_place('a')], at: center);
      await searchAndFail(
        '경복궁',
        const ApiException(message: '연결 실패'),
        at: center,
      );

      expect(provider.searchStatus, MapSearchStatus.failure);
      expect(provider.searchResults.map((p) => p.id), ['a']);
    });

    test('검색어가 다르면 결과를 비운다', () async {
      await searchAndSucceed('경복궁', [_place('a')], at: center);
      await searchAndFail(
        '덕수궁',
        const ApiException(message: '연결 실패'),
        at: center,
      );

      expect(provider.searchResults, isEmpty);
    });

    test('중심 좌표가 다르면 결과를 비운다', () async {
      await searchAndSucceed('경복궁', [_place('a')], at: center);
      await searchAndFail(
        '경복궁',
        const ApiException(message: '연결 실패'),
        at: const LatLng(35.1, 129.0),
      );

      expect(provider.searchResults, isEmpty);
    });

    test('retrySearch는 실패한 요청을 같은 조건으로 다시 보낸다', () async {
      await searchAndFail(
        '덕수궁',
        const ApiException(message: '연결 실패'),
        at: center,
      );

      final pending = provider.retrySearch();
      final retry = service.searchCalls.last;

      expect(service.searchCalls, hasLength(2));
      expect(retry.query, '덕수궁');
      expect(retry.latitude, center.latitude);
      expect(retry.longitude, center.longitude);

      retry.completer.complete([_place('d')]);
      await pending;

      expect(provider.searchStatus, MapSearchStatus.success);
      expect(provider.searchResults.map((p) => p.id), ['d']);
      expect(provider.canRetrySearch, isFalse);
    });

    test('실패한 요청이 없으면 retrySearch는 아무것도 하지 않는다', () async {
      await provider.retrySearch();

      expect(service.searchCalls, isEmpty);
    });
  });

  group('늦게 온 응답', () {
    test('이전 검색의 응답이 나중에 와도 무시한다', () async {
      final first = provider.search('경복궁');
      final second = provider.search('덕수궁');

      service.searchCalls[1].completer.complete([_place('second')]);
      await second;
      service.searchCalls[0].completer.complete([_place('first')]);
      await first;

      expect(provider.searchResults.map((p) => p.id), ['second']);
      expect(provider.lastSearchQuery, '덕수궁');
    });

    test('이전 검색의 실패가 나중에 와도 무시한다', () async {
      final first = provider.search('경복궁');
      final second = provider.search('덕수궁');

      service.searchCalls[1].completer.complete([_place('second')]);
      await second;
      service.searchCalls[0].completer.completeError(
        const ApiException(statusCode: 503, message: '장애'),
      );
      await first;

      expect(provider.searchStatus, MapSearchStatus.success);
      expect(provider.searchError, isNull);
    });

    test('clearSearch 뒤에 온 응답은 무시한다', () async {
      final pending = provider.search('경복궁');
      provider.clearSearch();

      service.searchCalls.single.completer.complete([_place('a')]);
      await pending;

      expect(provider.searchStatus, MapSearchStatus.idle);
      expect(provider.searchResults, isEmpty);
    });

    test('dispose 뒤에 온 응답은 예외 없이 무시한다', () async {
      final pending = provider.search('경복궁');
      provider.dispose();
      disposedInTest = true;

      service.searchCalls.single.completer.complete([_place('a')]);

      await expectLater(pending, completes);
    });
  });

  test('세션이 만료되면 오류 문구 없이 검색 상태를 비운다', () async {
    await searchAndSucceed('경복궁', [_place('a')]);
    runner.error = const SessionExpiredException();

    await provider.search('덕수궁');

    expect(provider.searchStatus, MapSearchStatus.idle);
    expect(provider.searchResults, isEmpty);
    expect(provider.searchError, isNull);
    expect(provider.canRetrySearch, isFalse);
  });

  test('세션이 바뀌어 중단된 검색은 화면의 결과를 그대로 두고 로딩만 거둔다', () async {
    await searchAndSucceed('경복궁', [_place('a')]);
    runner.error = const SessionChangedException();

    await provider.search('덕수궁');

    expect(provider.searchStatus, MapSearchStatus.success);
    expect(provider.searchResults.map((p) => p.id), ['a']);
    expect(provider.searchError, isNull);
    expect(provider.canRetrySearch, isFalse);
  });

  test('결과가 없던 상태에서 세션 변경으로 중단되면 idle로 돌아간다', () async {
    runner.error = const SessionChangedException();

    await provider.search('경복궁');

    expect(provider.searchStatus, MapSearchStatus.idle);
    expect(provider.searchError, isNull);
  });

  group('선택과 해제', () {
    test('결과를 고르면 선택한 장소가 되고, 새 검색은 선택을 해제한다', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);

      provider.selectSearchResult(provider.searchResults[1]);
      expect(provider.selectedPlace?.id, 'b');

      final pending = provider.search('덕수궁');
      expect(provider.selectedPlace, isNull);

      service.searchCalls.last.completer.complete(const []);
      await pending;
    });

    test('카드를 닫아도 검색 결과는 유지한다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);

      provider.clearSelectedPlace();

      expect(provider.selectedPlace, isNull);
      expect(provider.searchResults.map((p) => p.id), ['a']);
    });

    test('clearSearch는 검색어·결과·선택·오류를 모두 지운다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);

      provider.clearSearch();

      expect(provider.searchStatus, MapSearchStatus.idle);
      expect(provider.searchResults, isEmpty);
      expect(provider.lastSearchQuery, isNull);
      expect(provider.selectedPlace, isNull);
      expect(provider.canRetrySearch, isFalse);
    });
  });

  group('마커와 범위', () {
    test('좌표가 있는 결과만 마커로 만들고 선택된 마커를 위로 올린다', () async {
      await searchAndSucceed('경복궁', [
        _place('a', latitude: 37.1, longitude: 126.1),
        _place('b', latitude: 37.2, longitude: 126.2),
        _place('no-coords', latitude: null, longitude: null),
      ]);

      provider.selectSearchResult(provider.searchResults[1]);

      final markers = {
        for (final marker in provider.markers) marker.markerId.value: marker,
      };

      expect(markers.keys, containsAll(['search_a', 'search_b']));
      expect(markers.containsKey('search_no-coords'), isFalse);
      expect(markers['search_b']!.zIndexInt, 2);
      expect(markers['search_a']!.zIndexInt, 1);
    });

    test('마커를 탭하면 그 결과를 선택한다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);

      final marker = provider.markers.firstWhere(
        (m) => m.markerId.value == 'search_a',
      );
      marker.onTap!();

      expect(provider.selectedPlace?.id, 'a');
    });

    test('searchResultBounds는 좌표가 있는 결과를 모두 감싼다', () async {
      await searchAndSucceed('경복궁', [
        _place('a', latitude: 37.1, longitude: 127.0),
        _place('b', latitude: 37.6, longitude: 126.5),
        _place('no-coords', latitude: null, longitude: null),
      ]);

      final bounds = provider.searchResultBounds!;

      expect(bounds.southwest, const LatLng(37.1, 126.5));
      expect(bounds.northeast, const LatLng(37.6, 127.0));
    });

    test('날짜변경선을 사이에 둔 두 결과는 짧은 구간을 west > east로 감싼다', () async {
      await searchAndSucceed('피지', [
        _place('a', latitude: -17.0, longitude: 179.9),
        _place('b', latitude: -16.0, longitude: -179.9),
        _place('no-coords', latitude: null, longitude: null),
      ]);

      final bounds = provider.searchResultBounds!;

      expect(bounds.southwest, const LatLng(-17.0, 179.9));
      expect(bounds.northeast, const LatLng(-16.0, -179.9));
    });

    test('세 결과 이상이면 날짜변경선 쪽 짧은 구간을 고른다', () async {
      await searchAndSucceed('태평양', [
        _place('a', latitude: 10.0, longitude: 170.0),
        _place('b', latitude: 20.0, longitude: -175.0),
        _place('c', latitude: 15.0, longitude: 178.0),
      ]);

      final bounds = provider.searchResultBounds!;

      expect(bounds.southwest, const LatLng(10.0, 170.0));
      expect(bounds.northeast, const LatLng(20.0, -175.0));
    });

    test('경도 간격이 180으로 같으면 날짜변경선을 넘지 않는 구간을 고른다', () async {
      await searchAndSucceed('적도', [
        _place('a', latitude: 0.0, longitude: -90.0),
        _place('b', latitude: 1.0, longitude: 90.0),
      ]);

      final bounds = provider.searchResultBounds!;

      expect(bounds.southwest, const LatLng(0.0, -90.0));
      expect(bounds.northeast, const LatLng(1.0, 90.0));
    });

    test('결과가 하나면 남서와 북동이 같다', () async {
      await searchAndSucceed('경복궁', [
        _place('a', latitude: 37.5, longitude: 127.0),
      ]);

      final bounds = provider.searchResultBounds!;

      expect(bounds.southwest, bounds.northeast);
    });

    test('좌표가 있는 결과가 없으면 searchResultBounds는 null', () async {
      await searchAndSucceed('경복궁', [
        _place('no-coords', latitude: null, longitude: null),
      ]);

      expect(provider.searchResultBounds, isNull);
    });
  });

  group('상세 조회', () {
    test('상세 결과로 선택 장소와 검색 결과 항목을 함께 갱신한다', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);

      final pending = provider.loadSelectedPlaceDetails();
      expect(provider.detailsStatus, PlaceDetailsStatus.loading);

      service.detailCompleters.single.complete(
        _place('a', rating: 4.6, openNow: true),
      );
      await pending;

      expect(provider.detailsStatus, PlaceDetailsStatus.idle);
      expect(provider.selectedPlace?.rating, 4.6);
      expect(provider.searchResults.first.rating, 4.6);
      expect(provider.searchResults.first.openNow, isTrue);
    });

    test('같은 장소를 다시 열면 기억해 둔 상세 결과를 쓰고 다시 조회하지 않는다', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);
      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await pending;

      // 새 검색으로 rating 없는 같은 장소가 다시 나와도 상세 결과를 재사용한다.
      await searchAndSucceed('경복궁 근처', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      expect(provider.selectedPlace?.rating, 4.6);

      await provider.loadSelectedPlaceDetails();

      expect(service.detailCalls, ['a']);
      expect(provider.selectedPlace?.rating, 4.6);
    });

    test('상세 결과는 최대 50개까지 기억하고 오래된 것부터 지운다', () async {
      final places = [
        for (var i = 0; i <= MapProvider.maxCachedPlaceDetails; i++)
          _place('p$i'),
      ];
      await searchAndSucceed('많은 장소', places);

      for (final place in places) {
        provider.selectSearchResult(place);
        final pending = provider.loadSelectedPlaceDetails();
        service.detailCompleters.last.complete(_place(place.id, rating: 4.0));
        await pending;
      }

      final callsBefore = service.detailCalls.length;

      // 가장 최근 것은 기억되어 다시 조회하지 않는다.
      provider.selectSearchResult(places.last);
      await provider.loadSelectedPlaceDetails();
      expect(service.detailCalls.length, callsBefore);

      // 가장 오래된 것은 지워져 다시 조회한다.
      provider.selectSearchResult(places.first);
      unawaited(provider.loadSelectedPlaceDetails());
      expect(service.detailCalls.length, callsBefore + 1);
      service.detailCompleters.last.complete(_place('p0', rating: 4.0));
      await _flush();
    });

    test('상세 조회가 실패해도 검색 결과는 유지하고 카드용 오류를 남긴다', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);

      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.single.completeError(
        const PlaceApiException(message: '장소 상세 정보를 불러오지 못했습니다.'),
      );
      await pending;

      expect(provider.detailsStatus, PlaceDetailsStatus.failure);
      expect(provider.detailsErrorMessage, '장소 상세 정보를 불러오지 못했습니다.');
      expect(provider.searchStatus, MapSearchStatus.success);
      expect(provider.searchResults.map((p) => p.id), ['a', 'b']);
      expect(provider.selectedPlace?.id, 'a');
    });

    test('선택을 바꾼 뒤 도착한 이전 상세 응답은 무시한다', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);
      final pending = provider.loadSelectedPlaceDetails();

      provider.selectSearchResult(provider.searchResults[1]);
      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await pending;

      expect(provider.selectedPlace?.id, 'b');
      expect(provider.selectedPlace?.rating, isNull);
      expect(provider.detailsStatus, PlaceDetailsStatus.idle);
    });

    test('카드를 닫은 뒤 도착한 상세 응답은 무시한다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      final pending = provider.loadSelectedPlaceDetails();

      provider.clearSelectedPlace();
      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await pending;

      expect(provider.selectedPlace, isNull);
      expect(provider.searchResults.single.rating, isNull);
    });

    test('조회 중에는 같은 요청을 다시 보내지 않는다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);

      final first = provider.loadSelectedPlaceDetails();
      await provider.loadSelectedPlaceDetails();

      expect(service.detailCalls, ['a']);
      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await first;
      expect(provider.selectedPlace?.rating, 4.6);
    });
  });

  group('상세 조회 완료 여부', () {
    test('조회 전·조회 중·실패는 미완료, 성공하면 완료', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      expect(provider.selectedPlaceDetailsLoaded, isFalse);

      provider.selectSearchResult(provider.searchResults.single);
      expect(provider.selectedPlaceDetailsLoaded, isFalse);

      final failed = provider.loadSelectedPlaceDetails();
      expect(provider.selectedPlaceDetailsLoaded, isFalse);
      service.detailCompleters.single.completeError(
        const PlaceApiException(message: '실패'),
      );
      await failed;
      expect(provider.selectedPlaceDetailsLoaded, isFalse);

      final retried = provider.loadSelectedPlaceDetails();
      service.detailCompleters.last.complete(_place('a', rating: 4.6));
      await retried;
      expect(provider.selectedPlaceDetailsLoaded, isTrue);
    });

    test('평점·영업 여부가 모두 없는 성공 응답도 완료로 본다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);

      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.single.complete(_place('a'));
      await pending;

      expect(provider.selectedPlace?.rating, isNull);
      expect(provider.selectedPlace?.openNow, isNull);
      expect(provider.selectedPlaceDetailsLoaded, isTrue);
    });

    test('기억해 둔 결과가 있는 장소를 다시 고르면 바로 완료', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);
      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.single.complete(_place('a'));
      await pending;

      provider.selectSearchResult(provider.searchResults[1]);
      expect(provider.selectedPlaceDetailsLoaded, isFalse);

      provider.selectSearchResult(provider.searchResults.first);
      expect(provider.selectedPlaceDetailsLoaded, isTrue);
      expect(service.detailCalls, ['a']);
    });

    test('A 조회를 마친 뒤 B를 고르면 B는 미완료', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);
      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await pending;
      expect(provider.selectedPlaceDetailsLoaded, isTrue);

      provider.selectSearchResult(provider.searchResults[1]);

      expect(provider.selectedPlaceDetailsLoaded, isFalse);
      expect(provider.detailsStatus, PlaceDetailsStatus.idle);
    });

    test('A 조회 중 B를 고르면 늦은 A 응답이 B를 완료로 만들지 않는다', () async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);
      final pending = provider.loadSelectedPlaceDetails();

      provider.selectSearchResult(provider.searchResults[1]);
      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await pending;

      expect(provider.selectedPlace?.id, 'b');
      expect(provider.selectedPlaceDetailsLoaded, isFalse);

      // B는 바로 조회할 수 있다(A의 조회 중 상태가 막지 않음).
      unawaited(provider.loadSelectedPlaceDetails());
      expect(service.detailCalls, ['a', 'b']);
      service.detailCompleters.last.complete(_place('b'));
      await _flush();
      expect(provider.selectedPlaceDetailsLoaded, isTrue);
    });

    test('주변 장소에서 고를 때도 기억해 둔 상세 결과를 쓴다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.single.complete(
        _place('a', rating: 4.6, openNow: true),
      );
      await pending;

      // 상세 값이 없는 같은 장소를 주변 장소 경로로 고른다.
      provider.selectPlace(_place('a'));

      expect(provider.selectedPlaceDetailsLoaded, isTrue);
      expect(provider.selectedPlace?.rating, 4.6);
      expect(provider.selectedPlace?.openNow, isTrue);
    });

    test('30분이 지나면 값은 남기고 오래된 정보가 된다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      final fetchedAt = clock;
      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await pending;

      expect(provider.selectedPlaceDetailsStale, isFalse);
      expect(provider.selectedPlaceDetailsFetchedAt, fetchedAt);

      clock = clock.add(
        MapProvider.placeDetailsCacheTtl - const Duration(seconds: 1),
      );
      expect(provider.selectedPlaceDetailsStale, isFalse);

      clock = clock.add(const Duration(seconds: 1));
      expect(provider.selectedPlaceDetailsLoaded, isTrue);
      expect(provider.selectedPlaceDetailsStale, isTrue);
      expect(provider.selectedPlaceDetailsFetchedAt, fetchedAt);
      expect(provider.selectedPlace?.rating, 4.6);
    });
  });

  group('선택이 바뀔 때 상세 상태 초기화', () {
    test('상세 로딩 중 주변 장소를 불러오면 idle이 된다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      final details = provider.loadSelectedPlaceDetails();
      expect(provider.detailsStatus, PlaceDetailsStatus.loading);

      service.nearbyResult = [_place('n1')];
      await provider.loadNearbyPlaces(latitude: 37.5, longitude: 126.9);

      expect(provider.selectedPlace, isNull);
      expect(provider.detailsStatus, PlaceDetailsStatus.idle);

      service.detailCompleters.single.complete(_place('a', rating: 4.6));
      await details;

      expect(provider.selectedPlace, isNull);
      expect(provider.detailsStatus, PlaceDetailsStatus.idle);
    });
  });

  group('비로그인 검색', () {
    test('로그인하지 않았으면 서버에 검색을 보내지 않는다', () async {
      authState.isAuthenticated = false;

      await provider.search('경복궁');

      expect(service.searchCalls, isEmpty);
      expect(provider.searchStatus, MapSearchStatus.idle);
    });
  });

  group('세션 만료 안내', () {
    /// 검색 중 만료: AuthProvider가 로그인 상태를 먼저 해제(알림)한 뒤 만료 예외가 도착한다.
    test('검색 중 만료되면 검색 상태가 먼저 비워져도 안내를 정확히 한 번 남긴다', () async {
      var notified = 0;
      provider.addListener(() => notified++);

      final pending = provider.search('경복궁');
      authState.signOut();
      expect(provider.searchStatus, MapSearchStatus.idle);

      service.searchCalls.single.completer.completeError(
        const SessionExpiredException(1),
      );
      await pending;

      expect(provider.hasSessionExpiryNotice, isTrue);

      final notifiedBefore = notified;
      provider.consumeSessionExpiryNotice();
      expect(provider.hasSessionExpiryNotice, isFalse);
      expect(notified, notifiedBefore + 1);

      // 소비한 뒤에는 다시 켜지지 않는다.
      provider.consumeSessionExpiryNotice();
      expect(provider.hasSessionExpiryNotice, isFalse);
    });

    test('이전 검색 A가 만료를 확정하고 최신 검색 B는 세션 변경으로 끝나면 안내는 한 번', () async {
      final pendingA = provider.search('경복궁');
      final pendingB = provider.search('덕수궁');
      expect(service.searchCalls, hasLength(2));

      authState.signOut();

      service.searchCalls[0].completer.completeError(
        const SessionExpiredException(1),
      );
      await pendingA;
      expect(provider.hasSessionExpiryNotice, isTrue);

      service.searchCalls[1].completer.completeError(
        const SessionChangedException(),
      );
      await pendingB;

      expect(provider.hasSessionExpiryNotice, isTrue);
      expect(provider.searchResults, isEmpty);
      expect(provider.searchStatus, MapSearchStatus.idle);

      provider.consumeSessionExpiryNotice();
      expect(provider.hasSessionExpiryNotice, isFalse);
    });

    test('같은 세션의 검색 두 개가 함께 만료돼도 안내는 한 번', () async {
      final pendingA = provider.search('경복궁');
      final pendingB = provider.search('덕수궁');
      authState.signOut();

      service.searchCalls[0].completer.completeError(
        const SessionExpiredException(1),
      );
      await pendingA;
      provider.consumeSessionExpiryNotice();

      service.searchCalls[1].completer.completeError(
        const SessionExpiredException(1),
      );
      await pendingB;

      expect(provider.hasSessionExpiryNotice, isFalse);
    });

    test('검색 중 사용자가 로그아웃해 세션 변경으로 끝나면 안내하지 않는다', () async {
      final pending = provider.search('경복궁');
      authState.signOut();

      service.searchCalls.single.completer.completeError(
        const SessionChangedException(),
      );
      await pending;

      expect(provider.hasSessionExpiryNotice, isFalse);
    });

    test('진행 중인 검색 없이 로그인이 풀리면(앱 시작 복구 만료 등) 안내하지 않는다', () async {
      authState.signOut();

      expect(provider.hasSessionExpiryNotice, isFalse);
    });

    test('새 로그인 뒤 도착한 이전 세션의 만료 예외는 안내하지 않는다', () async {
      final pending = provider.search('경복궁');
      authState.signOut();
      authState.signIn();

      service.searchCalls.single.completer.completeError(
        const SessionExpiredException(1),
      );
      await pending;

      expect(provider.hasSessionExpiryNotice, isFalse);
    });

    test('표시하기 전에 다시 로그인하면 이전 세션의 안내는 무효가 된다', () async {
      final pending = provider.search('경복궁');
      authState.signOut();
      service.searchCalls.single.completer.completeError(
        const SessionExpiredException(1),
      );
      await pending;
      expect(provider.hasSessionExpiryNotice, isTrue);

      authState.signIn();

      expect(provider.hasSessionExpiryNotice, isFalse);
    });

    test('다시 로그인한 뒤 새 세션이 만료되면 새로 한 번 안내한다', () async {
      final first = provider.search('경복궁');
      authState.signOut();
      service.searchCalls.single.completer.completeError(
        const SessionExpiredException(1),
      );
      await first;
      provider.consumeSessionExpiryNotice();

      authState.signIn();
      final second = provider.search('덕수궁');
      authState.signOut();
      service.searchCalls.last.completer.completeError(
        const SessionExpiredException(3),
      );
      await second;

      expect(provider.hasSessionExpiryNotice, isTrue);
    });

    test('만료 안내는 검색어를 지워도 남아 있다(지도 탭 복귀 때 표시)', () async {
      final pending = provider.search('경복궁');
      authState.signOut();
      service.searchCalls.single.completer.completeError(
        const SessionExpiredException(1),
      );
      await pending;

      provider.clearSearch();

      expect(provider.hasSessionExpiryNotice, isTrue);
    });
  });

  group('상세 캐시 만료', () {
    Future<void> loadDetails(PlaceModel result) async {
      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.last.complete(result);
      await pending;
    }

    test('30분 전에는 재사용하고, 30분이 지나면 다시 조회해 갱신한다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      await loadDetails(_place('a', openNow: true));

      clock = clock.add(
        MapProvider.placeDetailsCacheTtl - const Duration(seconds: 1),
      );
      await provider.loadSelectedPlaceDetails();
      expect(service.detailCalls, ['a']);
      expect(provider.selectedPlace?.openNow, isTrue);

      clock = clock.add(const Duration(seconds: 1));
      final pending = provider.loadSelectedPlaceDetails();
      expect(service.detailCalls, ['a', 'a']);
      expect(provider.detailsStatus, PlaceDetailsStatus.loading);
      service.detailCompleters.last.complete(_place('a', openNow: false));
      await pending;

      expect(provider.selectedPlace?.openNow, isFalse);
      expect(provider.searchResults.single.openNow, isFalse);

      // 갱신한 시각부터 다시 30분 동안 재사용한다.
      clock = clock.add(const Duration(minutes: 29));
      await provider.loadSelectedPlaceDetails();
      expect(service.detailCalls, ['a', 'a']);
      expect(provider.selectedPlace?.openNow, isFalse);
    });

    test('만료 뒤 같은 장소를 다시 고르면 이전 값을 오래된 정보로 쓴다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      final fetchedAt = clock;
      await loadDetails(_place('a', rating: 4.6, openNow: true));

      clock = clock.add(
        MapProvider.placeDetailsCacheTtl - const Duration(seconds: 1),
      );
      await searchAndSucceed('경복궁 근처', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      expect(provider.selectedPlace?.openNow, isTrue);
      expect(provider.selectedPlaceDetailsStale, isFalse);

      clock = clock.add(const Duration(seconds: 1));
      await searchAndSucceed('경복궁 다시', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);

      expect(provider.selectedPlace?.openNow, isTrue);
      expect(provider.selectedPlace?.rating, 4.6);
      expect(provider.selectedPlaceDetailsStale, isTrue);
      expect(provider.selectedPlaceDetailsFetchedAt, fetchedAt);
    });

    test('새로 고침을 기다리는 동안과 실패했을 때는 이전 값과 받은 시각을 유지한다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      final fetchedAt = clock;
      await loadDetails(_place('a', rating: 4.6, openNow: true));

      clock = clock.add(MapProvider.placeDetailsCacheTtl);
      final pending = provider.loadSelectedPlaceDetails();

      expect(provider.detailsStatus, PlaceDetailsStatus.loading);
      expect(provider.selectedPlace?.openNow, isTrue);
      expect(provider.selectedPlaceDetailsStale, isTrue);
      expect(provider.selectedPlaceDetailsFetchedAt, fetchedAt);

      service.detailCompleters.last.completeError(
        const PlaceApiException(message: '실패'),
      );
      await pending;

      expect(provider.detailsStatus, PlaceDetailsStatus.failure);
      expect(provider.selectedPlace?.rating, 4.6);
      expect(provider.selectedPlace?.openNow, isTrue);
      expect(provider.selectedPlaceDetailsLoaded, isTrue);
      expect(provider.selectedPlaceDetailsStale, isTrue);
      expect(provider.selectedPlaceDetailsFetchedAt, fetchedAt);
    });

    test('새로 고침 응답에 값이 없으면 이전 값을 지우고 정보 없음으로 바꾼다', () async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      await loadDetails(_place('a', rating: 4.6, openNow: true));

      clock = clock.add(MapProvider.placeDetailsCacheTtl);
      final refreshedAt = clock;
      await loadDetails(_place('a'));

      expect(provider.selectedPlace?.rating, isNull);
      expect(provider.selectedPlace?.openNow, isNull);
      expect(provider.searchResults.single.openNow, isNull);
      expect(provider.selectedPlaceDetailsLoaded, isTrue);
      expect(provider.selectedPlaceDetailsStale, isFalse);
      expect(provider.selectedPlaceDetailsFetchedAt, refreshedAt);
    });
  });

  test('로그인이 풀리면 검색 상태와 상세 결과를 모두 비운다', () async {
    await searchAndSucceed('경복궁', [_place('a')]);
    provider.selectSearchResult(provider.searchResults.single);
    final pending = provider.loadSelectedPlaceDetails();
    service.detailCompleters.single.complete(_place('a', rating: 4.6));
    await pending;

    var notified = 0;
    provider.addListener(() => notified++);

    authState.signOut();

    expect(notified, 1);
    expect(provider.searchStatus, MapSearchStatus.idle);
    expect(provider.searchResults, isEmpty);
    expect(provider.selectedPlace, isNull);

    // 다시 로그인해 같은 장소를 열면 상세 결과를 새로 조회한다.
    authState.isAuthenticated = true;
    await searchAndSucceed('경복궁', [_place('a')]);
    provider.selectSearchResult(provider.searchResults.single);
    expect(provider.selectedPlace?.rating, isNull);
    unawaited(provider.loadSelectedPlaceDetails());
    expect(service.detailCalls, ['a', 'a']);
    service.detailCompleters.last.complete(_place('a'));
    await _flush();
  });

  test('기존 주변 장소 조회는 그대로 동작한다', () async {
    service.nearbyResult = [_place('n1')];

    await provider.loadNearbyPlaces(latitude: 37.5, longitude: 126.9);

    expect(provider.status, MapPlaceStatus.success);
    expect(provider.places.map((p) => p.id), ['n1']);
    expect(provider.searchStatus, MapSearchStatus.idle);
  });

  group('상세 결과 만료 타이머', () {
    /// 주입한 현재 시각과 테스트의 가짜 타이머 시간을 함께 진행시킨다.
    Future<void> advance(WidgetTester tester, Duration duration) async {
      clock = clock.add(duration);
      await tester.pump(duration);
    }

    Future<void> loadDetailsNow(PlaceModel result) async {
      final pending = provider.loadSelectedPlaceDetails();
      service.detailCompleters.last.complete(result);
      await pending;
    }

    testWidgets('원래 만료 시각에 알린다: 14:05에 받은 장소를 14:30에 다시 열면 14:35에 만료', (
      tester,
    ) async {
      clock = DateTime(2026, 11, 11, 14, 5);
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);
      await loadDetailsNow(_place('a', openNow: true));

      provider.selectSearchResult(provider.searchResults[1]);
      await advance(tester, const Duration(minutes: 25));

      provider.selectSearchResult(provider.searchResults.first);
      expect(clock, DateTime(2026, 11, 11, 14, 30));
      expect(provider.selectedPlaceDetailsStale, isFalse);

      var notified = 0;
      provider.addListener(() => notified++);

      await advance(tester, const Duration(minutes: 4, seconds: 59));
      expect(notified, 0);
      expect(provider.selectedPlaceDetailsStale, isFalse);

      await advance(tester, const Duration(seconds: 1));
      expect(clock, DateTime(2026, 11, 11, 14, 35));
      expect(notified, 1);
      expect(provider.selectedPlaceDetailsStale, isTrue);
      expect(provider.selectedPlace?.openNow, isTrue);
    });

    testWidgets('카드를 닫거나 다른 장소를 고르면 이전 장소의 만료를 알리지 않는다', (tester) async {
      await searchAndSucceed('경복궁', [_place('a'), _place('b')]);
      provider.selectSearchResult(provider.searchResults.first);
      await loadDetailsNow(_place('a', openNow: true));

      var notified = 0;
      provider.addListener(() => notified++);

      provider.clearSelectedPlace();
      provider.selectSearchResult(provider.searchResults[1]);
      final afterSelect = notified;

      await advance(tester, MapProvider.placeDetailsCacheTtl);
      expect(notified, afterSelect);
    });

    testWidgets('새로 고침에 성공하면 그 시각부터 다시 30분 뒤에 알린다', (tester) async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      await loadDetailsNow(_place('a', openNow: true));

      await advance(tester, MapProvider.placeDetailsCacheTtl);
      expect(provider.selectedPlaceDetailsStale, isTrue);

      await loadDetailsNow(_place('a', openNow: false));
      expect(provider.selectedPlaceDetailsStale, isFalse);

      var notified = 0;
      provider.addListener(() => notified++);

      await advance(
        tester,
        MapProvider.placeDetailsCacheTtl - const Duration(seconds: 1),
      );
      expect(notified, 0);

      await advance(tester, const Duration(seconds: 1));
      expect(notified, 1);
      expect(provider.selectedPlaceDetailsStale, isTrue);
    });

    testWidgets('로그아웃하면 타이머를 끈다', (tester) async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      await loadDetailsNow(_place('a', openNow: true));

      authState.signOut();

      var notified = 0;
      provider.addListener(() => notified++);
      await advance(tester, MapProvider.placeDetailsCacheTtl);
      expect(notified, 0);
    });

    testWidgets('dispose하면 타이머를 끈다', (tester) async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      await loadDetailsNow(_place('a', openNow: true));

      provider.dispose();
      disposedInTest = true;

      // 시간을 진행시키지 않고 끝낸다. dispose가 타이머를 끄지 않으면 testWidgets가
      // 테스트 끝에 남은 타이머(A Timer is still pending)로 실패시킨다.
    });

    for (final fails in [false, true]) {
      testWidgets('주변 장소 조회(${fails ? '실패' : '성공'})로 선택이 풀리면 타이머를 끈다', (
        tester,
      ) async {
        await searchAndSucceed('경복궁', [_place('a')]);
        provider.selectSearchResult(provider.searchResults.single);
        await loadDetailsNow(_place('a', openNow: true));

        if (fails) {
          service.nearbyError = const PlaceApiException(message: '실패');
        } else {
          service.nearbyResult = [_place('n1')];
        }

        await provider.loadNearbyPlaces(latitude: 37.5, longitude: 126.9);
        expect(provider.selectedPlace, isNull);

        var notified = 0;
        provider.addListener(() => notified++);

        await advance(tester, MapProvider.placeDetailsCacheTtl);
        expect(notified, 0);
      });
    }

    testWidgets('지도 이벤트 없이 열어 둔 카드에 30분 뒤 새로 고침이 나타난다', (tester) async {
      await searchAndSucceed('경복궁', [_place('a')]);
      provider.selectSearchResult(provider.searchResults.single);
      await loadDetailsNow(_place('a', openNow: true));

      // 화면 대역: Provider 알림으로만 다시 그린다(지도·위치 갱신 없음).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: provider,
              builder: (context, _) => PlaceDetailCard(
                place: provider.selectedPlace!,
                detailsStatus: provider.detailsStatus,
                detailsLoaded: provider.selectedPlaceDetailsLoaded,
                detailsStale: provider.selectedPlaceDetailsStale,
                detailsFetchedAt: provider.selectedPlaceDetailsFetchedAt,
                detailsErrorMessage: provider.detailsErrorMessage,
                onClose: () {},
                onDetailPressed: provider.loadSelectedPlaceDetails,
              ),
            ),
          ),
        ),
      );

      expect(find.text('영업 중'), findsOneWidget);
      expect(find.text(PlaceDetailCard.refreshLabel), findsNothing);

      await advance(
        tester,
        MapProvider.placeDetailsCacheTtl - const Duration(seconds: 1),
      );
      expect(find.text(PlaceDetailCard.refreshLabel), findsNothing);

      await advance(tester, const Duration(seconds: 1));
      expect(find.text(PlaceDetailCard.refreshLabel), findsOneWidget);
      expect(find.text('영업 중'), findsOneWidget);
      expect(find.textContaining(PlaceDetailCard.staleLabel), findsOneWidget);
    });
  });
}
