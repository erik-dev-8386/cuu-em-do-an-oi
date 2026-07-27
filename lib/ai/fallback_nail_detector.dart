import 'dart:math';
import 'dart:ui';

import 'package:image/image.dart' as img;

class FallbackNailDetector {
  static List<List<Offset>> estimate(img.Image image, {int maxNails = 5}) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) return const [];

    final stepX = max(2, width ~/ 220);
    final stepY = max(2, height ~/ 220);
    final startY = (height * 0.08).round();
    final endY = (height * 0.78).round();
    final minSkinRun = max(3, (height * 0.025 / stepY).round());

    final columns = <_FingerTopColumn>[];
    for (int x = 0; x < width; x += stepX) {
      int? topY;
      for (int y = startY; y < endY; y += stepY) {
        if (!_isSkin(image.getPixel(x, y))) continue;

        var run = 0;
        final runEnd = min(height - 1, y + (height * 0.18).round());
        for (int yy = y; yy <= runEnd; yy += stepY) {
          if (_isSkin(image.getPixel(x, yy))) run++;
        }

        if (run >= minSkinRun) {
          topY = y;
          break;
        }
      }

      if (topY != null) {
        columns.add(_FingerTopColumn(x.toDouble(), topY.toDouble()));
      }
    }

    if (columns.length < 3) return const [];

    final smoothed = _smoothColumns(columns);
    final minTop = smoothed.map((item) => item.y).reduce(min);
    final fingertipCutoff = minTop + height * 0.22;
    final groups = <List<_FingerTopColumn>>[];
    var current = <_FingerTopColumn>[];

    for (final column in smoothed) {
      if (column.y <= fingertipCutoff) {
        current.add(column);
      } else if (current.isNotEmpty) {
        groups.add(current);
        current = <_FingerTopColumn>[];
      }
    }
    if (current.isNotEmpty) groups.add(current);

    final candidates = groups
        .map((group) => _fingerTipFromGroup(group, width, height))
        .whereType<_FingerTip>()
        .toList();

    if (candidates.length < 3) {
      candidates
        ..clear()
        ..addAll(_pickSeparatedTops(smoothed, width, height, maxNails));
    }

    candidates.sort((a, b) => a.x.compareTo(b.x));
    return candidates
        .take(maxNails)
        .map((tip) => _ellipsePolygon(tip.x, tip.y, tip.w, tip.h))
        .toList(growable: false);
  }

  static List<_FingerTopColumn> _smoothColumns(List<_FingerTopColumn> input) {
    final result = <_FingerTopColumn>[];
    for (int i = 0; i < input.length; i++) {
      final start = max(0, i - 2);
      final end = min(input.length - 1, i + 2);
      var sum = 0.0;
      var count = 0;
      for (int j = start; j <= end; j++) {
        sum += input[j].y;
        count++;
      }
      result.add(_FingerTopColumn(input[i].x, sum / count));
    }
    return result;
  }

  static _FingerTip? _fingerTipFromGroup(
    List<_FingerTopColumn> group,
    int imageWidth,
    int imageHeight,
  ) {
    if (group.isEmpty) return null;

    final groupWidth = group.last.x - group.first.x;
    if (groupWidth < imageWidth * 0.018 || groupWidth > imageWidth * 0.22) {
      return null;
    }

    final top = group.reduce((a, b) => a.y <= b.y ? a : b);
    final nailW = (groupWidth * 0.62).clamp(
      imageWidth * 0.026,
      imageWidth * 0.06,
    );
    final nailH = (nailW * 1.35).clamp(
      imageHeight * 0.018,
      imageHeight * 0.055,
    );

    return _FingerTip(
      x: top.x,
      y: top.y + nailH * 0.7,
      w: nailW.toDouble(),
      h: nailH.toDouble(),
    );
  }

  static List<_FingerTip> _pickSeparatedTops(
    List<_FingerTopColumn> columns,
    int imageWidth,
    int imageHeight,
    int maxNails,
  ) {
    final sorted = List<_FingerTopColumn>.from(columns)
      ..sort((a, b) => a.y.compareTo(b.y));
    final minDistance = imageWidth * 0.075;
    final nailW = imageWidth * 0.045;
    final nailH = nailW * 1.35;
    final tips = <_FingerTip>[];

    for (final column in sorted) {
      final isTooClose = tips.any(
        (tip) => (tip.x - column.x).abs() < minDistance,
      );
      if (isTooClose) continue;

      tips.add(
        _FingerTip(x: column.x, y: column.y + nailH * 0.7, w: nailW, h: nailH),
      );

      if (tips.length >= maxNails) break;
    }

    return tips;
  }

  static List<Offset> _ellipsePolygon(
    double cx,
    double cy,
    double w,
    double h,
  ) {
    const steps = 18;
    return List<Offset>.generate(steps, (index) {
      final angle = (2 * pi * index) / steps;
      return Offset(cx + (w / 2.0) * cos(angle), cy + (h / 2.0) * sin(angle));
    }, growable: false);
  }

  static bool _isSkin(img.Pixel pixel) {
    final r = pixel.r.toDouble();
    final g = pixel.g.toDouble();
    final b = pixel.b.toDouble();
    final maxRgb = max(r, max(g, b));
    final minRgb = min(r, min(g, b));
    if (r < 55 || g < 35 || b < 20 || maxRgb - minRgb < 12) return false;
    if (r <= g || r <= b) return false;

    final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    return cb >= 77 && cb <= 135 && cr >= 133 && cr <= 180;
  }
}

class _FingerTopColumn {
  final double x;
  final double y;

  const _FingerTopColumn(this.x, this.y);
}

class _FingerTip {
  final double x;
  final double y;
  final double w;
  final double h;

  const _FingerTip({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}
