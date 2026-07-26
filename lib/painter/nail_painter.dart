import 'dart:math';
import 'package:flutter/material.dart';
import '../models/nail_variant.dart';

class NailPainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final Color nailColor;
  final NailVariant? variant;
  final double? imageWidth;
  final double? imageHeight;

  NailPainter({
    required this.polygons,
    this.nailColor = const Color(0xFFFF4081),
    this.variant,
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

    final Color effectiveColor = variant?.primaryColor ?? nailColor;
    final SurfaceType surface = variant?.surfaceType ?? SurfaceType.glossy;

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
      // Clip to detected nail contour polygon
      canvas.clipPath(path);

      // 1. Fill base gel color with natural blending mode
      final Paint basePaint = Paint()
        ..color = effectiveColor.withValues(
            alpha: surface == SurfaceType.matte || surface == SurfaceType.satin ? 0.90 : 0.82)
        ..blendMode = BlendMode.multiply;
      canvas.drawPath(path, basePaint);

      final Rect bounds = path.getBounds();

      // 2. Render Surface Finish (Glossy, Matte, Glitter, CatEye, Chrome, Holographic, Pearl, Satin)
      switch (surface) {
        case SurfaceType.glossy:
          final Paint glossPaint = Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.45),
                Colors.white.withValues(alpha: 0.05),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds)
            ..blendMode = BlendMode.screen;
          canvas.drawPath(path, glossPaint);
          break;

        case SurfaceType.matte:
          final Paint matteOverlay = Paint()
            ..color = Colors.white.withValues(alpha: 0.08)
            ..blendMode = BlendMode.softLight;
          canvas.drawPath(path, matteOverlay);
          break;

        case SurfaceType.catEye:
          final Paint catEyePaint = Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.75),
                Colors.transparent,
              ],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds)
            ..blendMode = BlendMode.screen;
          canvas.drawPath(path, catEyePaint);
          break;

        case SurfaceType.chrome:
          final Paint chromePaint = Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.65),
                effectiveColor.withValues(alpha: 0.3),
                Colors.white.withValues(alpha: 0.85),
                Colors.black.withValues(alpha: 0.2),
              ],
              stops: const [0.0, 0.4, 0.7, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds)
            ..blendMode = BlendMode.screen;
          canvas.drawPath(path, chromePaint);
          break;

        case SurfaceType.glitter:
          final Random rnd = Random(bounds.left.toInt() + bounds.top.toInt());
          final Paint glitterPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..style = PaintingStyle.fill;
          for (int i = 0; i < 18; i++) {
            final double gx = bounds.left + rnd.nextDouble() * bounds.width;
            final double gy = bounds.top + rnd.nextDouble() * bounds.height;
            final double radius = 0.8 + rnd.nextDouble() * 1.5;
            if (path.contains(Offset(gx, gy))) {
              canvas.drawCircle(Offset(gx, gy), radius, glitterPaint);
            }
          }
          break;

        case SurfaceType.holographic:
          // Multi-color rainbow iridescent shine
          final Paint holoPaint = Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.cyanAccent,
                const Color(0xFFFF00FF),
                Colors.yellowAccent,
                Colors.cyanAccent,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds)
            ..colorFilter = ColorFilter.mode(
              Colors.white.withValues(alpha: 0.35),
              BlendMode.modulate,
            )
            ..blendMode = BlendMode.colorDodge;
          canvas.drawPath(path, holoPaint);
          break;

        case SurfaceType.pearl:
          // Soft iridescent pearlescent sheen
          final Paint pearlPaint = Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.6),
                Colors.pink.shade100.withValues(alpha: 0.3),
                Colors.cyan.shade100.withValues(alpha: 0.1),
              ],
              center: Alignment.topRight,
              radius: 0.85,
            ).createShader(bounds)
            ..blendMode = BlendMode.screen;
          canvas.drawPath(path, pearlPaint);
          break;

        case SurfaceType.satin:
          // Smooth silk texture finish
          final Paint satinPaint = Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.25),
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.3),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(bounds)
            ..blendMode = BlendMode.overlay;
          canvas.drawPath(path, satinPaint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant NailPainter oldDelegate) =>
      oldDelegate.polygons != polygons ||
      oldDelegate.nailColor != nailColor ||
      oldDelegate.variant != variant ||
      oldDelegate.imageWidth != imageWidth ||
      oldDelegate.imageHeight != imageHeight;
}
