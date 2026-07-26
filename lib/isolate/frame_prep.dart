import 'package:image/image.dart' as img;
import '../ai/letterbox.dart';
import 'raw_camera_frame.dart';

/// Runs entirely on a background isolate via `compute()`: YUV420/BGRA8888 ->
/// RGB -> sensor-orientation rotation -> letterbox tensor. This is the
/// heaviest per-pixel work in the AR pipeline (two full-frame loops), so it
/// must not run on the UI isolate every camera frame.
LetterboxResult prepareFrameForInference(RawCameraFrame raw) {
  img.Image rgb = raw.isYuv420 ? _yuv420ToImage(raw) : _bgraToImage(raw);

  if (raw.rotationDegrees == 90 || raw.rotationDegrees == 270) {
    rgb = img.copyRotate(rgb, angle: raw.rotationDegrees);
  }

  return LetterboxProcessor.process(rgb);
}

img.Image _yuv420ToImage(RawCameraFrame raw) {
  final int width = raw.width;
  final int height = raw.height;
  final imgImage = img.Image(width: width, height: height);

  final yBuffer = raw.plane0;
  final uBuffer = raw.plane1!;
  final vBuffer = raw.plane2!;

  final int yRowStride = raw.plane0RowStride;
  final int uvRowStride = raw.uvRowStride;
  final int uvPixelStride = raw.uvPixelStride;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int yIndex = y * yRowStride + x;
      final int uvIndex = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;

      final int yValue = yBuffer[yIndex];
      final int uValue = uBuffer[uvIndex] - 128;
      final int vValue = vBuffer[uvIndex] - 128;

      int r = (yValue + 1.402 * vValue).round().clamp(0, 255);
      int g = (yValue - 0.344136 * uValue - 0.714136 * vValue).round().clamp(0, 255);
      int b = (yValue + 1.772 * uValue).round().clamp(0, 255);

      imgImage.setPixelRgb(x, y, r, g, b);
    }
  }

  return imgImage;
}

img.Image _bgraToImage(RawCameraFrame raw) {
  final int width = raw.width;
  final int height = raw.height;
  final bytes = raw.plane0;
  final imgImage = img.Image(width: width, height: height);

  int bufferIndex = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int b = bytes[bufferIndex];
      final int g = bytes[bufferIndex + 1];
      final int r = bytes[bufferIndex + 2];

      imgImage.setPixelRgb(x, y, r, g, b);
      bufferIndex += 4;
    }
  }

  return imgImage;
}
