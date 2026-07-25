import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'image_processor.dart';

class Detection {
  final double cx;
  final double cy;
  final double w;
  final double h;
  final double score;
  final List<double> maskCoeffs;

  Detection({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    required this.score,
    required this.maskCoeffs,
  });

  Rect get boundingBox => Rect.fromLTWH(
        cx - w / 2.0,
        cy - h / 2.0,
        w,
        h,
      );
}

class NailPostProcessor {
  static double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  /// Giải mã Output0 (Detections) và Output1 (Mask Prototypes) theo pipeline Ultralytics ROI Tối ưu
  static List<List<Offset>> decodeOutputs({
    required List<OrtValue?>? outputs,
    required LetterboxResult letterbox,
    double confThreshold = 0.35,
    double iouThreshold = 0.45,
    double maskThreshold = 0.5,
  }) {
    if (outputs == null || outputs.isEmpty) return [];

    final List<List<Offset>> nailPolygons = [];

    try {
      final rawOut0 = outputs[0]?.value;
      if (rawOut0 == null) return [];

      // 1. GIẢI MÃ DỮ LIỆU ANCHORS TỪ OUTPUT 0
      final List<Detection> candidates = _parseOutput0(rawOut0, confThreshold);
      if (candidates.isEmpty) return [];

      // 2. NMS (NON-MAXIMUM SUPPRESSION)
      candidates.sort((a, b) => b.score.compareTo(a.score));
      final List<Detection> nmsDetections = [];
      for (var det in candidates) {
        bool keep = true;
        for (var kept in nmsDetections) {
          if (_calculateIoU(det, kept) > iouThreshold) {
            keep = false;
            break;
          }
        }
        if (keep) {
          nmsDetections.add(det);
          if (nmsDetections.length >= 10) break; // Tối đa 10 móng
        }
      }

      if (nmsDetections.isEmpty) return [];

      // 3. ĐỌC MA TRẬN MASK PROTOTYPE TỪ OUTPUT 1 ([1, 32, 160, 160])
      dynamic rawOut1;
      if (outputs.length > 1) {
        rawOut1 = outputs[1]?.value;
      }

      final double imgW = letterbox.originalWidth.toDouble();
      final double imgH = letterbox.originalHeight.toDouble();

      // 4. TÁI TẠO MASK & RÚT BIÊN CONTOUR THEO QUY TRÌNH ULTRALYTICS ROI
      for (var det in nmsDetections) {
        List<Offset> polygon640 = [];

        if (rawOut1 != null) {
          polygon640 = _reconstructUltralyticsRoiMaskContour(det, rawOut1, maskThreshold);
        }

        // Ellipse fallback nếu mask proto rỗng
        if (polygon640.isEmpty) {
          polygon640 = _generateBoxEllipsePoints(det);
        }

        // 5. UN-LETTERBOX VỀ TỌA ĐỘ ẢNH GỐC
        final List<Offset> origPolygon = [];
        for (var pt in polygon640) {
          double origX = (pt.dx - letterbox.padLeft) / letterbox.scale;
          double origY = (pt.dy - letterbox.padTop) / letterbox.scale;

          origX = origX.clamp(0.0, imgW);
          origY = origY.clamp(0.0, imgH);

          origPolygon.add(Offset(origX, origY));
        }

        if (origPolygon.length >= 3) {
          nailPolygons.add(origPolygon);
        }
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint("⚠️ Lỗi giải mã Output YOLOv8-Seg: $e\n$stack");
      }
    }

    return nailPolygons;
  }

  /// Trích xuất danh sách Candidate từ Output0 (Tự động thích ứng [37][8400] hoặc [8400][37])
  static List<Detection> _parseOutput0(dynamic rawOut0, double confThreshold) {
    final List<Detection> candidates = [];

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

          candidates.add(Detection(
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

          candidates.add(Detection(
            cx: cx, cy: cy, w: w, h: h, score: score, maskCoeffs: coeffs,
          ));
        }
      }
    }

