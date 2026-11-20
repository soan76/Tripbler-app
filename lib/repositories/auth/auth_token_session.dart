import 'package:flutter/foundation.dart';

import '../../services/auth/token_storage_service.dart';
import 'auth_exceptions.dart';

/// 로그인 세션 번호와 기기 토큰 저장소 작업 순서를 관리한다.
///
/// 세션 번호 변경, 토큰 저장·삭제, "번호 + 토큰" 읽기를 모두 하나의 순차 경로로
/// 실행해 새 번호와 이전 토큰이 한 쌍으로 읽히지 않게 한다.
/// 네트워크 호출은 이 클래스에 넣지 않는다(느린 요청이 다른 인증 요청을 막지 않도록).
class AuthTokenSession {
  AuthTokenSession(this._tokenStorageService);

  final TokenStorageService _tokenStorageService;

  /// 로그인 세션 번호.
  ///
  /// 로그인(새 토큰 저장)과 세션 종료(로그아웃·탈퇴·토큰 삭제) 때만 바뀌고,
  /// 같은 세션에서 Access Token만 재발급할 때는 그대로다.
  /// 인증 요청은 시작할 때 이 번호를 기록해 두고, 재시도·토큰 저장·만료 처리를
  /// 원래 세션에만 적용한다. AuthNotifier도 같은 번호를 참조한다.
  int _sessionId = 0;

  int get sessionId => _sessionId;

  /// 토큰 저장소 작업을 한 줄로 처리하는 꼬리 Future.
  ///
  /// 세션 번호 변경과 토큰 저장·삭제, 인증 요청의 "번호 + 토큰" 읽기가 모두 이 꼬리를
  /// 공유한다. 다른 클래스가 따로 꼬리를 두면 순서가 깨지므로 이 클래스에만 둔다.
  Future<void> _storageTail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _storageTail.then((_) => operation());
    _storageTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// 현재 세션 번호와 저장된 Authorization 헤더를 한 쌍으로 읽는다.
  Future<({int sessionId, String? header})> readSessionAuth() {
    return _serialized(() async {
      return (
        sessionId: _sessionId,
        header: await _tokenStorageService.readAuthorizationHeader(),
      );
    });
  }

  /// 요청을 시작한 세션이 아직 유지되는지 확인한다.
  void ensureSameSession(int sessionId) {
    if (_sessionId != sessionId) {
      throw const SessionChangedException();
    }
  }

  /// 새 세션을 시작한다(로그인 성공 뒤).
  ///
  /// 같은 순차 경로 안에서 세션 번호를 바꾸고 새 토큰을 저장한다.
  Future<void> startSession({
    required String accessToken,
    required String refreshToken,
    required String tokenType,
  }) {
    return _serialized(() async {
      _sessionId++;

      await _tokenStorageService.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        tokenType: tokenType,
      );
    });
  }

  /// 현재 세션을 끝내고 저장된 토큰을 모두 지운다(세션 번호 한 번 변경).
  Future<void> clearTokens() {
    return _serialized(() async {
      _sessionId++;
      await _tokenStorageService.clearTokens();
    });
  }

  /// [sessionId] 세션이 아직 현재 세션일 때만 끝내고 토큰을 지운다.
  ///
  /// 세션 만료 처리나 탈퇴처럼 늦게 끝날 수 있는 작업이 그 사이 로그인한
  /// 다른 계정의 토큰을 지우지 않게 한다. 지웠으면 true.
  Future<bool> clearTokensIfSession(int sessionId) {
    return _serialized(() async {
      if (_sessionId != sessionId) {
        return false;
      }

      _sessionId++;
      await _tokenStorageService.clearTokens();

      return true;
    });
  }

  /// 로그아웃의 로컬 부분.
  ///
  /// 순차 경로 안에서 이 기기의 Refresh Token을 읽고, 세션 번호를 바꾸고, 로컬 토큰을
  /// 지운다. 삭제가 실패하면 한 번 더 시도하고, 그래도 실패하면 오류와 스택을 돌려준다
  /// (세션 번호는 이미 바뀐 상태). 읽은 Refresh Token은 서버 로그아웃에 쓴다.
  Future<
    ({String? refreshToken, Object? clearError, StackTrace? clearStackTrace})
  >
  endSessionForLogout() {
    return _serialized(() async {
      String? refreshToken;
      Object? clearError;
      StackTrace? clearStackTrace;

      try {
        // 서버는 이 Refresh Token과 일치하는 토큰만 폐기한다(같은 계정의 새 로그인 세션은 보존).
        refreshToken = await _tokenStorageService.readRefreshToken();
      } catch (error) {
        debugPrint('로그아웃용 토큰 읽기 실패: $error');
      }

      _sessionId++;

      try {
        await _tokenStorageService.clearTokens();
      } catch (error) {
        debugPrint('로컬 토큰 삭제 실패, 한 번 더 시도: $error');

        try {
          await _tokenStorageService.clearTokens();
        } catch (retryError, stackTrace) {
          clearError = retryError;
          clearStackTrace = stackTrace;
        }
      }

      return (
        refreshToken: refreshToken,
        clearError: clearError,
        clearStackTrace: clearStackTrace,
      );
    });
  }

  /// 재발급에 필요한 현재 세션 번호, Authorization 헤더, Refresh Token을 한 번에 읽는다.
  Future<({int sessionId, String? header, String? refreshToken})>
  readRefreshState() {
    return _serialized(() async {
      return (
        sessionId: _sessionId,
        header: await _tokenStorageService.readAuthorizationHeader(),
        refreshToken: await _tokenStorageService.readRefreshToken(),
      );
    });
  }

  /// [sessionId] 세션이 그대로일 때만 재발급한 Access Token을 저장하고
  /// 저장된 Authorization 헤더를 다시 읽는다. 세션이 바뀌었으면 저장하지 않는다.
  Future<({bool sameSession, String? header})> saveRefreshedAccessToken(
    int sessionId, {
    required String accessToken,
    String? tokenType,
  }) {
    return _serialized(() async {
      if (_sessionId != sessionId) {
        return (sameSession: false, header: null);
      }

      await _tokenStorageService.saveAccessToken(
        accessToken: accessToken,
        tokenType: tokenType,
      );

      return (
        sameSession: true,
        header: await _tokenStorageService.readAuthorizationHeader(),
      );
    });
  }

  // 아래 단순 읽기는 순차 경로 밖에서 저장소를 바로 읽는다.

  Future<String?> readAccessToken() {
    return _tokenStorageService.readAccessToken();
  }

  Future<String?> readRefreshToken() {
    return _tokenStorageService.readRefreshToken();
  }

  Future<String?> readAuthorizationHeader() {
    return _tokenStorageService.readAuthorizationHeader();
  }

  Future<bool> hasTokens() {
    return _tokenStorageService.hasTokens();
  }
}
