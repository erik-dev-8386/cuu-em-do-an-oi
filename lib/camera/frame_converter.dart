import 'package:camera/camera.dart';
import '../isolate/raw_camera_frame.dart';

class FrameConverter {
  /// Extracts plane bytes/layout from a [CameraImage] into a plain,
  /// isolate-transferable [RawCameraFrame]. Cheap (no per-pixel work) — safe
  /// to call on the UI isolate every frame. The actual YUV/BGRA -> RGB
  /// conversion happens later, off the UI isolate (see `isolate/frame_prep.dart`).
  static RawCameraFrame? extractRawFrame(CameraImage image, {required int rotationDegrees}) {
    if (image.format.group == ImageFormatGroup.yuv420) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      return RawCameraFrame(
        width: image.width,
        height: image.height,
        isYuv420: true,
        plane0: yPlane.bytes,
        plane1: uPlane.bytes,
        plane2: vPlane.bytes,
        plane0RowStride: yPlane.bytesPerRow,
        uvRowStride: uPlane.bytesPerRow,
        uvPixelStride: uPlane.bytesPerPixel ?? 1,
        rotationDegrees: rotationDegrees,
      );
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return RawCameraFrame(
        width: image.width,
        height: image.height,
        isYuv420: false,
        plane0: image.planes[0].bytes,
        rotationDegrees: rotationDegrees,
      );
    }
    return null;
  }
}
