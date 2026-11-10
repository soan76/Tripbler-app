import 'package:flutter/foundation.dart';

import '../repositories/auth/auth_repository.dart';
import '../models/user/user_response.dart';
import '../core/network/api_exception.dart';

/// 로그인이 필요한 요청을 토큰과 함께 실행하는 함수 형식.
/// [AuthProvider.runAuthorizedRequest]를 다른 Provider에 넘길 때 쓴다.
typedef AuthorizedRequestRunner =
    Future<T> Function<T>(
      Future<T> Function(String authorizationHeader) request,
    );

/// 앱의 인증 상태를 관리하는 ChangeNotifier 기반 클래스
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? authRepository})
    : _authRepository = authRepository ?? AuthRepository();

  final AuthRepository _authRepository;

  /// 앱 초기화 시 인증 상태를 복구했는지 여부
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  bool _isCheckingLoginId = false;
  bool _isLoadingSocialAccounts = false;
  bool _isDisposed = false;

  /// 세션 만료가 확인되지 않은 오류로 세션 복구에 실패해 토큰을 남겨 둔 상태.
  /// 화면은 상단 배너로 다시 시도([retryRestoreSession])를 안내한다.
  bool _sessionRestoreFailed = false;

  /// 현재 로그인 사용자의 Google 계정 연동 상태
  bool? _googleLinked;

  /// 현재 로그인 사용자의 정보
  int? _userId;
  String? _loginId;
  String? _nickname;
  String? _profileImageUrl;
  String? _errorMessage;
  bool? _isLoginIdAvailable;
  String? _checkedLoginId;
  String? _loginIdCheckMessage;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isCheckingLoginId => _isCheckingLoginId;
  bool get isLoadingSocialAccounts => _isLoadingSocialAccounts;
  bool get sessionRestoreFailed => _sessionRestoreFailed;
  bool? get googleLinked => _googleLinked;

  int? get userId => _userId;
  String? get loginId => _loginId;
  String? get nickname => _nickname;
  String? get profileImageUrl => _profileImageUrl;
  String? get errorMessage => _errorMessage;
  bool? get isLoginIdAvailable => _isLoginIdAvailable;
  String? get checkedLoginId => _checkedLoginId;
  String? get loginIdCheckMessage => _loginIdCheckMessage;

  /// 회원가입
  Future<bool> signup({
    required String loginId,
    String? nickname,
    required String password,
  }) {
    return _runGuardedAction(
      action: () async {
        await _authRepository.signup(
          loginId: loginId,
          nickname: nickname,
          password: password,
        );
      },
      logPrefix: '회원가입 실패',
      fallbackErrorMessage: '회원가입 중 오류가 발생했습니다.',
    );
  }

  /// 아이디 중복확인
  Future<void> checkLoginIdAvailability(String loginId) async {
    final trimmedLoginId = loginId.trim();

    if (_isCheckingLoginId) {
      return;
    }

    if (trimmedLoginId.isEmpty) {
      _isLoginIdAvailable = null;
      _checkedLoginId = null;
      _loginIdCheckMessage = '아이디를 입력해 주세요.';
      notifyListeners();
      return;
    }

    if (trimmedLoginId.length < 4 || trimmedLoginId.length > 30) {
      _isLoginIdAvailable = null;
      _checkedLoginId = null;
      _loginIdCheckMessage = '아이디는 4자 이상 30자 이하여야 합니다.';
      notifyListeners();
      return;
    }

    _isCheckingLoginId = true;
    _isLoginIdAvailable = null;
    _checkedLoginId = null;
    _loginIdCheckMessage = null;

    notifyListeners();

    try {
      final response = await _authRepository.checkLoginIdAvailability(
        trimmedLoginId,
      );

      _checkedLoginId = response.loginId;
      _isLoginIdAvailable = response.available;

      _loginIdCheckMessage = response.available
          ? '사용 가능한 아이디입니다.'
          : '이미 사용 중인 아이디입니다.';
    } catch (error) {
      debugPrint('아이디 중복확인 실패: $error');

      _isLoginIdAvailable = null;
      _checkedLoginId = null;
      _loginIdCheckMessage = '아이디 중복확인에 실패했습니다.';
    } finally {
      _isCheckingLoginId = false;
      notifyListeners();
    }
  }

  void resetLoginIdAvailability() {
    if (_isLoginIdAvailable == null &&
        _checkedLoginId == null &&
        _loginIdCheckMessage == null) {
      return;
    }

    _isLoginIdAvailable = null;
    _checkedLoginId = null;
    _loginIdCheckMessage = null;

    notifyListeners();
  }

  bool isLoginIdCheckedAndAvailable(String loginId) {
    return _isLoginIdAvailable == true && _checkedLoginId == loginId.trim();
  }

  /// 로그인
  Future<bool> login({required String loginId, required String password}) {
    return _runGuardedAction(
      action: () async {
        await _authRepository.login(loginId: loginId, password: password);

        // 로그인 성공 후 /users/me 호출
        // → loginId, nickname 등 현재 사용자 정보 조회
        final user = await _authRepository.getCurrentUser();

        _setCurrentUser(user);
      },
      logPrefix: '로그인 실패',
      fallbackErrorMessage: '로그인 중 오류가 발생했습니다.',
      onFailure: _clearUserState,
    );
  }

  void _setCurrentUser(UserResponse user) {
    _userId = user.id;
    _loginId = user.loginId;
    _nickname = user.nickname;
    _profileImageUrl = user.profileImageUrl;
    _isAuthenticated = true;
    _sessionRestoreFailed = false;
  }

  /// 현재 로그인 사용자의 닉네임을 변경한다.
  ///
  /// 서버에서 반환한 최신 사용자 정보를 Provider 상태에 반영한다.
  Future<bool> updateNickname({required String nickname}) {
    return _runGuardedAction(
      canRun: _isAuthenticated,
      action: () async {
        final user = await _authRepository.updateNickname(
          nickname: nickname.trim(),
        );

        _setCurrentUser(user);
      },
      logPrefix: '닉네임 변경 실패',
      fallbackErrorMessage: '닉네임 변경 중 오류가 발생했습니다.',
    );
  }

  /// 현재 로그인 사용자의 프로필 이미지를 변경한다.
  ///
  /// 서버에서 반환한 최신 사용자 정보를 Provider 상태에 반영한다.
  Future<bool> updateProfileImage({required String filePath}) {
    return _runGuardedAction(
      canRun: _isAuthenticated,
      action: () async {
        final user = await _authRepository.updateProfileImage(
          filePath: filePath,
        );

        _setCurrentUser(user);
      },
      logPrefix: '프로필 이미지 변경 실패',
      fallbackErrorMessage: '프로필 이미지 변경 중 오류가 발생했습니다.',
    );
  }

  /// 현재 로그인 사용자의 프로필 이미지를 삭제한다.
  Future<bool> deleteProfileImage() {
    return _runGuardedAction(
      canRun: _isAuthenticated,
      action: () async {
        await _authRepository.deleteProfileImage();

        _profileImageUrl = null;
      },
      logPrefix: '프로필 이미지 삭제 실패',
      fallbackErrorMessage: '프로필 이미지 삭제 중 오류가 발생했습니다.',
    );
  }

  /// 앱 시작 시 저장된 토큰으로 로그인 상태를 복구한다.
  ///
  /// - 세션 만료가 확인되면([AuthRepository.isSessionExpiredError]) 토큰을 지운다.
  /// - 그 밖의 실패(네트워크 오류, 5xx, 403, 재발급 뒤 401, 예상하지 못한 오류 등)는
  ///   토큰을 남기고 [sessionRestoreFailed]를 켠다. 화면은 상단 배너로
  ///   [retryRestoreSession]을 안내한다.
  /// - 복구 중 다른 계정으로 로그인되면 늦게 온 복구 결과는 버린다.
  Future<void> restoreSession() async {
    if (_isInitialized) {
      return;
    }

    await _restoreSessionFromStorage();
  }

  /// 일시적 장애로 실패한 세션 복구를 다시 시도한다(상단 배너의 다시 시도).
  Future<void> retryRestoreSession() async {
    if (!_sessionRestoreFailed || _isLoading) {
      return;
    }

    await _restoreSessionFromStorage();
  }

  Future<void> _restoreSessionFromStorage() async {
    _setLoading(true);
    _errorMessage = null;

    final sessionId = _authRepository.sessionId;

    try {
      final hasTokens = await _authRepository.hasTokens();

      if (_authRepository.sessionId != sessionId) {
        return;
      }

      if (!hasTokens) {
        _clearUserState();
        return;
      }

      // 401이면 getCurrentUser 안에서 같은 세션으로 재발급·재시도한다.
      final user = await _authRepository.getCurrentUser();

      if (_authRepository.sessionId != sessionId) {
        return;
      }

      _setCurrentUser(user);
    } on SessionChangedException {
      // 복구 중 로그아웃·재로그인됨: 늦게 온 복구 응답은 버린다.
    } catch (error) {
      debugPrint('인증 상태 복구 실패: $error');

      if (_authRepository.sessionId != sessionId) {
        return;
      }

      if (AuthRepository.isSessionExpiredError(error)) {
        // 세션 만료가 확인된 경우에만 토큰을 지운다.
        try {
          await _authRepository.clearTokensIfSession(sessionId);
        } catch (clearError) {
          debugPrint('토큰 삭제 실패: $clearError');
        }

        _clearUserState();
      } else {
        // 만료가 확인되지 않은 실패(네트워크 오류, 5xx, 403, 재발급 뒤 401 등)는
        // 로그인 정보를 잃지 않도록 토큰을 남기고 다시 시도를 안내한다.
        _clearUserState();
        _sessionRestoreFailed = true;
      }
    } finally {
      _isInitialized = true;
      _setLoading(false);
    }
  }

  /// 현재 사용자의 Google 계정 연동 상태를 조회한다.
  Future<void> loadLinkedSocialAccounts() async {
    if (!_isAuthenticated || _isLoadingSocialAccounts) {
      return;
    }

    _isLoadingSocialAccounts = true;
    notifyListeners();

    try {
      final response = await _authRepository.getLinkedSocialAccounts();

      _googleLinked = response.isLinked('GOOGLE');
    } catch (error) {
      debugPrint('소셜 계정 연동 상태 조회 실패: $error');
    } finally {
      _isLoadingSocialAccounts = false;
      notifyListeners();
    }
  }

  /// 현재 사용자에게 Google 계정을 연동한다.
  Future<bool> linkGoogleAccount() {
    return _runGuardedAction(
      action: () async {
        await _authRepository.linkGoogleAccount();
        _googleLinked = true;
      },
      logPrefix: 'Google 계정 연동 실패',
      fallbackErrorMessage: 'Google 계정 연동 중 오류가 발생했습니다.',
    );
  }

  /// 현재 사용자에게 연동된 Google 계정을 해제한다.
  Future<bool> unlinkGoogleAccount() {
    return _runGuardedAction(
      action: () async {
        await _authRepository.unlinkGoogleAccount();
        _googleLinked = false;
      },
      logPrefix: 'Google 계정 연동 해제 실패',
      fallbackErrorMessage: 'Google 계정 연동 해제 중 오류가 발생했습니다.',
    );
  }

  /// 현재 로그인 사용자의 계정을 탈퇴 처리한다.
  Future<bool> deleteAccount() {
    return _runGuardedAction(
      canRun: _isAuthenticated,
      action: () async {
        await _authRepository.deleteAccount();

        // 서버에서 계정 삭제가 완료된 경우
        // Flutter의 현재 사용자 상태도 비로그인으로 초기화한다.
        _clearUserState();
      },
      logPrefix: '계정 탈퇴 실패',
      fallbackErrorMessage: '계정 탈퇴 중 오류가 발생했습니다.',
    );
  }

  /// 로그아웃
  Future<void> logout() async {
    if (_isLoading) {
      return;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      await _authRepository.logout();
    } on ApiException catch (error) {
      debugPrint('로그아웃 API 호출 실패: $error');

      _errorMessage = error.message;
    } catch (error) {
      debugPrint('로그아웃 API 호출 실패: $error');

      _errorMessage = '로그아웃 중 오류가 발생했습니다.';
    } finally {
      // AuthRepository가 로컬 토큰을 먼저 지우고 서버 로그아웃은 따로 보내므로(로컬 우선)
      // 연결 상태와 관계없이 Flutter 인증 상태도 바로 로그아웃으로 바꾼다.
      _clearUserState();

      _setLoading(false);
    }
  }

  /// 로그인이 필요한 요청을 실행한다(장소 검색 등).
  ///
  /// 토큰 첨부, 401 재발급·재시도, 세션 확인은 [AuthRepository.authorizedRequest]가 맡는다.
  /// - 세션 만료가 확인되면([AuthRepository.isSessionExpiredError]) 요청을 시작한 세션이
  ///   아직 현재 세션일 때만 토큰을 지우고 로그인 상태를 해제한 뒤 [SessionExpiredException]을 던진다.
  ///   앱은 비로그인으로도 쓸 수 있으므로 화면 이동은 하지 않는다. 안내는 호출한 화면이 맡는다.
  /// - 요청 중 로그아웃·재로그인되면 [SessionChangedException]을 그대로 던진다.
  ///   호출부는 현재 화면의 데이터와 오류 문구를 그대로 두고 무시한다.
  /// - 그 밖의 오류(네트워크, 5xx 등)는 로그인 상태를 유지한 채 그대로 던진다.
  Future<T> runAuthorizedRequest<T>(
    Future<T> Function(String authorizationHeader) request,
  ) async {
    final sessionId = _authRepository.sessionId;

    try {
      return await _authRepository.authorizedRequest<T>(request);
    } on SessionChangedException {
      rethrow;
    } catch (error) {
      if (!AuthRepository.isSessionExpiredError(error)) {
        rethrow;
      }

      final isSameSession =
          !_isDisposed &&
          _isAuthenticated &&
          _authRepository.sessionId == sessionId;

      if (isSameSession) {
        debugPrint('세션 만료 확인: 로그인 상태를 해제합니다.');

        await _endExpiredSession(sessionId);
      }

      throw SessionExpiredException(sessionId);
    }
  }

  /// 만료된 세션이 아직 현재 세션일 때만 토큰을 지우고 로그인 상태를 해제한다.
  Future<void> _endExpiredSession(int sessionId) async {
    bool cleared;

    try {
      cleared = await _authRepository.clearTokensIfSession(sessionId);
    } catch (error) {
      // 저장소 삭제가 실패해도 세션 번호는 이미 바뀌었으므로 상태는 해제한다.
      debugPrint('토큰 삭제 실패: $error');
      cleared = true;
    }

    if (!cleared || _isDisposed) {
      return;
    }

    _clearUserState();
    notifyListeners();
  }

  /// 인증 상태를 강제로 해제할 때 사용
  ///
  /// 추후 Refresh Token 만료 등에서 사용할 수 있다.
  Future<void> clearSession() async {
    try {
      await _authRepository.clearTokens();
    } catch (error) {
      debugPrint('토큰 삭제 실패: $error');
    }

    _clearUserState();

    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// 인증 관련 단일 작업의 로딩 상태와 예외 처리를 공통으로 관리한다.
  ///
  /// 상태 변경은 action / onFailure에서 수행하고,
  /// UI 알림은 작업 종료 시 _setLoading(false)를 통해 한 번에 반영한다.
  Future<bool> _runGuardedAction({
    required Future<void> Function() action,
    required String logPrefix,
    required String fallbackErrorMessage,
    VoidCallback? onFailure,
    bool canRun = true,
  }) async {
    if (_isLoading || !canRun) {
      return false;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      await action();
      return true;
    } on SessionChangedException {
      // 이전 세션에서 시작한 작업: 현재 화면의 데이터와 오류 문구를 그대로 둔다.
      debugPrint('$logPrefix: 로그인 세션이 바뀌어 결과를 반영하지 않습니다.');

      return false;
    } on ApiException catch (error) {
      debugPrint('$logPrefix: $error');

      onFailure?.call();
      _errorMessage = error.message;

      return false;
    } catch (error) {
      debugPrint('$logPrefix: $error');

      onFailure?.call();
      _errorMessage = fallbackErrorMessage;

      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 인증 관련 예외 메시지를 초기화한다.
  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  /// 현재 로그인 사용자의 상태를 초기화한다.
  ///
  /// 세션 번호는 [AuthRepository]가 토큰 저장·삭제와 함께 관리한다.
  void _clearUserState() {
    _isAuthenticated = false;
    _sessionRestoreFailed = false;

    _userId = null;
    _loginId = null;
    _nickname = null;
    _profileImageUrl = null;
    _googleLinked = null;
  }

  /// 로딩 상태를 변경하고 ChangeNotifier에 알린다.
  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;
    notifyListeners();
  }

  /// AuthProvider를 더 이상 사용하지 않을 때 호출한다.
  @override
  void dispose() {
    _isDisposed = true;
    _authRepository.dispose();
    super.dispose();
  }
}
