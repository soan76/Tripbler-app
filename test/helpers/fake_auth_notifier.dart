import 'package:tripbler/providers/auth_provider.dart';

/// 테스트가 로그인·로그아웃·세션 만료를 직접 일으키는 가짜 인증 상태.
///
/// 실제 [AuthNotifier]처럼 세션이 바뀔 때마다 [AuthState.sessionId]를 올린다.
/// 저장소를 쓰지 않으므로 인증 API 메서드는 부르지 않는다.
/// `authProvider.overrideWith(() => fake)`로 넣는다.
class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier({this.initiallySignedIn = true});

  final bool initiallySignedIn;

  @override
  AuthState build() {
    return AuthState(isInitialized: true, isAuthenticated: initiallySignedIn);
  }

  bool get isAuthenticated => state.isAuthenticated;

  /// 세션을 바꾸지 않고 로그인 여부만 바꾼다(요청 직전 로그인이 풀린 상황 등).
  set isAuthenticated(bool value) {
    state = state.copyWith(isAuthenticated: value);
  }

  /// 새 세션으로 로그인한다.
  void signIn() {
    state = state.copyWith(
      isAuthenticated: true,
      sessionId: state.sessionId + 1,
    );
  }

  /// 로그아웃한다(세션 종료).
  void signOut() {
    state = state.withoutUser().copyWith(sessionId: state.sessionId + 1);
  }

  /// 세션이 만료돼 로그인이 풀린다(세션 종료).
  void expire() => signOut();

  /// 로그아웃→재로그인이 한 번의 변화로 합쳐져 도착한 상황.
  /// 로그인 여부는 그대로 true이고 세션 번호만 두 번 바뀐다.
  void signOutAndInAtOnce() {
    state = state.copyWith(
      isAuthenticated: true,
      sessionId: state.sessionId + 2,
    );
  }
}
