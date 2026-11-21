/// 인증 Repository가 던지는 예외. `auth_repository.dart`가 다시 내보낸다.
///
/// @docImport 'auth_repository.dart';
library;

/// 로컬 인증 세션 자체에 문제가 있을 때 사용하는 예외(저장된 토큰이 없음).
/// 세션 만료로 판정된다([AuthRepository.isSessionExpiredError]).
class AuthSessionException implements Exception {
  final String message;

  const AuthSessionException(this.message);

  @override
  String toString() => message;
}

/// 기기 토큰 저장소의 저장·읽기가 기대와 다르게 끝났을 때의 예외.
///
/// 세션 만료가 아니므로 [AuthRepository.isSessionExpiredError]는 false다.
/// 세션 복구에서는 토큰을 남기고 상단 배너의 다시 시도로 보낸다.
class TokenStorageException implements Exception {
  final String message;

  const TokenStorageException(this.message);

  @override
  String toString() => message;
}

/// 세션 만료가 확인되어 로그인 상태를 해제했음을 알리는 예외.
///
/// AuthNotifier.runAuthorizedRequest가 던진다. 앱은 비로그인으로도 쓸 수 있어 화면은
/// 그대로 남으므로, 안내가 필요하면 호출한 화면이 맡는다(예: 지도 검색의 만료 안내).
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.sessionId]);

  /// 만료된 요청이 시작된 로그인 세션 번호([AuthRepository.sessionId]).
  /// 같은 세션의 만료 안내를 한 번만 띄우는 데 쓴다.
  final int? sessionId;

  @override
  String toString() => '로그인이 만료되었습니다. 다시 로그인해 주세요.';
}

/// 요청을 시작한 로그인 세션이 그 사이 바뀌어(로그아웃·재로그인) 작업을 중단했음을 알리는 예외.
///
/// 세션 만료가 아니므로 [AuthRepository.isSessionExpiredError]는 false다.
/// 이전 화면에서 시작한 작업이므로 호출부는 현재 화면의 데이터와 오류 문구를 그대로 두고 무시한다.
class SessionChangedException implements Exception {
  const SessionChangedException();

  @override
  String toString() => '로그인 세션이 바뀌어 이전 요청을 중단했습니다.';
}

/// 세션을 끝낸 뒤 기기 토큰 삭제가 실패했음을 알리는 예외.
///
/// [AuthRepository.clearTokensIfSession]이 던진다. 삭제를 시도하기 전에 세션 번호를
/// 이미 바꿨으므로, 바뀐 번호를 [sessionId]에 담는다. 번호는 순차 경로 안에서 읽어
/// 그 뒤 대기 중이던 로그인이 번호를 다시 바꿔도 이 삭제가 끝낸 세션의 번호다.
/// 다시 지우기를 시도하는 쪽(로그아웃의 다시 시도)은 이 번호가 현재 세션일 때만 지운다.
class TokenClearException implements Exception {
  const TokenClearException({required this.sessionId, required this.cause});

  /// 실패한 삭제가 바꾼 뒤의 세션 번호.
  final int sessionId;

  /// 기기 토큰 저장소가 던진 원래 오류.
  final Object cause;

  @override
  String toString() => '기기 토큰 삭제 실패: $cause';
}
