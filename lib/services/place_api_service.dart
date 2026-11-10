import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/network/api_exception.dart';
import '../models/place_model.dart';

class PlaceApiService {
  PlaceApiService({http.Client? client, Duration timeout = defaultTimeout})
    : _client = client ?? http.Client(),
      _timeout = timeout;

  /// 서버의 Google 호출 제한(연결 2초 + 읽기 5초)보다 길게 둔다.
  static const Duration defaultTimeout = Duration(seconds: 8);

  final Duration _timeout;

  final http.Client _client;

  /// 검색어로 장소를 검색한다(로그인 필요).
  ///
  /// 좌표는 둘 다 넣거나 둘 다 생략한다. 좌표가 있으면 그 주변 결과가 우선된다.
  /// 검색어 정리(앞뒤 공백 제거, 길이 제한)는 호출부가 맡고, 여기서는 받은 값을 그대로 보낸다.
  ///
  /// 실패는 [ApiException]으로 던진다.
  /// - 서버 오류 응답: statusCode와 code(예: INVALID_REQUEST, PLACES_PROVIDER_UNAVAILABLE)
  /// - 시간 초과·연결 실패: statusCode가 null([ApiException.isNetworkError])
  /// 401이면 호출부(AuthRepository.authorizedRequest)가 토큰을 재발급해 다시 시도한다.
  Future<List<PlaceModel>> searchPlaces({
    required String query,
    double? latitude,
    double? longitude,
    required String authorizationHeader,
  }) async {
    final uri = ApiConfig.placesSearchUri(
      query: query,
      latitude: latitude,
      longitude: longitude,
    );

    final http.Response response;

    try {
      response = await _client
          .get(
            uri,
            headers: <String, String>{'Authorization': authorizationHeader},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        message: '장소 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } catch (_) {
      throw const ApiException(
        message: '장소 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    }

    if (response.statusCode != 200) {
      throw _searchErrorFrom(response);
    }

    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! List) {
        throw const FormatException('검색 응답이 List 형식이 아닙니다.');
      }

      return decodedBody
          .map((item) => PlaceModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (error) {
      debugPrint('장소 검색 응답 파싱 실패: $error');

      throw ApiException(
        statusCode: response.statusCode,
        message: '장소 검색 응답 형식이 올바르지 않습니다.',
      );
    }
  }

  // 서버 ErrorResponse의 code와 message를 담아 ApiException으로 바꾼다.
  // 본문을 읽지 못해도 상태 코드는 유지한다.
  ApiException _searchErrorFrom(http.Response response) {
    String? code;
    String? serverMessage;

    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is Map<String, dynamic>) {
        final rawCode = decodedBody['code'];
        final rawMessage = decodedBody['message'];

        code = rawCode is String ? rawCode : null;
        serverMessage = rawMessage is String && rawMessage.trim().isNotEmpty
            ? rawMessage.trim()
            : null;
      }
    } catch (_) {
      // 본문이 JSON이 아니면 상태 코드 기준 문구를 쓴다.
    }

    return ApiException(
      statusCode: response.statusCode,
      code: code,
      message: _searchMessageFor(response.statusCode, serverMessage),
    );
  }

  String _searchMessageFor(int statusCode, String? serverMessage) {
    switch (statusCode) {
      case 400:
        // 검색어 길이·좌표 오류처럼 사용자가 고칠 수 있는 내용은 서버 문구를 그대로 쓴다.
        return serverMessage ?? '검색 조건이 올바르지 않습니다.';
      case 401:
        return '로그인이 필요합니다.';
      case 503:
        return '장소 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return '장소를 검색하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }

  Future<List<PlaceModel>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    String type = 'restaurant',
    int radius = 1000,
  }) async {
    final uri = ApiConfig.placesNearbyUri(
      latitude: latitude,
      longitude: longitude,
      type: type,
      radius: radius,
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
    final uri = ApiConfig.placesNearestUri(
      latitude: latitude,
      longitude: longitude,
      radius: radius,
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
    final uri = ApiConfig.placeDetailsUri(placeId: placeId);

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
