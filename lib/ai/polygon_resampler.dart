import 'dart:math';
import 'dart:ui';

/// Converts a raw traced contour (dense, pixel-stairstepped, variable length)
/// into a fixed-length polygon by sampling boundary radius at evenly spaced
/// angles around the shape's centroid.
///
/// This serves two purposes at once:
/// 1. Smooths the jagged marching-squares boundary (angle bucketing averages
///    out single-pixel staircase noise).
/// 2. Gives every polygon the same point count in the same canonical order
///    (by angle from centroid, not by trace start), so frame-to-frame
///    vertices correspond to the same physical location on the nail and can
///    be blended safely for temporal smoothing.
class PolygonResampler {
  static const int defaultPointCount = 48;

  static List<Offset> resample(List<Offset> polygon, {int pointCount = defaultPointCount}) {
    if (polygon.length < 3) return polygon;

    double cx = 0, cy = 0;
    for (final p in polygon) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= polygon.length;
    cy /= polygon.length;

    final int n = polygon.length;
    final List<double> angles = List.filled(n, 0);
    final List<double> radii = List.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final dx = polygon[i].dx - cx;
      final dy = polygon[i].dy - cy;
      angles[i] = atan2(dy, dx);
      radii[i] = sqrt(dx * dx + dy * dy);
    }

    final order = List<int>.generate(n, (i) => i)..sort((a, b) => angles[a].compareTo(angles[b]));

    final List<Offset> result = [];
    for (int k = 0; k < pointCount; k++) {
      final double targetAngle = -pi + (2 * pi * k) / pointCount;
      final double r = _radiusAtAngle(order, angles, radii, targetAngle);
      result.add(Offset(cx + r * cos(targetAngle), cy + r * sin(targetAngle)));
    }

    return result;
  }

  /// Finds the two boundary samples bracketing [targetAngle] (in sorted-by-angle
  /// order, wrapping around +-pi) and linearly interpolates their radius.
  static double _radiusAtAngle(
    List<int> order,
    List<double> angles,
    List<double> radii,
    double targetAngle,
  ) {
    final int n = order.length;

    int lo = 0, hi = n - 1;
    if (targetAngle <= angles[order[0]] || targetAngle >= angles[order[n - 1]]) {
      // Wrap-around segment between the last and first sorted samples.
      final double a1 = angles[order[n - 1]];
      final double a2 = angles[order[0]] + 2 * pi;
      double t = targetAngle;
      if (t < angles[order[0]]) t += 2 * pi;
      final double span = a2 - a1;
      final double frac = span.abs() < 1e-9 ? 0.0 : ((t - a1) / span).clamp(0.0, 1.0);
      return radii[order[n - 1]] + frac * (radii[order[0]] - radii[order[n - 1]]);
    }

    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (angles[order[mid]] <= targetAngle) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final double a1 = angles[order[lo]];
    final double a2 = angles[order[hi]];
    final double span = a2 - a1;
    final double frac = span.abs() < 1e-9 ? 0.0 : ((targetAngle - a1) / span).clamp(0.0, 1.0);
    return radii[order[lo]] + frac * (radii[order[hi]] - radii[order[lo]]);
  }
}
