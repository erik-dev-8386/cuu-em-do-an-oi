import 'dart:math';
import 'dart:ui';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'fingertip_gate.dart';

/// Decouples nail *shape* (accurate but slow — comes from the YOLO
/// segmentation pipeline, updated maybe once every few seconds) from nail
/// *position* (needs to track the hand live — comes from MediaPipe hand
/// landmarks, updated every camera frame).
///
/// Whenever a YOLO detection is matched to a specific fingertip, its polygon
/// is stored in a frame relative to that finger: rotated so the finger points
/// along +x and scaled by the tip-to-DIP-joint distance. On every landmark
/// update, each stored shape is re-projected onto the *current* fingertip
/// position/orientation/scale — so the overlay follows the hand in real time
/// even though the shape itself is only refreshed occasionally.
class NailTracker {
  final Map<int, List<Offset>> _canonicalLocalShapes = {};

  /// Feeds a new YOLO detection batch. Each polygon is matched to whichever
  /// fingertip (across all detected hands) is nearest its centroid; polygons
  /// too far from every fingertip are ignored (almost certainly not a nail —
  /// the segmentation model has no concept of hand structure).
  void updateFromDetections({
    required List<List<Offset>> yoloPolygons,
    required List<Hand> hands,
    required int sensorWidth,
    required int sensorHeight,
    required int rotationDegrees,
    required double maxMatchDistance,
  }) {
    if (yoloPolygons.isEmpty || hands.isEmpty) return;

    final fingerFrames = _currentFingerFrames(
      hands: hands,
      sensorWidth: sensorWidth,
      sensorHeight: sensorHeight,
      rotationDegrees: rotationDegrees,
    );
    if (fingerFrames.isEmpty) return;

    for (final polygon in yoloPolygons) {
      if (polygon.length < 3) continue;
      final polyCentroid = centroid(polygon);

      int? bestKey;
      double bestDist = double.infinity;
      fingerFrames.forEach((key, frame) {
        final dist = (frame.tip - polyCentroid).distance;
        if (dist < bestDist) {
          bestDist = dist;
          bestKey = key;
        }
      });

      if (bestKey == null || bestDist > maxMatchDistance) continue;

      final frame = fingerFrames[bestKey]!;
      if (frame.length < 1.0) continue; // degenerate, avoid divide-by-zero

      _canonicalLocalShapes[bestKey!] = polygon
          .map((p) => _rotate(p - frame.tip, -frame.angle) / frame.length)
          .toList();
    }
  }

  /// Projects every stored canonical shape onto the *current* hand pose.
  /// Fingers that aren't currently trackable (hand out of frame, etc.) are
  /// skipped for this call but their canonical shape is kept in case the
  /// finger reappears.
  List<List<Offset>> render({
    required List<Hand> hands,
    required int sensorWidth,
    required int sensorHeight,
    required int rotationDegrees,
  }) {
    if (_canonicalLocalShapes.isEmpty || hands.isEmpty) return [];

    final fingerFrames = _currentFingerFrames(
      hands: hands,
      sensorWidth: sensorWidth,
      sensorHeight: sensorHeight,
      rotationDegrees: rotationDegrees,
    );

    final List<List<Offset>> rendered = [];
    _canonicalLocalShapes.forEach((key, localShape) {
      final frame = fingerFrames[key];
      if (frame == null || frame.length < 1.0) return;

      rendered.add(localShape
          .map((lp) => frame.tip + _rotate(lp * frame.length, frame.angle))
          .toList());
    });
    return rendered;
  }

  void reset() {
    _canonicalLocalShapes.clear();
  }

  /// Computes, for every (hand, finger) pair currently visible, the
  /// fingertip position/orientation/scale needed to place a nail shape.
  /// Keyed by `handIndex * 5 + fingerSlot` (fingerSlot indexes into
  /// [fingertipLandmarkIndices]).
  Map<int, _FingerFrame> _currentFingerFrames({
    required List<Hand> hands,
    required int sensorWidth,
    required int sensorHeight,
    required int rotationDegrees,
  }) {
    final Map<int, _FingerFrame> frames = {};

    for (int handIdx = 0; handIdx < hands.length; handIdx++) {
      final landmarks = hands[handIdx].landmarks;
      for (int slot = 0; slot < fingertipLandmarkIndices.length; slot++) {
        final tipIndex = fingertipLandmarkIndices[slot];
        final jointIndex = tipIndex - 1; // DIP/IP joint, just before the tip
        if (tipIndex >= landmarks.length || jointIndex < 0) continue;

        final tip = landmarkToPixel(
          landmarks[tipIndex],
          sensorWidth: sensorWidth,
          sensorHeight: sensorHeight,
          rotationDegrees: rotationDegrees,
        );
        final joint = landmarkToPixel(
          landmarks[jointIndex],
          sensorWidth: sensorWidth,
          sensorHeight: sensorHeight,
          rotationDegrees: rotationDegrees,
        );

        final vector = tip - joint;
        frames[handIdx * fingertipLandmarkIndices.length + slot] = _FingerFrame(
          tip: tip,
          angle: atan2(vector.dy, vector.dx),
          length: vector.distance,
        );
      }
    }

    return frames;
  }

  static Offset _rotate(Offset v, double angle) {
    final c = cos(angle);
    final s = sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }
}

class _FingerFrame {
  final Offset tip;
  final double angle;
  final double length;
  _FingerFrame({required this.tip, required this.angle, required this.length});
}
