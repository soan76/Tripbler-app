import 'package:flutter/material.dart';

/// 하단 메뉴 아이콘 상태의 치수(하단 가운데 기준). 설계: docs/mockups/bottom-nav-current-button.md
///
/// 메뉴 표면과 메뉴 위에 놓이는 화면(안내 문구 여백)이 같은 값을 쓰도록 한곳에 둔다.
abstract final class BottomMenuMetrics {
  /// 반투명 바깥 원의 지름과 화면 아래에서 띄운 거리.
  static const double outerSize = 74;
  static const double outerBottom = 12;

  /// 아이콘 상태에서 안쪽 불투명 버튼의 지름. 펼치면 부채꼴 버튼 크기(64, AI 76)로 커진다.
  static const double innerSize = 55;

  /// 안쪽 버튼 속 아이콘 그림의 크기. 그림은 버튼 정가운데에 둔다.
  static const double glyphSize = 22;

  /// 촬영 중 고리는 안쪽 버튼보다 지름이 이만큼 크다(둘레 4의 간격).
  static const double ringGrowth = 8;

  /// 아이콘 상태에서 안쪽 버튼(과 바깥 원)의 중심 높이. 부채꼴 버튼도 여기서 퍼진다.
  static const Offset iconCenter = Offset(0, outerBottom + outerSize / 2);

  /// 메뉴 위에 놓이는 화면이 하단 메뉴 원을 가리지 않게 맨 아래 내용 밑에 비워 둘 높이(원 위 끝 + 8).
  /// 촬영 안내 꼬리표는 2026-11-27 사용자 요청으로 없앴다.
  static const double contentClearance = outerBottom + outerSize + 8;
}

/// 촬영 중 안쪽 버튼 둘레에 도는 고리. 끌기 시작해 사라지는 동안에도 안쪽 버튼을 따라간다.
class BottomMenuCaptureRing extends StatelessWidget {
  const BottomMenuCaptureRing({
    super.key,
    required this.left,
    required this.bottom,
    required this.size,
    required this.opacity,
  });

  final double left, bottom, size, opacity;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Positioned(
      left: left,
      bottom: bottom,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: CircularProgressIndicator(
            key: const ValueKey('bottom-menu-capturing'),
            strokeWidth: 2.5,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: color.withValues(alpha: .2),
          ),
        ),
      ),
    );
  }
}
