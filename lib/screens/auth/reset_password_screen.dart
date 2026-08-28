import 'package:flutter/material.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String loginId;

  const ResetPasswordScreen({super.key, required this.loginId});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _passwordConfirmController =
      TextEditingController();

  bool _passwordHasError = false;
  bool _passwordConfirmHasError = false;

  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordConfirmController.dispose();

    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToLogin() {
    final password = _passwordController.text;
    final passwordConfirm = _passwordConfirmController.text;

    final passwordEmpty = password.isEmpty;
    final passwordConfirmEmpty = passwordConfirm.isEmpty;

    if (passwordEmpty || passwordConfirmEmpty) {
      setState(() {
        _passwordHasError = passwordEmpty;
        _passwordConfirmHasError = passwordConfirmEmpty;
      });

      _showMessage('새 비밀번호를 모두 입력해 주세요.');
      return;
    }

    if (password != passwordConfirm) {
      setState(() {
        _passwordHasError = true;
        _passwordConfirmHasError = true;
      });

      _showMessage('새 비밀번호가 일치하지 않습니다.');
      return;
    }

    setState(() {
      _passwordHasError = false;
      _passwordConfirmHasError = false;
    });

    FocusScope.of(context).unfocus();

    // TODO:
    // 이후 백엔드 비밀번호 재설정 API를 호출한다.
    //
    // 현재는 UI 구현 단계이므로
    // 비밀번호 검증 후 로그인 화면으로 돌아간다.

    Navigator.of(context).pop();
    Navigator.of(context).pop();
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
          '비밀번호 재설정',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),

                  Text(
                    '비밀번호 재설정',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 48),

                  _buildPasswordRow(
                    context,
                    label: '새 비밀번호',
                    controller: _passwordController,
                    hasError: _passwordHasError,
                    obscureText: _obscurePassword,
                    onVisibilityPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    onChanged: () {
                      if (_passwordHasError) {
                        setState(() {
                          _passwordHasError = false;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 20),

                  _buildPasswordRow(
                    context,
                    label: '새 비밀번호 확인',
                    controller: _passwordConfirmController,
                    hasError: _passwordConfirmHasError,
                    obscureText: _obscurePasswordConfirm,
                    onVisibilityPressed: () {
                      setState(() {
                        _obscurePasswordConfirm = !_obscurePasswordConfirm;
                      });
                    },
                    onChanged: () {
                      if (_passwordConfirmHasError) {
                        setState(() {
                          _passwordConfirmHasError = false;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 40),

                  Divider(color: colorScheme.outlineVariant),

                  const SizedBox(height: 24),

                  Center(
                    child: SizedBox(
                      width: 220,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _goToLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '로그인 화면으로 넘어가기',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordRow(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required bool hasError,
    required bool obscureText,
    required VoidCallback onVisibilityPressed,
    required VoidCallback onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),

        Expanded(
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) {
              onChanged();
            },
            decoration: _buildInputDecoration(
              context,
              hintText: '비밀번호를 입력하세요',
              hasError: hasError,
              suffixIcon: IconButton(
                onPressed: onVisibilityPressed,
                icon: Icon(
                  obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(
    BuildContext context, {
    required String hintText,
    required bool hasError,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: hasError ? colorScheme.error : colorScheme.outlineVariant,
          width: hasError ? 1.5 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: hasError ? colorScheme.error : colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }
}