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
    } on Exception {
      // 연결 실패·TLS 오류 같은 통신 예외만 네트워크 오류로 바꾼다. 프로그램 오류(Error)는
      // 연결 문제로 가리지 않고 그대로 던진다.
      throw const ApiException(
        message: '장소 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    }

    if (response.statusCode != 200) {
      throw _apiErrorFrom(response, _searchMessageFor);
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
  // 본문을 읽지 못해도 상태 코드는 유지한다. 문구는 [messageFor]가 정한다.
  ApiException _apiErrorFrom(
    http.Response response,
    String Function(int statusCode, String? serverMessage) messageFor,
  ) {
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
      message: messageFor(response.statusCode, serverMessage),
    );
  }

  static const String _tooManyRequestsMessage = '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';

  String _searchMessageFor(int statusCode, String? serverMessage) {
    switch (statusCode) {
      case 400:
        // 검색어 길이·좌표 오류처럼 사용자가 고칠 수 있는 내용은 서버 문구를 그대로 쓴다.
        return serverMessage ?? '검색 조건이 올바르지 않습니다.';
      case 401:
        return '로그인이 필요합니다.';
      case 429:
        return serverMessage ?? _tooManyRequestsMessage;
      case 503:
        return '장소 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return '장소를 검색하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }

  /// placeId로 장소 상세 정보(평점·영업 여부 포함)를 조회한다(로그인 필요).
  ///
  /// 실패는 검색과 같은 [ApiException]으로 던진다.
  /// - 서버 오류 응답: statusCode와 code(예: TOO_MANY_REQUESTS, RESOURCE_NOT_FOUND)
  /// - 시간 초과·연결 실패: statusCode가 null([ApiException.isNetworkError])
  /// 401이면 호출부(AuthRepository.authorizedRequest)가 토큰을 재발급해 다시 시도한다.
  Future<PlaceModel> fetchPlaceDetails({
    required String placeId,
    required String authorizationHeader,
  }) async {
    final uri = ApiConfig.placeDetailsUri(placeId: placeId);

    final http.Response response;

    try {
      response = await _client
          .get(
            uri,
            headers: <String, String>{'Authorization': authorizationHeader},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(message: '장소 상세 정보 요청 시간이 초과되었습니다.');
    } on Exception {
      // 검색과 같이 통신 예외만 네트워크 오류로 바꾼다.
      throw const ApiException(message: '장소 서버에 연결할 수 없습니다.');
    }

    if (response.statusCode != 200) {
      throw _apiErrorFrom(response, _detailsMessageFor);
    }

    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! Map<String, dynamic>) {
        throw const FormatException('상세 응답이 객체 형식이 아닙니다.');
      }

      return PlaceModel.fromJson(decodedBody);
    } catch (error) {
      debugPrint('장소 상세 응답 파싱 실패: $error');

      throw ApiException(
        statusCode: response.statusCode,
        message: '장소 상세 응답 형식이 올바르지 않습니다.',
      );
    }
  }

  String _detailsMessageFor(int statusCode, String? serverMessage) {
    switch (statusCode) {
      case 401:
        return '로그인이 필요합니다.';
      case 429:
        return serverMessage ?? _tooManyRequestsMessage;
      case 503:
        return '장소 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return serverMessage ?? '장소 상세 정보를 불러오지 못했습니다.';
    }
  }

  void dispose() {
    _client.close();
  }
}