    return candidates;
  }

  /// Quy trình Reconstruct chuẩn Ultralytics Tối ưu ROI (ROI-only computation):
  /// 1. Tọa độ Box trong 640 -> Map sang 160 Prototype Space [px1, py1, px2, py2]
  /// 2. Nhân 32 Coeffs * Prototype 160 CHỈ TRONG VÙNG ROI
  /// 3. Upsample Bilinear CHỈ MẶT MẮT MÓN ROI lên Kích thước Bounding Box trong 640
  /// 4. Boundary Tracing trong phạm vi Bounding Box (tăng tốc ~170 lần)
  static List<Offset> _reconstructUltralyticsRoiMaskContour(
    Detection det,
    dynamic rawProto,
    double maskThreshold,
  ) {
    int boxX1 = (det.cx - det.w / 2.0).floor().clamp(0, 639);
    int boxY1 = (det.cy - det.h / 2.0).floor().clamp(0, 639);
    int boxX2 = (det.cx + det.w / 2.0).ceil().clamp(0, 639);
    int boxY2 = (det.cy + det.h / 2.0).ceil().clamp(0, 639);

    if (boxX2 <= boxX1 || boxY2 <= boxY1) return [];

    // Map sang 160 prototype space (160 / 640 = 0.25)
    int px1 = (boxX1 * 0.25).floor().clamp(0, 159);
    int py1 = (boxY1 * 0.25).floor().clamp(0, 159);
    int px2 = (boxX2 * 0.25).ceil().clamp(0, 159);
    int py2 = (boxY2 * 0.25).ceil().clamp(0, 159);

    int roiWProto = px2 - px1 + 1;
    int roiHProto = py2 - py1 + 1;

    if (roiWProto <= 0 || roiHProto <= 0) return [];

    // 1. Tính toán Sigmoid Mask CHỈ trên vùng ROI 160
    final List<Float32List> maskRoiProto = List.generate(
      roiHProto,
      (_) => Float32List(roiWProto),
    );

    for (int y = 0; y < roiHProto; y++) {
      int protoY = py1 + y;
      for (int x = 0; x < roiWProto; x++) {
        int protoX = px1 + x;
        double val = 0.0;
        for (int c = 0; c < det.maskCoeffs.length && c < 32; c++) {
          val += det.maskCoeffs[c] * _getProtoVal(rawProto, c, protoY, protoX, 160, 160);
        }
        maskRoiProto[y][x] = _sigmoid(val);
      }
    }

    // 2. Upsample Bilinear CHỈ VÙNG ROI lên không gian Box (640)
    final int boxW = boxX2 - boxX1 + 1;
    final int boxH = boxY2 - boxY1 + 1;

    final List<List<bool>> binaryGrid640 = List.generate(
      640,
      (_) => List.filled(640, false),
    );

    final double scaleX = (roiWProto > 1) ? (roiWProto - 1.0) / max(1.0, boxW - 1.0) : 0.0;
    final double scaleY = (roiHProto > 1) ? (roiHProto - 1.0) / max(1.0, boxH - 1.0) : 0.0;

    for (int dy = 0; dy < boxH; dy++) {
      double gy = dy * scaleY;
      int y1 = gy.floor().clamp(0, roiHProto - 1);
      int y2 = (y1 + 1).clamp(0, roiHProto - 1);
      double fy = gy - y1;

      int targetY = boxY1 + dy;
      if (targetY < 0 || targetY >= 640) continue;

      for (int dx = 0; dx < boxW; dx++) {
        double gx = dx * scaleX;
        int x1 = gx.floor().clamp(0, roiWProto - 1);
        int x2 = (x1 + 1).clamp(0, roiWProto - 1);
        double fx = gx - x1;

        double v11 = maskRoiProto[y1][x1];
        double v21 = maskRoiProto[y1][x2];
        double v12 = maskRoiProto[y2][x1];
        double v22 = maskRoiProto[y2][x2];

        double val = (1.0 - fx) * (1.0 - fy) * v11 +
            fx * (1.0 - fy) * v21 +
            (1.0 - fx) * fy * v12 +
            fx * fy * v22;

        if (val >= maskThreshold) {
          int targetX = boxX1 + dx;
          if (targetX >= 0 && targetX < 640) {
            binaryGrid640[targetY][targetX] = true;
          }
        }
      }
    }

    // 3. Boundary Tracing trên lưới 640x640 trong phạm vi Box
    final List<Point<int>> boundaryPoints = _traceBoundary(binaryGrid640, boxX1, boxY1, boxX2, boxY2);
    if (boundaryPoints.isEmpty) return [];

    final List<Offset> points640 = [];
    for (var pt in boundaryPoints) {
      points640.add(Offset(pt.x.toDouble(), pt.y.toDouble()));
    }

    return points640;
  }

  /// Trích xuất giá trị từ Tensor Proto Mask 160x160
  static double _getProtoVal(
    dynamic rawProto,
    int c,
    int y,
    int x,
    int h,
    int w,
  ) {
    if (rawProto == null) return 0.0;

    if (rawProto is Float32List || rawProto is List<double> || rawProto is List<num>) {
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

  /// Moore-Neighbor Tracing Algorithm trên lưới 640x640
  static List<Point<int>> _traceBoundary(
    List<List<bool>> grid,
    int minX,
    int minY,
    int maxX,
    int maxY,
  ) {
    Point<int>? startPt;

    outerLoop:
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        if (grid[y][x]) {
          startPt = Point(x, y);
          break outerLoop;
        }
      }
    }

    if (startPt == null) return [];

    final List<Point<int>> result = [];
    const List<int> dx = [0, 1, 1, 1, 0, -1, -1, -1];
    const List<int> dy = [-1, -1, 0, 1, 1, 1, 0, -1];

    Point<int> currPt = startPt;
    int backtrackDir = 6;
    int iterations = 0;
    const int maxIterations = 2000;

    do {
      result.add(currPt);
      bool foundNext = false;
      int startDir = (backtrackDir + 1) % 8;

      for (int i = 0; i < 8; i++) {
        int dir = (startDir + i) % 8;
        int nx = currPt.x + dx[dir];
        int ny = currPt.y + dy[dir];

        if (nx >= 0 && nx < 640 && ny >= 0 && ny < 640 && grid[ny][nx]) {
          currPt = Point(nx, ny);
          backtrackDir = (dir + 4) % 8;
          foundNext = true;
          break;
        }
      }

      if (!foundNext) break;
      iterations++;
    } while (currPt != startPt && iterations < maxIterations);

    return result;
  }

  /// Fallback oval cho Bounding Box nếu không có Contour
  static List<Offset> _generateBoxEllipsePoints(Detection det) {
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

  static double _calculateIoU(Detection a, Detection b) {
    double x1 = max(a.cx - a.w / 2.0, b.cx - b.w / 2.0);
    double y1 = max(a.cy - a.h / 2.0, b.cy - b.h / 2.0);
    double x2 = min(a.cx + a.w / 2.0, b.cx + b.w / 2.0);
    double y2 = min(a.cy + a.h / 2.0, b.cy + b.h / 2.0);

    double intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    double areaA = a.w * a.h;
    double areaB = b.w * b.h;
    double unionArea = areaA + areaB - intersection;

    return unionArea <= 0 ? 0.0 : intersection / unionArea;
  }
}
