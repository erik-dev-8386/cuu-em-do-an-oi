import 'dart:ui';

/// Smooths nail polygons across consecutive video stream frames using IoU (Intersection over Union)
/// matching and Exponential Moving Average (EMA) filtering to eliminate jitter.
class PolygonSmoother {
  final double alpha; // Smoothing factor (0.0 < alpha <= 1.0)
  final double minIouThreshold; // Minimum IoU threshold to consider a match
  List<List<Offset>> _history = [];

  PolygonSmoother({
    this.alpha = 0.4,
    this.minIouThreshold = 0.25,
  });

  List<List<Offset>> smooth(List<List<Offset>> newPolygons) {
    if (_history.isEmpty || newPolygons.isEmpty) {
      _history = newPolygons;
      return newPolygons;
    }

    final List<List<Offset>> smoothedResult = [];

    for (var newPoly in newPolygons) {
      if (newPoly.isEmpty) continue;

      final Rect newBox = _getBoundingBox(newPoly);
      List<Offset>? bestMatchedPoly;
      double maxIou = 0.0;

      for (var histPoly in _history) {
        final Rect histBox = _getBoundingBox(histPoly);
        final double iou = _calculateRectIoU(newBox, histBox);
        if (iou > maxIou) {
          maxIou = iou;
          bestMatchedPoly = histPoly;
        }
      }

      // Match found based on IoU threshold
      if (bestMatchedPoly != null &&
          maxIou >= minIouThreshold &&
          bestMatchedPoly.length == newPoly.length) {
        final List<Offset> smoothedPoly = [];
        for (int i = 0; i < newPoly.length; i++) {
          final double smoothedX =
              alpha * newPoly[i].dx + (1.0 - alpha) * bestMatchedPoly[i].dx;
          final double smoothedY =
              alpha * newPoly[i].dy + (1.0 - alpha) * bestMatchedPoly[i].dy;
          smoothedPoly.add(Offset(smoothedX, smoothedY));
        }
        smoothedResult.add(smoothedPoly);
      } else {
        smoothedResult.add(newPoly);
      }
    }

    _history = smoothedResult;
    return smoothedResult;
  }

  void reset() {
    _history.clear();
  }

  Rect _getBoundingBox(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx;
    double minY = points.first.dy;
    double maxX = points.first.dx;
    double maxY = points.first.dy;

    for (var p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double _calculateRectIoU(Rect a, Rect b) {
    final Rect intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;

    final double interArea = intersection.width * intersection.height;
    final double areaA = a.width * a.height;
    final double areaB = b.width * b.height;
    final double unionArea = areaA + areaB - interArea;

    return unionArea <= 0 ? 0.0 : interArea / unionArea;
  }
}
