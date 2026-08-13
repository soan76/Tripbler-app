import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/place_model.dart';

class PlaceApiService {
  PlaceApiService({http.Client? client}) : _client = client ?? http.Client();

  static const String _definedBaseUrl = String.fromEnvironment(
    'TRIPBLER_API_BASE_URL',
  );

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;

  String get _baseUrl {
    if (_definedBaseUrl.isNotEmpty) {
      return _definedBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8080';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8080';

      case TargetPlatform.iOS:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'http://localhost:8080';
    }
  }

  Future<List<PlaceModel>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    String type = 'restaurant',
    int radius = 1000,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/places/nearby').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        'type': type,
        'radius': radius.toString(),
      },
    );

    final response = await _sendGetRequest(uri);

    if (response.statusCode != 200) {
      throw PlaceApiException(
        message: _parseErrorMessage(
          response,
          fallbackMessage: _messageForStatusCode(response.statusCode),
        ),
      );
    }

    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      debugPrint('nearest response body: ${utf8.decode(response.bodyBytes)}');

      if (decodedBody is! List) {
        throw const FormatException('장소 응답이 List 형식이 아닙니다.');
      }

      return decodedBody
          .map((item) => PlaceModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (error) {
      debugPrint('장소 응답 파싱 실패: $error');

      throw const PlaceApiException(message: '장소 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<http.Response> _sendGetRequest(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const PlaceApiException(
        message: '장소 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on http.ClientException {
      throw const PlaceApiException(
        message: '장소 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    } catch (_) {
      throw const PlaceApiException(
        message: '장소 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    }
  }

  // 사용자가 지도 위 기본 POI 아이콘 근처를 탭했을 때,
  // 해당 좌표 주변에서 가장 가까운 장소 1개를 백엔드에 요청함.
  Future<PlaceModel?> fetchNearestPlace({
    required double latitude,
    required double longitude,
    int radius = 40,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/places/nearest').replace(
      queryParameters: <String, String>{
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        'radius': radius.toString(),
      },
    );

    try {
      final response = await _client.get(uri).timeout(_timeout);

      // 근처에 장소가 없는 경우
      if (response.statusCode == 204 || response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        throw PlaceApiException(
          message: _parseErrorMessage(
            response,
            fallbackMessage: '선택한 장소 정보를 불러오지 못했습니다.',
          ),
        );
      }

      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! Map<String, dynamic>) {
        throw const PlaceApiException(message: '장소 상세 응답 형식이 올바르지 않습니다.');
      }

      return PlaceModel.fromJson(decodedBody);
    } on TimeoutException {
      throw const PlaceApiException(message: '장소 정보 요청 시간이 초과되었습니다.');
    } on http.ClientException {
      throw const PlaceApiException(message: '장소 서버에 연결할 수 없습니다.');
    } on PlaceApiException {
      rethrow;
    } catch (error) {
      debugPrint('근처 장소 조회 실패: $error');

      throw const PlaceApiException(message: '선택한 위치의 장소 정보를 불러오지 못했습니다.');
    }
  }

  // placeId를 기준으로 장소 상세 정보를 백엔드에서 조회함.
  // 백엔드 엔드포인트:
  // GET /api/v1/places/{placeId}
  Future<PlaceModel> fetchPlaceDetails({required String placeId}) async {
    final uri = Uri.parse('$_baseUrl/api/v1/places/$placeId');

    try {
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw PlaceApiException(
          message: _parseErrorMessage(
            response,
            fallbackMessage: '장소 상세 정보를 불러오지 못했습니다.',
          ),
        );
      }

      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! Map<String, dynamic>) {
        throw const PlaceApiException(message: '장소 상세 응답 형식이 올바르지 않습니다.');
      }

      return PlaceModel.fromJson(decodedBody);
    } on TimeoutException {
      throw const PlaceApiException(message: '장소 상세 정보 요청 시간이 초과되었습니다.');
    } on http.ClientException {
      throw const PlaceApiException(message: '장소 서버에 연결할 수 없습니다.');
    } on PlaceApiException {
      rethrow;
    } catch (error) {
      debugPrint('장소 상세 조회 실패: $error');

      throw const PlaceApiException(message: '장소 상세 정보를 불러오는 중 문제가 발생했습니다.');
    }
  }

  String _parseErrorMessage(
    http.Response response, {
    required String fallbackMessage,
  }) {
    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! Map<String, dynamic>) {
        return fallbackMessage;
      }

      final status = decodedBody['status'];
      final code = decodedBody['code'];
      final message = decodedBody['message'];

      if (status == 503 || code == 'PLACES_PROVIDER_UNAVAILABLE') {
        return '장소 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      }

      if (status == 500 || code == 'INTERNAL_SERVER_ERROR') {
        return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
      }

      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }

      return fallbackMessage;
    } catch (_) {
      return fallbackMessage;
    }
  }

  String _messageForStatusCode(int statusCode) {
    if (statusCode == 400) {
      return '장소 검색 요청값이 올바르지 않습니다.';
    }

    if (statusCode == 404) {
      return '장소 API 주소를 찾을 수 없습니다.';
    }

    if (statusCode == 500) {
      return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 503) {
      return '장소 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    }

    return '장소 정보를 불러오지 못했습니다. 다시 시도해 주세요.';
  }

  void dispose() {
    _client.close();
  }
}

class PlaceApiException implements Exception {
  final String message;

  const PlaceApiException({required this.message});

  @override
  String toString() {
    return message;
  }
}
