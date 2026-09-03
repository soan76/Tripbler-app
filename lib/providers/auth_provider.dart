import 'package:flutter/foundation.dart';

import '../repositories/auth/auth_repository.dart';
import '../models/user/user_response.dart';
import '../core/network/api_exception.dart';
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
  /// 현재 로그인 사용자의 Google 계정 연동 상태
  bool? _googleLinked;
  /// 현재 로그인 사용자의 정보
  int? _userId;
  String? _loginId;
  String? _nickname;
  String? _errorMessage;
  bool? _isLoginIdAvailable;
  String? _checkedLoginId;
  String? _loginIdCheckMessage;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isCheckingLoginId => _isCheckingLoginId;
  bool get isLoadingSocialAccounts => _isLoadingSocialAccounts;
  bool? get googleLinked => _googleLinked;

  int? get userId => _userId;
  String? get loginId => _loginId;
  String? get nickname => _nickname;
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
    _isAuthenticated = true;
  }

  /// 앱 시작 시 저장된 인증정보 확인
  ///
  /// 현재 단계에서는 Access Token / Refresh Token의
  /// 저장 여부를 기준으로 로그인 상태를 복구한다.
  ///
  /// 실제 Refresh Token 유효성 검증 및 자동 재발급은
  /// 이후 단계에서 추가한다.
  Future<void> restoreSession() async {
    if (_isInitialized) {
      return;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      final hasTokens = await _authRepository.hasTokens();

      if (!hasTokens) {
        _clearUserState();
        return;
      }

      try {
        // 기존 Access Token으로 현재 사용자 조회
        final user = await _authRepository.getCurrentUser();

        _setCurrentUser(user);
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          debugPrint('Access Token 인증 실패. Refresh Token으로 재발급을 시도합니다.');

          await _authRepository.refreshAccessToken();

          final user = await _authRepository.getCurrentUser();

          _setCurrentUser(user);

          debugPrint('Access Token 재발급 후 세션 복구 성공');
        } else {
          rethrow;
        }
      }
    } catch (error) {
      debugPrint('인증 상태 복구 실패: $error');

      // Refresh Token까지 사용할 수 없거나
      // 사용자 조회에 최종적으로 실패한 경우 세션 제거
      await _authRepository.clearTokens();

      _clearUserState();
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
      // AuthRepository에서 서버 로그아웃 성공 여부와 관계없이
      // 로컬 토큰을 제거하므로 Flutter 인증 상태도 로그아웃으로 변경한다.
      _clearUserState();

      _setLoading(false);
    }
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

    notifyListeners();
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
  void _clearUserState() {
    _isAuthenticated = false;

    _userId = null;
    _loginId = null;
    _nickname = null;
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
    _authRepository.dispose();
    super.dispose();
  }
}