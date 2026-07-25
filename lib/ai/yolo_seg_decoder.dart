import 'dart:math';
import 'dart:ui';
import 'mask_reconstruct.dart';
import 'marching_squares.dart';
import 'nms.dart';
import 'onnx_service.dart';

class YoloSegDecoder {
  static double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  /// Master Ultralytics Decoder: Anchor Parsing -> NMS -> ROI Reconstruct -> Contour -> Undo Letterbox
  static List<List<Offset>> decode({
    required YoloSegOutputs rawOutputs,
    double confThreshold = 0.35,
    double iouThreshold = 0.45,
    double maskThreshold = 0.5,
  }) {
    if (rawOutputs.pred == null) return [];

    final List<List<Offset>> resultPolygons = [];

    // Step 1: Parse prediction anchors
    final candidates = _parseOutput0(rawOutputs.pred, confThreshold);
    if (candidates.isEmpty) return [];

    // Step 2: NMS Filtering
    final nmsDetections = NmsProcessor.filter(
      candidates: candidates,
      iouThreshold: iouThreshold,
      maxKeep: 10,
    );

    if (nmsDetections.isEmpty) return [];

    final double imgW = rawOutputs.letterbox.originalWidth.toDouble();
    final double imgH = rawOutputs.letterbox.originalHeight.toDouble();

    // Step 3 & 4: Mask ROI Reconstruction & Marching Squares Contour Extraction
    for (var det in nmsDetections) {
      LocalizedMaskRoi? maskRoi;
      if (rawOutputs.proto != null) {
        maskRoi = MaskReconstructionProcessor.reconstructRoiMask(
          det: det,
          rawProto: rawOutputs.proto,
          maskThreshold: maskThreshold,
        );
      }

      List<Offset> polygon640 = [];
      if (maskRoi != null) {
        polygon640 = MarchingSquaresProcessor.extractContour(maskRoi);
      }

      // Ellipse fallback if contour extraction returns empty
      if (polygon640.isEmpty) {
        polygon640 = _generateBoxEllipsePoints(det);
      }

      // Step 5: Undo Letterbox to Original Image Coordinates
      final List<Offset> origPolygon = [];
      for (var pt in polygon640) {
        double origX = (pt.dx - rawOutputs.letterbox.padLeft) / rawOutputs.letterbox.scale;
        double origY = (pt.dy - rawOutputs.letterbox.padTop) / rawOutputs.letterbox.scale;

        origX = origX.clamp(0.0, imgW);
        origY = origY.clamp(0.0, imgH);

        origPolygon.add(Offset(origX, origY));
      }

      if (origPolygon.length >= 3) {
        resultPolygons.add(origPolygon);
      }
    }

    return resultPolygons;
  }

  static List<YoloDetection> _parseOutput0(dynamic rawOut0, double confThreshold) {
    final List<YoloDetection> candidates = [];

    dynamic matrix = rawOut0;
    if (matrix is List && matrix.length == 1 && matrix[0] is List) {
      matrix = matrix[0];
    }

    if (matrix is! List || matrix.isEmpty) return candidates;

    int dimA = matrix.length;
    int dimB = (matrix[0] is List) ? (matrix[0] as List).length : 0;

    // Case 1: [37][8400] - Channels First
    if (dimA <= 40 && dimB > 100) {
      final int numChannels = dimA;
      final int numAnchors = dimB;

      final List rowCX = matrix[0] as List;
      final List rowCY = matrix[1] as List;
      final List rowW = matrix[2] as List;
      final List rowH = matrix[3] as List;
      final List rowScore = matrix[4] as List;

      for (int i = 0; i < numAnchors; i++) {
        double rawScore = (rowScore[i] as num).toDouble();
        double score = (rawScore > 1.0 || rawScore < 0.0) ? _sigmoid(rawScore) : rawScore;

        if (score >= confThreshold) {
          double cx = (rowCX[i] as num).toDouble();
          double cy = (rowCY[i] as num).toDouble();
          double w = (rowW[i] as num).toDouble();
          double h = (rowH[i] as num).toDouble();

          List<double> coeffs = [];
          for (int c = 5; c < numChannels && c < 37; c++) {
            coeffs.add(((matrix[c] as List)[i] as num).toDouble());
          }

          candidates.add(YoloDetection(
            cx: cx, cy: cy, w: w, h: h, score: score, maskCoeffs: coeffs,
          ));
        }
      }
    }
    // Case 2: [8400][37] - Anchors First
    else if (dimA > 100 && dimB <= 40) {
      final int numAnchors = dimA;
      final int numChannels = dimB;

      for (int i = 0; i < numAnchors; i++) {
        final List anchorData = matrix[i] as List;
        double rawScore = (anchorData[4] as num).toDouble();
        double score = (rawScore > 1.0 || rawScore < 0.0) ? _sigmoid(rawScore) : rawScore;

        if (score >= confThreshold) {
          double cx = (anchorData[0] as num).toDouble();
          double cy = (anchorData[1] as num).toDouble();
          double w = (anchorData[2] as num).toDouble();
          double h = (anchorData[3] as num).toDouble();

          List<double> coeffs = [];
          for (int c = 5; c < numChannels && c < 37; c++) {
            coeffs.add((anchorData[c] as num).toDouble());
          }

          candidates.add(YoloDetection(
            cx: cx, cy: cy, w: w, h: h, score: score, maskCoeffs: coeffs,
          ));
        }
      }
    }

    return candidates;
  }

  static List<Offset> _generateBoxEllipsePoints(YoloDetection det) {
    final List<Offset> points = [];
    const int steps = 16;
    for (int i = 0; i < steps; i++) {
      double angle = (2 * pi * i) / steps;
      double px = det.cx + (det.w / 2.0) * cos(angle);
      double py = det.cy + (det.h / 2.0) * sin(angle);
      points.add(Offset(px, py));
    }
    return points;
  }
}
