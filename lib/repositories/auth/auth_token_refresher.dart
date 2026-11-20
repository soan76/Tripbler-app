import 'package:flutter/foundation.dart';

import '../../models/auth/token_refresh_request.dart';
import '../../models/auth/token_refresh_response.dart';
import '../../services/auth/auth_api_service.dart';
import 'auth_exceptions.dart';
import 'auth_token_session.dart';

/// 세션별 Access Token 재발급을 맡는다.
///
/// 토큰 저장소 읽기·저장은 [AuthTokenSession]의 순차 경로로만 하고,
/// 재발급 네트워크 호출은 그 경로 밖에서 보낸다.
class AuthTokenRefresher {
  AuthTokenRefresher({
    required AuthTokenSession session,
    required AuthApiService authApiService,
  }) : _session = session,
       _authApiService = authApiService;

  final AuthTokenSession _session;
  final AuthApiService _authApiService;

  /// 진행 중인 Access Token 재발급. 같은 세션의 요청끼리만 공유한다.
  _RefreshTask? _ongoingRefresh;

  /// [sessionId] 세션의 Access Token을 재발급한다.
  ///
  /// - 같은 세션의 진행 중인 재발급이 있으면 합류한다. 다른 세션의 재발급에는 합류하지 않는다.
  /// - [failedHeader]보다 새 토큰이 이미 저장돼 있으면(다른 요청이 먼저 재발급함) 그 토큰을 쓴다.
  /// - 결과는 순차 경로에서 세션이 그대로일 때만 저장한다. 세션이 바뀌었으면
  ///   [SessionChangedException]을 던지고, 이전 세션의 실패가 새 세션의 만료로 판정되지 않게 한다.
  Future<String> refreshForSession(
    int sessionId, {
    required String? failedHeader,
  }) {
    final ongoing = _ongoingRefresh;

    if (ongoing != null && ongoing.sessionId == sessionId) {
      return ongoing.future;
    }

    final task = _RefreshTask(
      sessionId,
      _performRefresh(sessionId, failedHeader: failedHeader),
    );

    _ongoingRefresh = task;

    // 늦게 끝난 다른 세션의 재발급이 진행 중인 참조를 지우지 않도록 자기 것만 지운다.
    task.future.then<void>(
      (_) => _clearOngoingRefresh(task),
      onError: (Object _) => _clearOngoingRefresh(task),
    );

    return task.future;
  }

  void _clearOngoingRefresh(_RefreshTask task) {
    if (identical(_ongoingRefresh, task)) {
      _ongoingRefresh = null;
    }
  }

  Future<String> _performRefresh(
    int sessionId, {
    required String? failedHeader,
  }) async {
    final stored = await _session.readRefreshState();

    if (stored.sessionId != sessionId) {
      throw const SessionChangedException();
    }

    final storedHeader = stored.header;

    if (failedHeader != null &&
        storedHeader != null &&
        storedHeader.isNotEmpty &&
        storedHeader != failedHeader) {
      debugPrint('다른 요청에서 Access Token 재발급 완료 → 저장된 토큰 사용');
      return storedHeader;
    }

    final refreshToken = stored.refreshToken;

    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthSessionException('저장된 Refresh Token이 없습니다.');
    }

    final TokenRefreshResponse response;

    try {
      response = await _authApiService.refresh(
        TokenRefreshRequest(refreshToken: refreshToken),
      );
    } catch (_) {
      // 재발급 중 세션이 바뀌었다면 이전 세션의 실패(만료 포함)는 세션 변경으로 바꾼다.
      _session.ensureSameSession(sessionId);
      rethrow;
    }

    final saved = await _session.saveRefreshedAccessToken(
      sessionId,
      accessToken: response.accessToken,
      tokenType: response.tokenType,
    );

    if (!saved.sameSession) {
      // 재발급 응답이 오기 전에 로그아웃·재로그인됨: 이전 세션의 토큰은 저장하지 않는다.
      throw const SessionChangedException();
    }

    final refreshedHeader = saved.header;

    if (refreshedHeader == null || refreshedHeader.isEmpty) {
      // 서버는 새 Access Token을 발급했지만 기기 저장소에서 다시 읽지 못했다.
      // 세션 만료가 아니라 로컬 저장·읽기 실패이므로 Refresh Token은 지우지 않는다.
      throw const TokenStorageException('재발급한 Access Token을 기기에서 읽지 못했습니다.');
    }

    return refreshedHeader;
  }
}

/// 세션별 Access Token 재발급 작업.
class _RefreshTask {
  _RefreshTask(this.sessionId, this.future);

  final int sessionId;
  final Future<String> future;
}
