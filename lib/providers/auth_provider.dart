import 'package:flutter/foundation.dart';

import '../repositories/auth/auth_repository.dart';
import '../models/user/user_response.dart';
import '../core/network/api_exception.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? authRepository})
    : _authRepository = authRepository ?? AuthRepository();

  final AuthRepository _authRepository;

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  bool _isCheckingLoginId = false;

  int? _userId;
  String? _loginId;
  String? _nickname;
  String? _email;
  String? _errorMessage;
  bool? _isLoginIdAvailable;
  String? _checkedLoginId;
  String? _loginIdCheckMessage;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isCheckingLoginId => _isCheckingLoginId;

  int? get userId => _userId;
  String? get loginId => _loginId;
  String? get nickname => _nickname;
  String? get email => _email;
  String? get errorMessage => _errorMessage;
  bool? get isLoginIdAvailable => _isLoginIdAvailable;
  String? get checkedLoginId => _checkedLoginId;
  String? get loginIdCheckMessage => _loginIdCheckMessage;

  /// 회원가입
  Future<bool> signup({
    required String loginId,
    required String nickname,
    required String email,
    required String password,
  }) async {
    if (_isLoading) {
      return false;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      await _authRepository.signup(
        loginId: loginId,
        nickname: nickname,
        email: email,
        password: password,
      );

      return true;
    } catch (error) {
      debugPrint('회원가입 실패: $error');

      _errorMessage = error.toString();
      notifyListeners();

      return false;
    } finally {
      _setLoading(false);
    }
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
  Future<bool> login({
    required String loginId,
    required String password,
  }) async {
    if (_isLoading) {
      return false;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      await _authRepository.login(loginId: loginId, password: password);

      // 로그인 성공 후 /users/me 호출
      // → loginId, nickname, email 등 현재 사용자 정보 조회
      final user = await _authRepository.getCurrentUser();

      _setCurrentUser(user);

      notifyListeners();

      return true;
    } catch (error) {
      debugPrint('로그인 실패: $error');

      _clearUserState();
      _errorMessage = error.toString();

      notifyListeners();

      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setCurrentUser(UserResponse user) {
    _userId = user.id;
    _loginId = user.loginId;
    _nickname = user.nickname;
    _email = user.email;
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
        _isAuthenticated = false;
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

  /// 로그아웃
  Future<void> logout() async {
    if (_isLoading) {
      return;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      await _authRepository.logout();
    } catch (error) {
      debugPrint('로그아웃 API 호출 실패: $error');

      _errorMessage = error.toString();
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

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  void _clearUserState() {
    _isAuthenticated = false;

    _userId = null;
    _loginId = null;
    _nickname = null;
    _email = null;
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authRepository.dispose();
    super.dispose();
  }
}
