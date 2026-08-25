import 'package:flutter/foundation.dart';

import '../repositories/auth/auth_repository.dart';
import '../core/network/api_exception.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? authRepository})
    : _authRepository = authRepository ?? AuthRepository();

  final AuthRepository _authRepository;

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isAuthenticated = false;

  int? _userId;
  String? _email;
  String? _errorMessage;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;

  int? get userId => _userId;
  String? get email => _email;
  String? get errorMessage => _errorMessage;

  /// 로그인
  Future<bool> login({required String email, required String password}) async {
    if (_isLoading) {
      return false;
    }

    _setLoading(true);
    _errorMessage = null;

    try {
      final response = await _authRepository.login(
        email: email,
        password: password,
      );

      _userId = response.id;
      _email = response.email;
      _isAuthenticated = true;

      notifyListeners();

      return true;
    } catch (error) {
      debugPrint('로그인 실패: $error');

      _isAuthenticated = false;
      _errorMessage = error.toString();

      notifyListeners();

      return false;
    } finally {
      _setLoading(false);
    }
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
        // 1. 기존 Access Token으로 현재 사용자 조회
        final user = await _authRepository.getCurrentUser();

        _userId = user.id;
        _email = user.email;
        _isAuthenticated = true;
      } on ApiException catch (error) {
        // 2. Access Token이 만료되었거나 인증되지 않은 경우
        if (error.statusCode == 401) {
          debugPrint('Access Token 인증 실패. Refresh Token으로 재발급을 시도합니다.');

          // 새 Access Token 발급 + Secure Storage 저장
          await _authRepository.refreshAccessToken();

          // 3. 새 Access Token으로 /users/me 다시 요청
          final user = await _authRepository.getCurrentUser();

          _userId = user.id;
          _email = user.email;
          _isAuthenticated = true;

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
