import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider;

import 'auth_provider.dart';

/// 회원가입 화면의 아이디 중복확인 상태.
class LoginIdCheckState {
  const LoginIdCheckState({
    this.isCheckingLoginId = false,
    this.isLoginIdAvailable,
    this.checkedLoginId,
    this.loginIdCheckMessage,
  });

  final bool isCheckingLoginId;
  final bool? isLoginIdAvailable;
  final String? checkedLoginId;
  final String? loginIdCheckMessage;

  bool isLoginIdCheckedAndAvailable(String loginId) {
    return isLoginIdAvailable == true && checkedLoginId == loginId.trim();
  }

  /// 아이디 중복확인 결과를 비운다. [message]를 주면 안내 문구만 남긴다.
  /// 확인 중 여부([isCheckingLoginId])는 그대로 둔다.
  LoginIdCheckState withoutLoginIdCheck({String? message}) {
    return LoginIdCheckState(
      isCheckingLoginId: isCheckingLoginId,
      loginIdCheckMessage: message,
    );
  }

  LoginIdCheckState copyWith({bool? isCheckingLoginId}) {
    return LoginIdCheckState(
      isCheckingLoginId: isCheckingLoginId ?? this.isCheckingLoginId,
      isLoginIdAvailable: isLoginIdAvailable,
      checkedLoginId: checkedLoginId,
      loginIdCheckMessage: loginIdCheckMessage,
    );
  }
}

/// 아이디 중복확인을 관리한다. 로그인 상태([authProvider])와는 따로 둔다.
class LoginIdCheckNotifier extends Notifier<LoginIdCheckState> {
  @override
  LoginIdCheckState build() => const LoginIdCheckState();

  /// 상태를 내보낸다. 상태 객체가 폐기된 뒤에는 아무것도 하지 않는다.
  void _emit(LoginIdCheckState next) {
    if (!ref.mounted) {
      return;
    }

    state = next;
  }

  /// 아이디 중복확인
  Future<void> checkLoginIdAvailability(String loginId) async {
    final trimmedLoginId = loginId.trim();

    if (state.isCheckingLoginId) {
      return;
    }

    if (trimmedLoginId.isEmpty) {
      _emit(state.withoutLoginIdCheck(message: '아이디를 입력해 주세요.'));
      return;
    }

    if (trimmedLoginId.length < 4 || trimmedLoginId.length > 30) {
      _emit(state.withoutLoginIdCheck(message: '아이디는 4자 이상 30자 이하여야 합니다.'));
      return;
    }

    _emit(state.withoutLoginIdCheck().copyWith(isCheckingLoginId: true));

    LoginIdCheckState Function(LoginIdCheckState s) result;

    try {
      final response = await ref
          .read(authRepositoryProvider)
          .checkLoginIdAvailability(trimmedLoginId);

      result = (s) => LoginIdCheckState(
        isCheckingLoginId: s.isCheckingLoginId,
        checkedLoginId: response.loginId,
        isLoginIdAvailable: response.available,
        loginIdCheckMessage: response.available
            ? '사용 가능한 아이디입니다.'
            : '이미 사용 중인 아이디입니다.',
      );
    } catch (error) {
      debugPrint('아이디 중복확인 실패: $error');

      result = (s) => s.withoutLoginIdCheck(message: '아이디 중복확인에 실패했습니다.');
    }

    if (!ref.mounted) {
      return;
    }

    _emit(result(state).copyWith(isCheckingLoginId: false));
  }

  void resetLoginIdAvailability() {
    if (state.isLoginIdAvailable == null &&
        state.checkedLoginId == null &&
        state.loginIdCheckMessage == null) {
      return;
    }

    _emit(state.withoutLoginIdCheck());
  }
}

/// 아이디 중복확인 상태. 앱이 켜져 있는 동안 유지한다(지금까지 인증 상태에 있던 것과 같다).
final loginIdCheckProvider =
    NotifierProvider<LoginIdCheckNotifier, LoginIdCheckState>(
      LoginIdCheckNotifier.new,
    );
