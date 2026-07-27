import 'dart:math';
import 'dart:typed_data';
import 'nms.dart';

class LocalizedMaskRoi {
  final List<List<bool>> binaryGrid;
  final int boxX1;
  final int boxY1;
  final int boxX2;
  final int boxY2;

  LocalizedMaskRoi({
    required this.binaryGrid,
    required this.boxX1,
    required this.boxY1,
    required this.boxX2,
    required this.boxY2,
  });
}

class MaskReconstructionProcessor {
  static double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  /// Step 3 & 4: Crop at Proto scale + Upsample ROI
  static LocalizedMaskRoi? reconstructRoiMask({
    required YoloDetection det,
    required dynamic rawProto,
    required int inputSize,
    double maskThreshold = 0.5,
  }) {
    if (rawProto == null) return null;

    final protoShape = _inferProtoShape(rawProto, inputSize);
    final protoChannels = protoShape.channels;
    final protoH = protoShape.height;
    final protoW = protoShape.width;
    final modelMax = inputSize - 1;

    int boxX1 = (det.x1).floor().clamp(0, modelMax);
    int boxY1 = (det.y1).floor().clamp(0, modelMax);
    int boxX2 = (det.x2).ceil().clamp(0, modelMax);
    int boxY2 = (det.y2).ceil().clamp(0, modelMax);

    if (boxX2 <= boxX1 || boxY2 <= boxY1) return null;

    final protoScaleX = protoW / inputSize;
    final protoScaleY = protoH / inputSize;
    int px1 = (boxX1 * protoScaleX).floor().clamp(0, protoW - 1);
    int py1 = (boxY1 * protoScaleY).floor().clamp(0, protoH - 1);
    int px2 = (boxX2 * protoScaleX).ceil().clamp(0, protoW - 1);
    int py2 = (boxY2 * protoScaleY).ceil().clamp(0, protoH - 1);

    int roiWProto = px2 - px1 + 1;
    int roiHProto = py2 - py1 + 1;

    if (roiWProto <= 0 || roiHProto <= 0) return null;

    // 1. Matrix multiply coefficients * prototype ONLY inside ROI
    final List<Float32List> maskRoiProto = List.generate(
      roiHProto,
      (_) => Float32List(roiWProto),
    );

    for (int y = 0; y < roiHProto; y++) {
      int protoY = py1 + y;
      for (int x = 0; x < roiWProto; x++) {
        int protoX = px1 + x;
        double val = 0.0;
        for (int c = 0; c < det.maskCoeffs.length && c < protoChannels; c++) {
          val +=
              det.maskCoeffs[c] *
              _getProtoVal(rawProto, c, protoY, protoX, protoH, protoW);
        }
        maskRoiProto[y][x] = _sigmoid(val);
      }
    }

    // 2. Bilinear upsample ONLY the small ROI mask to Box dimensions in model space
    final int boxW = boxX2 - boxX1 + 1;
    final int boxH = boxY2 - boxY1 + 1;

    final List<List<bool>> binaryGrid = List.generate(
      boxH,
      (_) => List.filled(boxW, false),
    );

    final double scaleX = (roiWProto > 1)
        ? (roiWProto - 1.0) / max(1.0, boxW - 1.0)
        : 0.0;
    final double scaleY = (roiHProto > 1)
        ? (roiHProto - 1.0) / max(1.0, boxH - 1.0)
        : 0.0;

    for (int dy = 0; dy < boxH; dy++) {
      double gy = dy * scaleY;
      int y1 = gy.floor().clamp(0, roiHProto - 1);
      int y2 = (y1 + 1).clamp(0, roiHProto - 1);
      double fy = gy - y1;

      for (int dx = 0; dx < boxW; dx++) {
        double gx = dx * scaleX;
        int x1 = gx.floor().clamp(0, roiWProto - 1);
        int x2 = (x1 + 1).clamp(0, roiWProto - 1);
        double fx = gx - x1;

        double v11 = maskRoiProto[y1][x1];
        double v21 = maskRoiProto[y1][x2];
        double v12 = maskRoiProto[y2][x1];
        double v22 = maskRoiProto[y2][x2];

        double val =
            (1.0 - fx) * (1.0 - fy) * v11 +
            fx * (1.0 - fy) * v21 +
            (1.0 - fx) * fy * v12 +
            fx * fy * v22;

        if (val >= maskThreshold) {
          binaryGrid[dy][dx] = true;
        }
      }
    }

    return LocalizedMaskRoi(
      binaryGrid: binaryGrid,
      boxX1: boxX1,
      boxY1: boxY1,
      boxX2: boxX2,
      boxY2: boxY2,
    );
  }

  static double _getProtoVal(
    dynamic rawProto,
    int c,
    int y,
    int x,
    int h,
    int w,
  ) {
    if (rawProto == null) return 0.0;

    if (rawProto is Float32List ||
        rawProto is List<double> ||
        rawProto is List<num>) {
      int idx = c * (h * w) + y * w + x;
      if (idx >= 0 && idx < rawProto.length) {
        return (rawProto[idx] as num).toDouble();
      }
      return 0.0;
    }

    if (rawProto is List) {
      dynamic level = rawProto;
      if (level.length == 1 && level[0] is List) {
        level = level[0];
      }

      if (level is List && c < level.length) {
        dynamic channelData = level[c];

        if (channelData is List && y < channelData.length) {
          dynamic rowData = channelData[y];
          if (rowData is List && x < rowData.length) {
            return (rowData[x] as num).toDouble();
          } else if (rowData is num && x == 0) {
            return rowData.toDouble();
          }
        } else if (channelData is List || channelData is Float32List) {
          int flatIdx = y * w + x;
          if (flatIdx >= 0 && flatIdx < channelData.length) {
            return (channelData[flatIdx] as num).toDouble();
          }
        }
      }
    }
    return 0.0;
  }

  static _ProtoShape _inferProtoShape(dynamic rawProto, int inputSize) {
    final fallbackSize = (inputSize / 4).round();
    if (rawProto is List && rawProto.isNotEmpty) {
      dynamic level = rawProto;
      if (level.length == 1 && level[0] is List) {
        level = level[0];
      }

      if (level is List && level.isNotEmpty) {
        final channels = level.length;
        final firstChannel = level.first;
        if (firstChannel is List && firstChannel.isNotEmpty) {
          final height = firstChannel.length;
          final firstRow = firstChannel.first;
          final width = firstRow is List ? firstRow.length : fallbackSize;
          return _ProtoShape(channels: channels, height: height, width: width);
        }
      }
    }

    return _ProtoShape(channels: 32, height: fallbackSize, width: fallbackSize);
  }
}

class _ProtoShape {
  final int channels;
  final int height;
  final int width;

  const _ProtoShape({
    required this.channels,
    required this.height,
    required this.width,
  });
}
