import 'package:flutter/material.dart';

class AccountDeletionDialog extends StatelessWidget {
  const AccountDeletionDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AccountDeletionDialog(),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '탈퇴 시 계정 정보가 소멸되며\n'
            '복구가 불가능합니다.\n\n'
            '정말로 탈퇴하시겠습니까?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.5),
          ),

          const SizedBox(height: 28),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFAFAFAB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '취소',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFEE7234),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '탈퇴',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AccountDeletionLoadingDialog extends StatelessWidget {
  const AccountDeletionLoadingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),

              SizedBox(height: 20),

              Text(
                '계정 탈퇴 처리 중...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
