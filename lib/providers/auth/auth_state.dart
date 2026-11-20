import '../../models/user/user_response.dart';
import '../../repositories/auth/auth_repository.dart';

/// 앱의 인증 상태.
class AuthState {
  const AuthState({
    this.isInitialized = false,
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isLoadingSocialAccounts = false,
    this.sessionRestoreFailed = false,
    this.googleLinked,
    this.userId,
    this.loginId,
    this.nickname,
    this.profileImageUrl,
    this.errorMessage,
    this.sessionId = 0,
  });

  /// 앱 초기화 시 인증 상태를 복구했는지 여부
  final bool isInitialized;
  final bool isLoading;
  final bool isAuthenticated;
  final bool isLoadingSocialAccounts;

  /// 세션 만료가 확인되지 않은 오류로 세션 복구에 실패해 토큰을 남겨 둔 상태.
  /// 화면은 상단 배너로 다시 시도([AuthNotifier.retryRestoreSession])를 안내한다.
  final bool sessionRestoreFailed;

  /// 현재 로그인 사용자의 Google 계정 연동 상태
  final bool? googleLinked;

  /// 현재 로그인 사용자의 정보
  final int? userId;
  final String? loginId;
  final String? nickname;
  final String? profileImageUrl;
  final String? errorMessage;

  /// 상태를 내보낸 시점의 [AuthRepository.sessionId].
  /// 로그인·로그아웃·세션 만료 때마다 바뀐다. 중간 전이가 합쳐져도 세션이 바뀐 것을
  /// 알 수 있도록 다른 상태(지도)가 이 번호를 비교한다.
  final int sessionId;

  AuthState copyWith({
    bool? isInitialized,
    bool? isLoading,
    bool? isAuthenticated,
    bool? isLoadingSocialAccounts,
    bool? sessionRestoreFailed,
    bool? googleLinked,
    bool clearGoogleLinked = false,
    int? userId,
    bool clearUserId = false,
    String? loginId,
    bool clearLoginId = false,
    String? nickname,
    bool clearNickname = false,
    String? profileImageUrl,
    bool clearProfileImageUrl = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    int? sessionId,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoadingSocialAccounts:
          isLoadingSocialAccounts ?? this.isLoadingSocialAccounts,
      sessionRestoreFailed: sessionRestoreFailed ?? this.sessionRestoreFailed,
      googleLinked: clearGoogleLinked
          ? null
          : googleLinked ?? this.googleLinked,
      userId: clearUserId ? null : userId ?? this.userId,
      loginId: clearLoginId ? null : loginId ?? this.loginId,
      nickname: clearNickname ? null : nickname ?? this.nickname,
      profileImageUrl: clearProfileImageUrl
          ? null
          : profileImageUrl ?? this.profileImageUrl,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  /// 서버가 준 현재 사용자 정보로 로그인 상태가 된다. 없는 값(닉네임·사진)은 비운다.
  AuthState withUser(UserResponse user) {
    return copyWith(
      userId: user.id,
      loginId: user.loginId,
      nickname: user.nickname,
      clearNickname: user.nickname == null,
      profileImageUrl: user.profileImageUrl,
      clearProfileImageUrl: user.profileImageUrl == null,
      isAuthenticated: true,
      sessionRestoreFailed: false,
    );
  }

  /// 현재 로그인 사용자의 상태를 비운다.
  ///
  /// 세션 번호는 [AuthRepository]가 토큰 저장·삭제와 함께 관리한다.
  AuthState withoutUser() {
    return copyWith(
      isAuthenticated: false,
      sessionRestoreFailed: false,
      clearUserId: true,
      clearLoginId: true,
      clearNickname: true,
      clearProfileImageUrl: true,
      clearGoogleLinked: true,
    );
  }
}
