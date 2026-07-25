import 'dart:ui';

class CameraTransform {
  /// Calculates scale and offset transformation parameters mapping image coordinates
  /// to screen preview canvas coordinates.
  static List<Offset> transformPolygon({
    required List<Offset> polygon,
    required double imageWidth,
    required double imageHeight,
    required Size canvasSize,
  }) {
    if (polygon.isEmpty || imageWidth <= 0 || imageHeight <= 0) return polygon;

    final double scaleX = canvasSize.width / imageWidth;
    final double scaleY = canvasSize.height / imageHeight;

    final List<Offset> transformed = [];
    for (var pt in polygon) {
      transformed.add(Offset(
        pt.dx * scaleX,
        pt.dy * scaleY,
      ));
    }

    return transformed;
  }
}
