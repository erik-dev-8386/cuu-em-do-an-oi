import 'package:flutter/material.dart';

class NailPainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final Color nailColor;
  final double? imageWidth;
  final double? imageHeight;

  NailPainter({
    required this.polygons,
    required this.nailColor,
    this.imageWidth,
    this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (polygons.isEmpty) return;

    final double scaleX = (imageWidth != null && imageWidth! > 0)
        ? size.width / imageWidth!
        : 1.0;
    final double scaleY = (imageHeight != null && imageHeight! > 0)
        ? size.height / imageHeight!
        : 1.0;

    for (var polygon in polygons) {
      if (polygon.length < 3) continue;

      final path = Path();
      final Offset firstScaled = Offset(
        polygon.first.dx * scaleX,
        polygon.first.dy * scaleY,
      );
      path.moveTo(firstScaled.dx, firstScaled.dy);

      for (int i = 1; i < polygon.length; i++) {
        path.lineTo(
          polygon[i].dx * scaleX,
          polygon[i].dy * scaleY,
        );
      }
      path.close();

      canvas.save();
      // Cắt khuôn móng tay (Clipping)
      canvas.clipPath(path);

      // 1. Phủ màu móng gel (BlendMode.multiply giúp giữ độ bóng móng gốc)
      final Paint paint = Paint()
        ..color = nailColor.withValues(alpha: 0.85)
        ..blendMode = BlendMode.multiply;
      canvas.drawPath(path, paint);

      // 2. Tạo hiệu ứng bóng móng long lanh (Glossy Top Coat)
      final Paint glossPaint = Paint()
        ..shader = LinearGradient(
          colors: [Colors.white.withValues(alpha: 0.4), Colors.transparent],
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
      oldDelegate.polygons != polygons ||
      oldDelegate.nailColor != nailColor ||
      oldDelegate.imageWidth != imageWidth ||
      oldDelegate.imageHeight != imageHeight;
}
