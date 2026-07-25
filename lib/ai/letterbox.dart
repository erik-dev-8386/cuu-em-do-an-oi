import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class LetterboxResult {
  final Float32List tensor;
  final double scale;
  final double padLeft;
  final double padTop;
  final int originalWidth;
  final int originalHeight;

  LetterboxResult({
    required this.tensor,
    required this.scale,
    required this.padLeft,
    required this.padTop,
    required this.originalWidth,
    required this.originalHeight,
  });
}

class LetterboxProcessor {
  static LetterboxResult process(img.Image inputImage, {int targetSize = 640}) {
    final int imgW = inputImage.width;
    final int imgH = inputImage.height;

    final double scale = min(targetSize / imgW, targetSize / imgH);
    final int newW = (imgW * scale).round();
    final int newH = (imgH * scale).round();

    final double padLeft = ((targetSize - newW) / 2.0).floorToDouble();
    final double padTop = ((targetSize - newH) / 2.0).floorToDouble();

    final resizedImage = img.copyResize(inputImage, width: newW, height: newH);

    final Float32List float32List = Float32List(1 * 3 * targetSize * targetSize);
    final double fillValue = 114.0 / 255.0;
    float32List.fillRange(0, float32List.length, fillValue);

    final int channelStride = targetSize * targetSize;

    for (int y = 0; y < newH; y++) {
      final int tensorY = (padTop + y).toInt();
      if (tensorY < 0 || tensorY >= targetSize) continue;

      for (int x = 0; x < newW; x++) {
        final int tensorX = (padLeft + x).toInt();
        if (tensorX < 0 || tensorX >= targetSize) continue;

        final pixel = resizedImage.getPixel(x, y);
        final int offset = tensorY * targetSize + tensorX;

        float32List[offset] = pixel.r / 255.0;
        float32List[channelStride + offset] = pixel.g / 255.0;
        float32List[channelStride * 2 + offset] = pixel.b / 255.0;
      }
    }

    return LetterboxResult(
      tensor: float32List,
      scale: scale,
      padLeft: padLeft,
      padTop: padTop,
      originalWidth: imgW,
      originalHeight: imgH,
    );
  }
}
