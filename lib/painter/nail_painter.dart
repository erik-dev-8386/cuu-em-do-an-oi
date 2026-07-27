import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/nail_variant.dart';

class NailPainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final Color nailColor;
  final NailVariant? variant;
  final double? imageWidth;
  final double? imageHeight;
  final ui.Image? shapeTexture;

  NailPainter({
    required this.polygons,
    this.nailColor = const Color(0xFFFFD700),
    this.variant,
    this.imageWidth,
    this.imageHeight,
    this.shapeTexture,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (polygons.isEmpty) return;

    final double scaleX =
        (imageWidth != null && imageWidth! > 0) ? size.width / imageWidth! : 1.0;
    final double scaleY =
        (imageHeight != null && imageHeight! > 0) ? size.height / imageHeight! : 1.0;

    final SurfaceType surface = variant?.surfaceType ?? SurfaceType.glossy;
    final surfaceParams = _surfaceShaderParams;
    final sortedPolygons = _sortPolygonsForFingerColors(polygons);

    for (int polygonIndex = 0; polygonIndex < sortedPolygons.length; polygonIndex++) {
      final polygon = sortedPolygons[polygonIndex];
      if (polygon.length < 3) continue;

      final scaledPolygon =
          polygon.map((pt) => Offset(pt.dx * scaleX, pt.dy * scaleY)).toList();

      final geometry = _buildNailGeometry(scaledPolygon);
      final path = geometry.path;

      canvas.save();
      canvas.clipPath(path);

      final Rect bounds = geometry.bounds;
      // PCA principal-axis angle (in radians, 0 = horizontal, Ï€/2 = vertical)
      // drawAngle: angle to rotate shape image so its tip aligns with nail direction.
      // When pcaAngle = Ï€/2 (vertical nail, tip up), drawAngle = 0 â†’ no rotation needed.x
      // When pcaAngle = 0 (horizontal nail, tip right), drawAngle = Ï€/2 â†’ rotate CW 90Â°.
      final double drawAngle = geometry.drawAngle;
      final int fingerIndex = polygonIndex + 1;
      final Color effectiveColor = _colorForFinger(fingerIndex);

      // â”€â”€ LAYER 1: Vivid base nail color â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // A solid, opaque fill in the nail color.
      if (_usesGradientFill) {
        final angleDeg = drawAngle * 180 / pi;
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: _gradientColors,
              begin: _alignmentFromDegrees(angleDeg - 90),
              end: _alignmentFromDegrees(angleDeg + 90),
            ).createShader(bounds)
            ..blendMode = BlendMode.srcOver,
        );
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..color = effectiveColor.withValues(alpha: 0.90)
            ..blendMode = BlendMode.srcOver,
        );
      }

      // â”€â”€ LAYER 2: Shape image texture (depth & shadow) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // The shape image is drawn with multiply blend:
      //   â€¢ White/light areas of the image â†’ transparent over the base color
      //   â€¢ Dark/shadow areas â†’ deepen the base color naturally
      // Image is rotated so the nail TIP aligns with the finger direction.
      if (shapeTexture != null) {
        _drawShapeImageLayer(canvas, geometry);
      }

      // â”€â”€ LAYER 3: Surface Finish Shader â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // All effects use drawAngle for directionality (rotates with finger).
      final double angleDeg = drawAngle * 180 / pi;
      _drawSurfaceShader(
        canvas, path, bounds, effectiveColor, drawAngle, angleDeg, surface, surfaceParams,
      );

      // â”€â”€ LAYER 4: Edge shadow (dimensional depth) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Subtle darkening around the polygon edge â€” makes nails look 3-D.
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.22),
            ],
            stops: const [0.60, 1.0],
            center: Alignment.center,
            radius: 0.85,
          ).createShader(bounds)
          ..blendMode = BlendMode.multiply,
      );

      canvas.restore();
    }
  }

  // â”€â”€â”€ Surface shader dispatcher â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _drawSurfaceShader(
    Canvas canvas,
    Path path,
    Rect bounds,
    Color effectiveColor,
    double drawAngle,
    double angleDeg,
    SurfaceType surface,
    Map<String, dynamic> surfaceParams,
  ) {
    switch (surface) {
      case SurfaceType.glossy:
        final shine = _paramDouble(surfaceParams, 'shine', 0.55);
        // Main highlight: bright streak along the finger axis (top/cuticle area).
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.70 * shine),
                Colors.white.withValues(alpha: 0.30 * shine),
                Colors.transparent,
                Colors.transparent,
              ],
              stops: const [0.0, 0.25, 0.55, 1.0],
              begin: _alignmentFromDegrees(angleDeg - 90),
              end: _alignmentFromDegrees(angleDeg + 90),
            ).createShader(bounds)
            ..blendMode = BlendMode.screen,
        );
        // Secondary specular dot near the tip
        canvas.drawPath(
          path,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.45),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
              center: Alignment(-sin(drawAngle) * 0.35, -cos(drawAngle) * 0.35),
              radius: 0.45,
            ).createShader(bounds)
            ..blendMode = BlendMode.screen,
        );
        break;

      case SurfaceType.matte:
        final opacity = _paramDouble(surfaceParams, 'opacity', 0.10);
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: opacity.clamp(0.04, 0.18))
            ..blendMode = BlendMode.softLight,
        );
        break;

      case SurfaceType.catEye:
        final streak = _paramDouble(surfaceParams, 'streak', 0.80);
        final rawAngle = _paramDouble(surfaceParams, 'angle', 45);
        final totalAngle = rawAngle + angleDeg;
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: streak.clamp(0.40, 0.95)),
                Colors.transparent,
              ],
              stops: const [0.30, 0.50, 0.70],
              begin: _alignmentFromDegrees(totalAngle + 180),
              end: _alignmentFromDegrees(totalAngle),
            ).createShader(bounds)
            ..blendMode = BlendMode.screen,
        );
        break;

      case SurfaceType.chrome:
        final reflectivity = _paramDouble(surfaceParams, 'reflectivity', 0.9);
        final metallic = _paramDouble(surfaceParams, 'metallic', 1.0);
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.30 + reflectivity * 0.55),
                effectiveColor.withValues(alpha: 0.12 + metallic * 0.15),
                Colors.white.withValues(alpha: 0.35 + reflectivity * 0.50),
                Colors.black.withValues(alpha: 0.05 + metallic * 0.15),
              ],
              stops: const [0.0, 0.4, 0.7, 1.0],
              begin: _alignmentFromDegrees(angleDeg - 90),
              end: _alignmentFromDegrees(angleDeg + 90),
            ).createShader(bounds)
            ..blendMode = BlendMode.screen,
        );
        break;

      case SurfaceType.glitter:
        final intensity = _paramDouble(surfaceParams, 'intensity', 0.85);
        final rnd = Random(bounds.left.toInt() * 31 + bounds.top.toInt());
        final sparklePaint = Paint()
          ..style = PaintingStyle.fill;
        final sparkleCount = (12 + intensity * 20).round();
        for (int i = 0; i < sparkleCount; i++) {
          final gx = bounds.left + rnd.nextDouble() * bounds.width;
          final gy = bounds.top + rnd.nextDouble() * bounds.height;
          if (path.contains(Offset(gx, gy))) {
            final r = 0.7 + rnd.nextDouble() * 2.0;
            sparklePaint.color = (rnd.nextBool() ? Colors.white : Colors.yellowAccent)
                .withValues(alpha: 0.5 + rnd.nextDouble() * 0.5);
            canvas.drawCircle(Offset(gx, gy), r, sparklePaint);
          }
        }
        break;

      case SurfaceType.holographic:
        final intensity = _paramDouble(surfaceParams, 'intensity', 0.70);
        final useRainbow = _paramBool(surfaceParams, 'rainbow', true);
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: useRainbow
                  ? [
                      Colors.cyanAccent.withValues(alpha: intensity),
                      const Color(0xFFFF00FF).withValues(alpha: intensity),
                      Colors.yellowAccent.withValues(alpha: intensity),
                      Colors.cyanAccent.withValues(alpha: intensity),
                    ]
                  : [
                      Colors.white.withValues(alpha: intensity),
                      Colors.cyanAccent.withValues(alpha: intensity),
                      Colors.white.withValues(alpha: intensity),
                    ],
              begin: _alignmentFromDegrees(angleDeg),
              end: _alignmentFromDegrees(angleDeg + 180),
            ).createShader(bounds)
            ..blendMode = BlendMode.screen,
        );
        break;

      case SurfaceType.pearl:
        canvas.drawPath(
          path,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.65),
                Colors.pink.shade100.withValues(alpha: 0.30),
                Colors.cyan.shade100.withValues(alpha: 0.10),
              ],
              center: _alignmentFromDegrees(angleDeg - 90),
              radius: 0.90,
            ).createShader(bounds)
            ..blendMode = BlendMode.screen,
        );
        break;

      case SurfaceType.satin:
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.28),
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.28),
              ],
              begin: _alignmentFromDegrees(angleDeg - 90),
              end: _alignmentFromDegrees(angleDeg + 90),
            ).createShader(bounds)
            ..blendMode = BlendMode.overlay,
        );
        break;
    }
  }

  // â”€â”€â”€ Shape image layer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Draws [shapeTexture] as a multiply-blended shadow/depth layer.
  ///
  /// Using `BlendMode.multiply`:
  ///  â€¢ White / light pixels in the image â†’ invisible over the base color
  ///  â€¢ Dark pixels â†’ create natural shadow/depth on the nail
  ///
  /// [drawAngle] = Ï€/2 âˆ’ pcaAngle so the tip of the nail image aligns with the
  /// actual finger direction (0 rad â†’ tip points up, which is the image default).
  void _drawShapeImageLayer(Canvas canvas, _NailGeometry geometry) {
    final texture = shapeTexture!;
    final src = Rect.fromLTWH(
      0, 0, texture.width.toDouble(), texture.height.toDouble(),
    );

    canvas.save();
    canvas.translate(geometry.center.dx, geometry.center.dy);
    canvas.rotate(geometry.drawAngle);

    // Cover the oriented nail slot; the clip path keeps the image inside it.
    final double scaleW = geometry.width / texture.width * 1.12;
    final double scaleH = geometry.length / texture.height * 1.12;
    final double s = max(scaleW, scaleH);
    final dst = Rect.fromCenter(
      center: Offset.zero,
      width: texture.width * s,
      height: texture.height * s,
    );

    // Use saveLayer to apply overall 70% opacity for the texture layer
    final texturePaint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..blendMode = BlendMode.softLight
      // Darken-only: map luminance of shape image onto the base color.
      // White pixels (R=G=B=1.0) → multiply gives same as base → invisible
      // Dark pixels (R=G=B~0)    → multiply darkens the base → natural shadow
      ..colorFilter = ColorFilter.matrix(<double>[
        1.15, 0, 0, 0, 0,
        0, 1.15, 0, 0, 0,
        0, 0, 1.15, 0, 0,
        0, 0, 0, 0.22, 0,
      ]);
    canvas.drawImageRect(texture, src, dst, texturePaint);
    canvas.restore(); // pops translate+rotate
  }

  // â”€â”€â”€ Geometry â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns the PCA principal-axis angle of the polygon (radians from X-axis).
  ///
  /// â€¢ Vertical elongated polygon (nail tip up) â†’ ~Ï€/2
  /// â€¢ Horizontal elongated polygon (nail tip right) â†’ ~0
  ///
  /// callers use `drawAngle = Ï€/2 âˆ’ pcaAngle` to convert to rotation needed.
  double _calculatePcaAngle(List<Offset> poly) {
    if (poly.length < 3) return pi / 2; // default: treat as vertical

    double cx = 0, cy = 0;
    for (final pt in poly) {
      cx += pt.dx;
      cy += pt.dy;
    }
    cx /= poly.length;
    cy /= poly.length;

    double mu20 = 0, mu02 = 0, mu11 = 0;
    for (final pt in poly) {
      final dx = pt.dx - cx;
      final dy = pt.dy - cy;
      mu20 += dx * dx;
      mu02 += dy * dy;
      mu11 += dx * dy;
    }

    // atan2 of 2nd-order moments gives major-axis direction [-Ï€/2, Ï€/2]
    return 0.5 * atan2(2 * mu11, mu20 - mu02);
  }

  _NailGeometry _buildNailGeometry(List<Offset> polygon) {
    final pcaAngle = _calculatePcaAngle(polygon);
    final axis = Offset(cos(pcaAngle), sin(pcaAngle));
    final cross = Offset(-sin(pcaAngle), cos(pcaAngle));

    var center = Offset.zero;
    for (final pt in polygon) {
      center += pt;
    }
    center = center / polygon.length.toDouble();

    var minMajor = double.infinity;
    var maxMajor = -double.infinity;
    var minMinor = double.infinity;
    var maxMinor = -double.infinity;
    for (final pt in polygon) {
      final rel = pt - center;
      final major = rel.dx * axis.dx + rel.dy * axis.dy;
      final minor = rel.dx * cross.dx + rel.dy * cross.dy;
      minMajor = min(minMajor, major);
      maxMajor = max(maxMajor, major);
      minMinor = min(minMinor, minor);
      maxMinor = max(maxMinor, minor);
    }

    final sourceLength = maxMajor - minMajor;
    final sourceWidth = maxMinor - minMinor;
    final shortSide = max(8.0, min(sourceLength, sourceWidth));
    final longSide = max(sourceLength, sourceWidth);
    final width = max(shortSide * 1.20, longSide * _shapeWidthRatio);
    final length = max(longSide * 1.08, width * _shapeLengthRatio);
    final drawAngle = _resolveDrawAngle(pcaAngle);
    final localPath = _buildLocalShapePath(width, length);
    final cosA = cos(drawAngle);
    final sinA = sin(drawAngle);
    final matrix = Float64List.fromList(<double>[
      cosA,
      sinA,
      0,
      0,
      -sinA,
      cosA,
      0,
      0,
      0,
      0,
      1,
      0,
      center.dx,
      center.dy,
      0,
      1,
    ]);
    final path = localPath.transform(matrix);

    return _NailGeometry(
      path: path,
      bounds: path.getBounds(),
      center: center,
      width: width,
      length: length,
      drawAngle: drawAngle,
    );
  }

  Path _buildLocalShapePath(double width, double length) {
    final halfW = width / 2.0;
    final halfL = length / 2.0;
    final shape = _normalizedShapeName;

    if (shape.contains('stiletto')) {
      return Path()
        ..moveTo(0, -halfL)
        ..cubicTo(
          halfW * 0.62,
          -halfL * 0.66,
          halfW * 0.94,
          -halfL * 0.10,
          halfW * 0.72,
          halfL * 0.74,
        )
        ..quadraticBezierTo(0, halfL, -halfW * 0.9, halfL * 0.68)
        ..cubicTo(
          -halfW * 0.94,
          -halfL * 0.10,
          -halfW * 0.62,
          -halfL * 0.66,
          0,
          -halfL,
        )
        ..close();
    }

    if (shape.contains('coffin') || shape.contains('ballerina')) {
      final tipHalf = halfW * (shape.contains('ballerina') ? 0.58 : 0.66);
      return Path()
        ..moveTo(-tipHalf, -halfL)
        ..lineTo(tipHalf, -halfL)
        ..cubicTo(
          halfW * 0.98,
          -halfL * 0.20,
          halfW,
          halfL * 0.50,
          halfW * 0.72,
          halfL * 0.76,
        )
        ..quadraticBezierTo(0, halfL, -halfW * 0.72, halfL * 0.76)
        ..cubicTo(
          -halfW,
          halfL * 0.50,
          -halfW * 0.98,
          -halfL * 0.20,
          -tipHalf,
          -halfL,
        )
        ..close();
    }

    if (shape.contains('square')) {
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-halfW, -halfL, width, length),
            Radius.circular(width * 0.16),
          ),
        );
    }

    if (shape.contains('round')) {
      return Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-halfW, -halfL, width, length),
            Radius.circular(halfW),
          ),
        );
    }

    if (shape.contains('almond')) {
      return Path()
        ..moveTo(0, -halfL)
        ..cubicTo(
          halfW * 0.78,
          -halfL * 0.70,
          halfW,
          -halfL * 0.10,
          halfW * 0.78,
          halfL * 0.60,
        )
        ..quadraticBezierTo(0, halfL * 1.05, -halfW * 0.78, halfL * 0.60)
        ..cubicTo(
          -halfW,
          -halfL * 0.10,
          -halfW * 0.78,
          -halfL * 0.70,
          0,
          -halfL,
        )
        ..close();
    }

    return Path()..addOval(Rect.fromLTWH(-halfW, -halfL, width, length));
  }

  double get _shapeLengthRatio {
    final shape = _normalizedShapeName;
    if (shape.contains('stiletto')) return 2.95;
    if (shape.contains('coffin') || shape.contains('ballerina')) return 2.45;
    if (shape.contains('square')) return 1.95;
    if (shape.contains('round')) return 1.72;
    if (shape.contains('almond')) return 2.25;
    if (shape.contains('oval')) return 2.05;
    return 2.05;
  }

  double get _shapeWidthRatio {
    final shape = _normalizedShapeName;
    if (shape.contains('stiletto')) return 0.22;
    if (shape.contains('coffin') || shape.contains('ballerina')) return 0.32;
    if (shape.contains('square')) return 0.42;
    if (shape.contains('round')) return 0.46;
    if (shape.contains('almond')) return 0.34;
    if (shape.contains('oval')) return 0.40;
    return 0.36;
  }

  String get _normalizedShapeName =>
      (variant?.shapeName ?? '').trim().toLowerCase();

  // â”€â”€â”€ Color helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double _resolveDrawAngle(double pcaAngle) {
    final candidateA = pcaAngle + pi / 2;
    final candidateB = pcaAngle - pi / 2;
    return _tipVector(candidateA).dy <= _tipVector(candidateB).dy
        ? candidateA
        : candidateB;
  }

  Offset _tipVector(double drawAngle) => Offset(sin(drawAngle), -cos(drawAngle));

  bool get _usesGradientFill =>
      variant?.colorMode == NailColorMode.gradient && _gradientColors.length > 1;

  List<Color> get _gradientColors {
    final colors = variant?.gradientColors ?? const [];
    return colors.length > 1 ? colors : [variant?.primaryColor ?? nailColor];
  }

  Color _colorForFinger(int fingerIndex) {
    if (variant?.colorMode == NailColorMode.perFinger) {
      return variant!.colorForFingerIndex(fingerIndex);
    }
    return variant?.primaryColor ?? nailColor;
  }

  List<List<Offset>> _sortPolygonsForFingerColors(List<List<Offset>> input) {
    if (variant?.colorMode != NailColorMode.perFinger) return input;
    final sorted = List<List<Offset>>.from(input);
    sorted.sort((a, b) => _centerX(a).compareTo(_centerX(b)));
    return sorted;
  }

  double _centerX(List<Offset> polygon) {
    if (polygon.isEmpty) return 0;
    return polygon.fold<double>(0, (s, p) => s + p.dx) / polygon.length;
  }

  // â”€â”€â”€ Surface param helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Map<String, dynamic> get _surfaceShaderParams {
    final raw = variant?.surfaceShaderParam.trim();
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }

  double _paramDouble(Map<String, dynamic> p, String key, double fallback) {
    final v = p[key];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  bool _paramBool(Map<String, dynamic> p, String key, bool fallback) {
    final v = p[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  Alignment _alignmentFromDegrees(double degrees) {
    final rad = degrees * pi / 180;
    return Alignment(cos(rad), sin(rad));
  }

  @override
  bool shouldRepaint(covariant NailPainter old) =>
      old.polygons != polygons ||
      old.nailColor != nailColor ||
      old.variant != variant ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight ||
      old.shapeTexture != shapeTexture;
}

class _NailGeometry {
  final Path path;
  final Rect bounds;
  final Offset center;
  final double width;
  final double length;
  final double drawAngle;

  const _NailGeometry({
    required this.path,
    required this.bounds,
    required this.center,
    required this.width,
    required this.length,
    required this.drawAngle,
  });
}
