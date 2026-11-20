import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, ProviderSubscription;
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';

/// [repository]를 쓰는 인증 상태를 새 테스트 컨테이너에 두고 읽고 바꾼다.
/// 상태가 바뀔 때마다 리스너에 알린다.
class AuthHandle extends ChangeNotifier {
  AuthHandle(AuthRepository repository)
    : container = ProviderContainer.test(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      ) {
    _subscription = container.listen(authProvider, (_, _) => notifyListeners());
  }

  final ProviderContainer container;
  late final ProviderSubscription<AuthState> _subscription;

  AuthNotifier get _notifier => container.read(authProvider.notifier);
  AuthState get state => container.read(authProvider);

  bool get isInitialized => state.isInitialized;
  bool get isLoading => state.isLoading;
  bool get isAuthenticated => state.isAuthenticated;
  bool get isLoadingSocialAccounts => state.isLoadingSocialAccounts;
  bool get sessionRestoreFailed => state.sessionRestoreFailed;
  bool? get googleLinked => state.googleLinked;
  int? get userId => state.userId;
  String? get loginId => state.loginId;
  String? get nickname => state.nickname;
  String? get profileImageUrl => state.profileImageUrl;
  String? get errorMessage => state.errorMessage;
  int get sessionId => state.sessionId;

  Future<bool> login({required String loginId, required String password}) =>
      _notifier.login(loginId: loginId, password: password);

  Future<bool> updateNickname({required String nickname}) =>
      _notifier.updateNickname(nickname: nickname);

  Future<bool> updateProfileImage({required String filePath}) =>
      _notifier.updateProfileImage(filePath: filePath);

  Future<bool> deleteProfileImage() => _notifier.deleteProfileImage();

  Future<void> restoreSession() => _notifier.restoreSession();

  Future<void> retryRestoreSession() => _notifier.retryRestoreSession();

  Future<void> logout() => _notifier.logout();

  Future<void> clearSession() => _notifier.clearSession();

  Future<T> runAuthorizedRequest<T>(
    Future<T> Function(String authorizationHeader) request,
  ) => _notifier.runAuthorizedRequest<T>(request);

  /// 인증 상태가 든 컨테이너를 폐기한다(기존 `AuthProvider.dispose`에 해당).
  @override
  void dispose() {
    _subscription.close();
    container.dispose();
    super.dispose();
  }
}
