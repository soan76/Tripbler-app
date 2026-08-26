import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _loginIdController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _passwordConfirmController =
      TextEditingController();

  final TextEditingController _nicknameController = TextEditingController();

  final TextEditingController _emailLocalController = TextEditingController();

  final TextEditingController _emailDomainController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nicknameController.dispose();
    _emailLocalController.dispose();
    _emailDomainController.dispose();

    super.dispose();
  }

  Future<void> _signup() async {
    final loginId = _loginIdController.text.trim();

    final password = _passwordController.text;

    final passwordConfirm = _passwordConfirmController.text;

    final nickname = _nicknameController.text.trim();

    final emailLocal = _emailLocalController.text.trim();

    final emailDomain = _emailDomainController.text.trim();

    final authProvider = context.read<AuthProvider>();

    if (!authProvider.isLoginIdCheckedAndAvailable(loginId)) {
      _showMessage('아이디 중복확인을 해주세요.');
      return;
    }

    // 필수값 검사
    if (loginId.isEmpty ||
        password.isEmpty ||
        passwordConfirm.isEmpty ||
        nickname.isEmpty ||
        emailLocal.isEmpty ||
        emailDomain.isEmpty) {
      _showMessage('모든 정보를 입력해 주세요.');
      return;
    }

    // 아이디 길이
    if (loginId.length < 4 || loginId.length > 30) {
      _showMessage('아이디는 4자 이상 30자 이하여야 합니다.');
      return;
    }

    // 비밀번호 길이
    if (password.length < 8 || password.length > 72) {
      _showMessage('비밀번호는 8자 이상 72자 이하여야 합니다.');
      return;
    }

    // 비밀번호 확인
    if (password != passwordConfirm) {
      _showMessage('비밀번호가 일치하지 않습니다.');
      return;
    }

    // 닉네임 길이
    if (nickname.length < 2 || nickname.length > 20) {
      _showMessage('닉네임은 2자 이상 20자 이하여야 합니다.');
      return;
    }

    final email = '$emailLocal@$emailDomain';

    FocusScope.of(context).unfocus();

    final success = await authProvider.signup(
      loginId: loginId,
      nickname: nickname,
      email: email,
      password: password,
    );

    if (!mounted) {
      return;
    }

    if (success) {
      Navigator.of(context).pop(true);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          '회원가입',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '회원가입을 위해 정보를 입력하세요',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 아이디
                  _buildLabel(context, '아이디'),

                  const SizedBox(height: 6),

                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _loginIdController,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              enabled: !authProvider.isLoading,
                              onChanged: (_) {
                                authProvider.resetLoginIdAvailability();
                              },
                              decoration: _buildInputDecoration(
                                context: context,
                                hintText: '아이디를 입력하세요',
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          SizedBox(
                            height: 56,
                            child: OutlinedButton(
                              onPressed:
                                  authProvider.isCheckingLoginId ||
                                      authProvider.isLoading
                                  ? null
                                  : () {
                                      FocusScope.of(context).unfocus();

                                      authProvider.checkLoginIdAvailability(
                                        _loginIdController.text,
                                      );
                                    },
                              child: authProvider.isCheckingLoginId
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      '중복확인',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // 아이디 중복확인 결과
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      final message = authProvider.loginIdCheckMessage;

                      if (message == null) {
                        return const SizedBox.shrink();
                      }

                      final isAvailable =
                          authProvider.isLoginIdAvailable == true;

                      return Padding(
                        padding: const EdgeInsets.only(top: 6, left: 2),
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isAvailable
                                ? colorScheme.primary
                                : colorScheme.error,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 18),

                  // 비밀번호
                  _buildLabel(context, '비밀번호'),

                  const SizedBox(height: 6),

                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    decoration: _buildInputDecoration(
                      context: context,
                      hintText: '비밀번호를 입력하세요',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 비밀번호 확인
                  _buildLabel(context, '비밀번호 확인'),

                  const SizedBox(height: 6),

                  TextField(
                    controller: _passwordConfirmController,
                    obscureText: _obscurePasswordConfirm,
                    textInputAction: TextInputAction.next,
                    decoration: _buildInputDecoration(
                      context: context,
                      hintText: '비밀번호를 다시 입력하세요',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePasswordConfirm = !_obscurePasswordConfirm;
                          });
                        },
                        icon: Icon(
                          _obscurePasswordConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 닉네임
                  _buildLabel(context, '닉네임'),

                  const SizedBox(height: 6),

                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    decoration: _buildInputDecoration(
                      context: context,
                      hintText: '닉네임을 입력하세요',
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 이메일 주소
                  _buildLabel(context, '이메일 주소'),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailLocalController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: _buildInputDecoration(
                            context: context,
                            hintText: '이메일',
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '@',
                          style: TextStyle(
                            fontSize: 18,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),

                      Expanded(
                        child: TextField(
                          controller: _emailDomainController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          decoration: _buildInputDecoration(
                            context: context,
                            hintText: '도메인',
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  // 회원가입 버튼
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: authProvider.isLoading ? null : _signup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: authProvider.isLoading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Text(
                                  '회원가입',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),

                  // 회원가입 API 오류
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      final errorMessage = authProvider.errorMessage;

                      if (errorMessage == null) {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          errorMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.error,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 36),

                  // 다른 서비스 회원가입 구분선
                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: colorScheme.outlineVariant),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '또는 다른 서비스 계정으로 회원가입',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),

                      Expanded(
                        child: Divider(color: colorScheme.outlineVariant),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // TODO:
                  // Google / Naver 등
                  // 다른 서비스 계정 회원가입 구현
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;

    return Text(
      text,
      textAlign: TextAlign.left,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required BuildContext context,
    required String hintText,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      hintText: hintText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surface,
      hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    );
  }
}
