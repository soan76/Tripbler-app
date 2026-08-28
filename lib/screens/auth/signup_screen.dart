import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../utils/auth/signup_validator.dart';
import '../../widgets/auth/signup/signup_form_label.dart';
import '../../widgets/auth/signup/signup_input_decoration.dart';
import '../../widgets/auth/signup/signup_login_id_field.dart';
import '../../widgets/auth/signup/signup_password_fields.dart';

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

  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  bool _loginIdHasError = false;
  bool _passwordHasError = false;
  bool _passwordConfirmHasError = false;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nicknameController.dispose();

    super.dispose();
  }

  Future<void> _signup() async {
    final loginId = _loginIdController.text.trim();
    final password = _passwordController.text;
    final passwordConfirm = _passwordConfirmController.text;
    final nickname = _nicknameController.text.trim();

    final authProvider = context.read<AuthProvider>();

    final validation = SignupValidator.validate(
      loginId: loginId,
      password: password,
      passwordConfirm: passwordConfirm,
      nickname: nickname,
    );

    if (!validation.isValid) {
      setState(() {
        _loginIdHasError = validation.loginIdHasError;
        _passwordHasError = validation.passwordHasError;
        _passwordConfirmHasError = validation.passwordConfirmHasError;
      });

      if (validation.message != null) {
        _showMessage(validation.message!);
      }

      return;
    }

    // 아이디 중복확인
    if (!authProvider.isLoginIdCheckedAndAvailable(loginId)) {
      setState(() {
        _loginIdHasError = true;
      });

      _showMessage('아이디 중복확인을 해주세요.');
      return;
    }

    _clearFieldErrors();

    FocusScope.of(context).unfocus();

    final success = await authProvider.signup(
      loginId: loginId,
      nickname: nickname.isEmpty ? null : nickname,
      password: password,
    );

    if (!mounted) {
      return;
    }

    if (success) {
      Navigator.of(context).pop(true);
      return;
    }

    final message = authProvider.errorMessage;

    if (message != null) {
      _showMessage(message);
    }
  }

  void _clearFieldErrors() {
    setState(() {
      _loginIdHasError = false;
      _passwordHasError = false;
      _passwordConfirmHasError = false;
    });
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(SnackBar(content: Text(message)));
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
                  SignupLoginIdField(
                    controller: _loginIdController,
                    hasError: _loginIdHasError,
                    onChanged: (_) {
                      if (_loginIdHasError) {
                        setState(() {
                          _loginIdHasError = false;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 18),

                  // 비밀번호 / 비밀번호 확인
                  SignupPasswordFields(
                    passwordController: _passwordController,
                    passwordConfirmController: _passwordConfirmController,
                    obscurePassword: _obscurePassword,
                    obscurePasswordConfirm: _obscurePasswordConfirm,
                    passwordHasError: _passwordHasError,
                    passwordConfirmHasError: _passwordConfirmHasError,
                    onPasswordChanged: (_) {
                      if (_passwordHasError) {
                        setState(() {
                          _passwordHasError = false;
                        });
                      }
                    },
                    onPasswordConfirmChanged: (_) {
                      if (_passwordConfirmHasError) {
                        setState(() {
                          _passwordConfirmHasError = false;
                        });
                      }
                    },
                    onTogglePasswordVisibility: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    onTogglePasswordConfirmVisibility: () {
                      setState(() {
                        _obscurePasswordConfirm = !_obscurePasswordConfirm;
                      });
                    },
                  ),

                  const SizedBox(height: 18),

                  // 닉네임
                  const SignupFormLabel(text: '닉네임'),

                  const SizedBox(height: 6),

                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.done,
                    decoration: buildSignupInputDecoration(
                      context: context,
                      hintText: '닉네임을 입력하세요',
                    ),
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
}
