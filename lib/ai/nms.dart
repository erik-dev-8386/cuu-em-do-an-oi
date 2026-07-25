import 'dart:math';

class YoloDetection {
  final double cx;
  final double cy;
  final double w;
  final double h;
  final double score;
  final List<double> maskCoeffs;

  YoloDetection({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    required this.score,
    required this.maskCoeffs,
  });

  double get x1 => cx - w / 2.0;
  double get y1 => cy - h / 2.0;
  double get x2 => cx + w / 2.0;
  double get y2 => cy + h / 2.0;
}

class NmsProcessor {
  static List<YoloDetection> filter({
    required List<YoloDetection> candidates,
    required double iouThreshold,
    int maxKeep = 10,
  }) {
    if (candidates.isEmpty) return [];

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final List<YoloDetection> selected = [];

    for (var cand in candidates) {
      bool keep = true;
      for (var kept in selected) {
        if (_calculateIoU(cand, kept) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) {
        selected.add(cand);
        if (selected.length >= maxKeep) break;
      }
    }

    return selected;
  }

  static double _calculateIoU(YoloDetection a, YoloDetection b) {
    double interX1 = max(a.x1, b.x1);
    double interY1 = max(a.y1, b.y1);
    double interX2 = min(a.x2, b.x2);
    double interY2 = min(a.y2, b.y2);

    double interWidth = max(0.0, interX2 - interX1);
    double interHeight = max(0.0, interY2 - interY1);
    double intersection = interWidth * interHeight;

    double areaA = a.w * a.h;
    double areaB = b.w * b.h;
    double unionArea = areaA + areaB - intersection;

    return unionArea <= 0 ? 0.0 : intersection / unionArea;
  }
}
