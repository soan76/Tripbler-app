import 'package:flutter/material.dart';

import '../../models/map/scale_bar_data.dart';

class MapScaleBar extends StatelessWidget {
  final ScaleBarData data;
  final String label;

  const MapScaleBar({super.key, required this.data, required this.label});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Scale Bar가 지도 드래그/확대/축소 터치를 막지 않도록 터치 이벤트를 무시함.
      ignoring: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: data.widthPx,
              height: 6,
              child: CustomPaint(painter: _ScaleBarPainter()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScaleBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double strokeWidth = 2;

    final Paint paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final double y = size.height - strokeWidth;

    // Scale Bar 가로선
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);

    // Scale Bar 왼쪽 끝선
    canvas.drawLine(Offset(0, y), Offset(0, 0), paint);

    // Scale Bar 오른쪽 끝선
    canvas.drawLine(Offset(size.width, y), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant _ScaleBarPainter oldDelegate) {
    return false;
  }
}
