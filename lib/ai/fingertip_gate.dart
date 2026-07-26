import 'dart:ui';
import 'package:hand_landmarker/hand_landmarker.dart';

/// MediaPipe Hands landmark indices for the five fingertips (thumb, index,
/// middle, ring, pinky). The joint just before each tip is always tip-1 for
/// this landmark topology (IP/DIP joint), which [NailTracker] uses to get a
/// finger-pointing direction at the tip.
const List<int> fingertipLandmarkIndices = [4, 8, 12, 16, 20];

/// Converts a single hand landmark (normalized 0..1, relative to the *raw
/// sensor* frame) into the same rotated/upright pixel space that
/// [YoloSegDecoder] polygons live in (i.e. `LetterboxResult.originalWidth/Height`
/// space).
///
/// Mirrors exactly the pixel mapping `package:image`'s `copyRotate` uses for
/// 90/270 degree rotations (see `image/src/transform/copy_rotate.dart`), since
/// that is what turned the raw sensor frame into that upright image in the
/// first place. Only rotationDegrees of 0/90/180/270 are meaningful here,
/// matching what the rest of the AR pipeline handles.
Offset landmarkToPixel(
  Landmark landmark, {
  required int sensorWidth,
  required int sensorHeight,
  required int rotationDegrees,
}) {
  final double srcX = landmark.x * sensorWidth;
  final double srcY = landmark.y * sensorHeight;

  switch (rotationDegrees) {
    case 90:
      return Offset(sensorHeight - srcY, srcX);
    case 270:
      return Offset(srcY, sensorWidth - srcX);
    default:
      // 0/180 aren't rotated by the rest of the pipeline either.
      return Offset(srcX, srcY);
  }
}

/// All five fingertip positions (across all detected hands), in the same
/// pixel space as nail polygons.
List<Offset> fingertipPixelPositions({
  required List<Hand> hands,
  required int sensorWidth,
  required int sensorHeight,
  required int rotationDegrees,
}) {
  final List<Offset> fingertips = [];
  for (final hand in hands) {
    for (final index in fingertipLandmarkIndices) {
      if (index >= hand.landmarks.length) continue;
      fingertips.add(landmarkToPixel(
        hand.landmarks[index],
        sensorWidth: sensorWidth,
        sensorHeight: sensorHeight,
        rotationDegrees: rotationDegrees,
      ));
    }
  }
  return fingertips;
}

Offset centroid(List<Offset> polygon) {
  double sx = 0, sy = 0;
  for (final p in polygon) {
    sx += p.dx;
    sy += p.dy;
  }
  return Offset(sx / polygon.length, sy / polygon.length);
}
