import 'package:flutter/material.dart';

class NailPainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final Color nailColor;

  NailPainter({required this.polygons, required this.nailColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (polygons.isEmpty) return;

    for (var polygon in polygons) {
      if (polygon.length < 3) continue;

      final path = Path();
      path.moveTo(polygon.first.dx, polygon.first.dy);
      for (int i = 1; i < polygon.length; i++) {
        path.lineTo(polygon[i].dx, polygon[i].dy);
      }
      path.close();

      canvas.save();
      // Cắt khuôn móng tay (Clipping)
      canvas.clipPath(path);

      // 1. Phủ màu móng gel (BlendMode.multiply giúp giữ độ bóng móng gốc)
      final Paint paint = Paint()
        ..color = nailColor.withOpacity(0.85)
        ..blendMode = BlendMode.multiply;
      canvas.drawPath(path, paint);

      // 2. Tạo hiệu ứng bóng móng long lanh (Glossy Top Coat)
      final Paint glossPaint = Paint()
        ..shader = LinearGradient(
          colors: [Colors.white.withOpacity(0.4), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(path.getBounds())
        ..blendMode = BlendMode.screen;
      canvas.drawPath(path, glossPaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant NailPainter oldDelegate) =>
      oldDelegate.polygons != polygons || oldDelegate.nailColor != nailColor;
}
