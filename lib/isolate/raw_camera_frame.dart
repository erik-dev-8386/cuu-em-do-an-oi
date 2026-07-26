import 'dart:typed_data';

/// Everything needed to convert one camera frame to RGB and letterbox it,
/// extracted from a [CameraImage] into plain, isolate-transferable data.
///
/// `CameraImage`/`Plane` (from package:camera) are plugin types and are not
/// safe to send across an isolate boundary — only their underlying byte
/// buffers and the few ints describing layout are extracted here, on the
/// calling (UI) isolate, which is cheap (no per-pixel work happens yet).
class RawCameraFrame {
  final int width;
  final int height;
  final bool isYuv420; // false => bgra8888
  final Uint8List plane0;
  final Uint8List? plane1; // U (yuv420 only)
  final Uint8List? plane2; // V (yuv420 only)
  final int plane0RowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int rotationDegrees; // 0, 90, 180, 270 — from the camera sensor orientation

  RawCameraFrame({
    required this.width,
    required this.height,
    required this.isYuv420,
    required this.plane0,
    this.plane1,
    this.plane2,
    this.plane0RowStride = 0,
    this.uvRowStride = 0,
    this.uvPixelStride = 1,
    this.rotationDegrees = 0,
  });
}
