import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/account_recovery_provider.dart';
import '../../utils/auth/reset_password_validator.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String resetToken;

  const ResetPasswordScreen({super.key, required this.resetToken});

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

  /// 입력값 검증 후 백엔드에 비밀번호 재설정을 요청한다.
  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    final passwordConfirm = _passwordConfirmController.text;

    // 비밀번호 입력 규칙은 ResetPasswordValidator에서 검사한다.
    final validationResult = ResetPasswordValidator.validate(
      password: password,
      passwordConfirm: passwordConfirm,
    );

    setState(() {
      _passwordHasError = validationResult.passwordHasError;
      _passwordConfirmHasError = validationResult.passwordConfirmHasError;
    });

    if (!validationResult.isValid) {
      _showMessage(validationResult.message ?? '비밀번호 입력값을 확인해 주세요.');

      return;
    }

    FocusScope.of(context).unfocus();

    final recoveryProvider = context.read<AccountRecoveryProvider>();

    final success = await recoveryProvider.resetPassword(
      resetToken: widget.resetToken,
      newPassword: password,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(recoveryProvider.errorMessage ?? '비밀번호 재설정에 실패했습니다.');

      return;
    }

    _showMessage('비밀번호가 변경되었습니다.');

    // ResetPasswordScreen 종료
    Navigator.of(context).pop();

    // FindPasswordScreen 종료
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final recoveryProvider = context.watch<AccountRecoveryProvider>();

    final isLoading = recoveryProvider.isLoading;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: isLoading
              ? null
              : () {
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

                  const SizedBox(height: 12),

                  Text(
                    '새로 사용할 비밀번호를 입력하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 48),

                  _buildPasswordRow(
                    context,
                    label: '새 비밀번호',
                    controller: _passwordController,
                    hasError: _passwordHasError,
                    obscureText: _obscurePassword,
                    enabled: !isLoading,
                    textInputAction: TextInputAction.next,
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
                    enabled: !isLoading,
                    textInputAction: TextInputAction.done,
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
                    onSubmitted: () {
                      if (!isLoading) {
                        _resetPassword();
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
                        onPressed: isLoading ? null : _resetPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          disabledBackgroundColor:
                              colorScheme.surfaceContainerHighest,
                          disabledForegroundColor: colorScheme.onSurfaceVariant,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '비밀번호 변경',
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
    required bool enabled,
    required TextInputAction textInputAction,
    required VoidCallback onVisibilityPressed,
    required VoidCallback onChanged,
    VoidCallback? onSubmitted,
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
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: textInputAction,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) {
              onChanged();
            },
            onSubmitted: (_) {
              onSubmitted?.call();
            },
            decoration: _buildInputDecoration(
              context,
              hintText: '비밀번호를 입력하세요',
              hasError: hasError,
              suffixIcon: IconButton(
                onPressed: enabled ? onVisibilityPressed : null,
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
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
    );
  }
}