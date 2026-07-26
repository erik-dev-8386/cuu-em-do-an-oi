import 'dart:ui';

/// Tracks nail polygons across consecutive video frames.
///
/// Combines three things that used to live separately (and one that didn't
/// work at all):
/// - IoU-based matching of new detections against tracks from the previous
///   frame (greedy, highest-IoU-first).
/// - Exponential Moving Average blending of matched polygons to remove jitter.
///   This only works because [YoloSegDecoder] now emits fixed-length,
///   angle-canonical polygons (see `polygon_resampler.dart`) — before that,
///   the length check below was almost never true and no smoothing happened.
/// - A confirm/grace-period state machine per tracked nail: a brand-new
///   detection must be seen for [confirmFrames] consecutive frames before it
///   is shown (suppresses one-frame false-positive blips), and a previously
///   confirmed nail keeps displaying its last known polygon for up to
///   [graceFrames] frames after it stops matching (suppresses flicker from a
///   single dropped/missed frame).
class PolygonSmoother {
  final double alpha; // Smoothing factor (0.0 < alpha <= 1.0)
  final double minIouThreshold; // Minimum IoU threshold to consider a match
  final int confirmFrames; // Consecutive hits required before a nail is shown
  final int graceFrames; // Consecutive misses tolerated before a shown nail is dropped

  List<_TrackedNail> _tracks = [];

  PolygonSmoother({
    this.alpha = 0.4,
    this.minIouThreshold = 0.25,
    this.confirmFrames = 2,
    this.graceFrames = 2,
  });

  List<List<Offset>> smooth(List<List<Offset>> newPolygons) {
    final matchedTrackIdx = <int>{};
    final matchedDetIdx = <int>{};

    final candidates = <_MatchCandidate>[];
    for (int ti = 0; ti < _tracks.length; ti++) {
      final trackBox = _getBoundingBox(_tracks[ti].polygon);
      for (int di = 0; di < newPolygons.length; di++) {
        final iou = _calculateRectIoU(trackBox, _getBoundingBox(newPolygons[di]));
        if (iou >= minIouThreshold) {
          candidates.add(_MatchCandidate(ti, di, iou));
        }
      }
    }
    candidates.sort((a, b) => b.iou.compareTo(a.iou));

    for (final c in candidates) {
      if (matchedTrackIdx.contains(c.trackIdx) || matchedDetIdx.contains(c.detIdx)) continue;
      matchedTrackIdx.add(c.trackIdx);
      matchedDetIdx.add(c.detIdx);

      final track = _tracks[c.trackIdx];
      final det = newPolygons[c.detIdx];
      track.polygon = (track.polygon.length == det.length) ? _blend(track.polygon, det) : det;
      track.hitStreak++;
      track.missStreak = 0;
      if (track.hitStreak >= confirmFrames) track.confirmed = true;
    }

    final survivors = <_TrackedNail>[];
    for (int ti = 0; ti < _tracks.length; ti++) {
      final track = _tracks[ti];
      if (matchedTrackIdx.contains(ti)) {
        survivors.add(track);
        continue;
      }
      track.missStreak++;
      track.hitStreak = 0;
      if (track.confirmed && track.missStreak <= graceFrames) {
        survivors.add(track);
      }
      // Unconfirmed tracks that miss a frame are dropped outright.
    }

    for (int di = 0; di < newPolygons.length; di++) {
      if (!matchedDetIdx.contains(di)) {
        survivors.add(_TrackedNail(polygon: newPolygons[di]));
      }
    }

    _tracks = survivors;

    return _tracks.where((t) => t.confirmed).map((t) => t.polygon).toList();
  }

  void reset() {
    _tracks = [];
  }

  List<Offset> _blend(List<Offset> prev, List<Offset> curr) {
    final result = <Offset>[];
    for (int i = 0; i < curr.length; i++) {
      result.add(Offset(
        alpha * curr[i].dx + (1.0 - alpha) * prev[i].dx,
        alpha * curr[i].dy + (1.0 - alpha) * prev[i].dy,
      ));
    }
    return result;
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

class _TrackedNail {
  List<Offset> polygon;
  int hitStreak;
  int missStreak;
  bool confirmed;

  _TrackedNail({
    required this.polygon,
  })  : hitStreak = 1,
        missStreak = 0,
        confirmed = false;
}

class _MatchCandidate {
  final int trackIdx;
  final int detIdx;
  final double iou;
  _MatchCandidate(this.trackIdx, this.detIdx, this.iou);
}
