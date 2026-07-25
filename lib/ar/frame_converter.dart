import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class FrameConverter {
  /// Converts [CameraImage] on an Isolate (Async)
  static Future<img.Image?> convertCameraImageAsync(CameraImage image) async {
    return await compute(convertCameraImageSync, image);
  }

  /// Converts [CameraImage] (YUV420_888 for Android or BGRA8888 for iOS) directly inline (Sync)
  static img.Image? convertCameraImageSync(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToImage(image);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("⚠️ Lỗi chuyển đổi CameraImage: $e");
      }
    }
    return null;
  }

  static img.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final imgImage = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

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

  static img.Image _convertBGRA8888ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final bytes = image.planes[0].bytes;

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
}
