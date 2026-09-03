import 'package:flutter/material.dart';
/// 계정 관련 섹션 위젯
class UserAccountSection extends StatelessWidget {
  const UserAccountSection({
    super.key,
    required this.googleLinked,
    required this.isLoading,
    required this.onChangePassword,
    required this.onChangeSocialAccount,
  });

  final bool? googleLinked;
  final bool isLoading;
  final VoidCallback onChangePassword;
  final VoidCallback onChangeSocialAccount;

  @override
  Widget build(BuildContext context) {
    final canInteract = !isLoading;

    return Column(
      children: [
        _buildSectionTitle(context, '계정'),

        _buildAccountRow(
          context,
          title: '비밀번호',
          value: '비밀번호 변경',
          trailing: _buildArrowTrailing(context, enabled: canInteract),
          onTap: canInteract ? onChangePassword : null,
        ),

        _buildAccountRow(
          context,
          title: '연동된 계정',
          value: _googleAccountStatusText(),
          trailing: OutlinedButton(
            onPressed: _canChangeGoogleAccount ? onChangeSocialAccount : null,
            child: Text(_googleAccountActionText()),
          ),
        ),
      ],
    );
  }
  /// Google 계정 연동 상태에 따라 연동/연동 해제 버튼 활성화 여부 결정
  bool get _canChangeGoogleAccount => googleLinked != null && !isLoading;

  String _googleAccountStatusText() {
    if (googleLinked == null) {
      return 'Google · 확인 중...';
    }

    return googleLinked! ? 'Google · 연동됨' : 'Google · 연동 안 됨';
  }

  String _googleAccountActionText() {
    return googleLinked == true ? '연동 해제' : '연동';
  }
  /// 섹션 제목 위젯
  Widget _buildSectionTitle(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
  /// 계정 정보 행 위젯
  Widget _buildAccountRow(
    BuildContext context, {
    required String title,
    required String value,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: TextStyle(color: colorScheme.onSurface)),
      subtitle: Text(
        value,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildArrowTrailing(BuildContext context, {required bool enabled}) {
    final theme = Theme.of(context);

    return Icon(
      Icons.chevron_right,
      color: enabled ? theme.colorScheme.onSurfaceVariant : theme.disabledColor,
    );
  }
}