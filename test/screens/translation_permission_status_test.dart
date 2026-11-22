import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tripbler/providers/translation/translation_provider.dart';
import 'package:tripbler/screens/translation_screen.dart';

// 카메라 권한 상태 → 번역 화면 상태 판단(blockedStatusFor) 표.
void main() {
  final cases =
      <
        ({
          PermissionStatus permission,
          bool hasRequested,
          TranslationStatus? expected,
        })
      >[
        (
          permission: PermissionStatus.granted,
          hasRequested: false,
          expected: null,
        ),
        (
          permission: PermissionStatus.granted,
          hasRequested: true,
          expected: null,
        ),
        (
          permission: PermissionStatus.denied,
          hasRequested: false,
          expected: TranslationStatus.permissionRequired,
        ),
        (
          permission: PermissionStatus.denied,
          hasRequested: true,
          expected: TranslationStatus.permissionDenied,
        ),
        (
          permission: PermissionStatus.permanentlyDenied,
          hasRequested: false,
          expected: TranslationStatus.permissionPermanentlyDenied,
        ),
        (
          permission: PermissionStatus.permanentlyDenied,
          hasRequested: true,
          expected: TranslationStatus.permissionPermanentlyDenied,
        ),
        (
          permission: PermissionStatus.restricted,
          hasRequested: false,
          expected: TranslationStatus.permissionPermanentlyDenied,
        ),
        (
          permission: PermissionStatus.restricted,
          hasRequested: true,
          expected: TranslationStatus.permissionPermanentlyDenied,
        ),
      ];

  for (final c in cases) {
    test('${c.permission.name}, 요청 ${c.hasRequested ? '후' : '전'} → '
        '${c.expected?.name ?? '허용(null)'}', () {
      expect(
        blockedStatusFor(c.permission, hasRequested: c.hasRequested),
        c.expected,
      );
    });
  }
}
