import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
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
}

class NailPostProcessor {
  static double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  /// Giải mã Output0 (Detections) và Output1 (Mask Prototypes) động theo kích thước model
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

      // 3. ĐỌC MA TRẬN MASK PROTOTYPE TỪ OUTPUT 1
      dynamic rawOut1;
      if (outputs.length > 1) {
        rawOut1 = outputs[1]?.value;
      }

      final double imgW = letterbox.originalWidth.toDouble();
      final double imgH = letterbox.originalHeight.toDouble();
      final int inputSize = letterbox.targetSize; // 416 hoặc 640...

      // 4. TÁI TẠO MASK & RÚT BIÊN CONTOUR THEO KÍCH THƯỚC MODEL ĐỘNG
      for (var det in nmsDetections) {
        List<Offset> polygonTarget = [];

        if (rawOut1 != null) {
          polygonTarget = _reconstructUltralyticsMaskContour(
            det,
            rawOut1,
            maskThreshold,
            inputSize,
          );
        }

        // Ellipse fallback nếu mask proto rỗng
        if (polygonTarget.isEmpty) {
          polygonTarget = _generateBoxEllipsePoints(det);
        }

        // 5. UN-LETTERBOX VỀ TỌA ĐỘ ẢNH GỐC
        final List<Offset> origPolygon = [];
        for (var pt in polygonTarget) {
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
      print("⚠️ Lỗi giải mã Output YOLOv8-Seg: $e\n$stack");
    }

    return nailPolygons;
  }

  /// Trích xuất danh sách Candidate từ Output0 (Tự động thích ứng [37][anchors] hoặc [anchors][37])
  static List<Detection> _parseOutput0(dynamic rawOut0, double confThreshold) {
    final List<Detection> candidates = [];

    dynamic matrix = rawOut0;
    if (matrix is List && matrix.length == 1 && matrix[0] is List) {
      matrix = matrix[0];
    }

    if (matrix is! List || matrix.isEmpty) return candidates;

    int dimA = matrix.length;
    int dimB = (matrix[0] is List) ? (matrix[0] as List).length : 0;

    print("📊 Output0 Tensor Structure: dimA=$dimA, dimB=$dimB");

    // Case 1: [37][anchors] - Channels First
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
    // Case 2: [anchors][37] - Anchors First
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

    if (candidates.isNotEmpty) {
      print("💡 [Sample Detection 0]: cx=${candidates[0].cx}, cy=${candidates[0].cy}, w=${candidates[0].w}, h=${candidates[0].h}, score=${candidates[0].score}");
    } else {
      print("⚠️ Không tìm thấy Detection nào vượt ngưỡng Confidence $confThreshold");
    }

    return candidates;
  }

  /// Reconstruct Mask với kích thước Prototype tự động (104x104 hoặc 160x160)
  /// và Bilinear Upsample lên inputSize (416 hoặc 640)
  static List<Offset> _reconstructUltralyticsMaskContour(
    Detection det,
    dynamic rawProto,
    double maskThreshold,
    int inputSize,
  ) {
    int protoW = 160;
    int protoH = 160;

    if (rawProto != null) {
      final dims = _getProtoDimensions(rawProto);
      protoW = dims.width;
      protoH = dims.height;
    }

    print("🧩 Proto Mask Resolution: ${protoW}x$protoH | Input Target Size: ${inputSize}x$inputSize");

    // Bước 1: Nhân 32 coeffs * Prototype (protoW x protoH)
    final List<Float32List> maskProto = List.generate(
      protoH,
      (_) => Float32List(protoW),
    );

    for (int y = 0; y < protoH; y++) {
      for (int x = 0; x < protoW; x++) {
        double val = 0.0;
        for (int c = 0; c < det.maskCoeffs.length && c < 32; c++) {
          val += det.maskCoeffs[c] * _getProtoVal(rawProto, c, y, x, protoH, protoW);
        }
        maskProto[y][x] = _sigmoid(val);
      }
    }

    // Bước 2: Upsample Bilinear từ (protoW x protoH) lên (inputSize x inputSize)
    final List<Float32List> maskTarget = _bilinearResize(
      maskProto,
      srcW: protoW,
      srcH: protoH,
      dstW: inputSize,
      dstH: inputSize,
    );

    // Bước 3: Crop Bounding Box trong không gian inputSize x inputSize & Threshold
    int boxX1 = (det.cx - det.w / 2.0).floor().clamp(0, inputSize - 1);
    int boxY1 = (det.cy - det.h / 2.0).floor().clamp(0, inputSize - 1);
    int boxX2 = (det.cx + det.w / 2.0).ceil().clamp(0, inputSize - 1);
    int boxY2 = (det.cy + det.h / 2.0).ceil().clamp(0, inputSize - 1);

    if (boxX2 <= boxX1 || boxY2 <= boxY1) return [];

    final List<List<bool>> binaryGrid = List.generate(
      inputSize,
      (_) => List.filled(inputSize, false),
    );

    for (int y = boxY1; y <= boxY2; y++) {
      for (int x = boxX1; x <= boxX2; x++) {
        if (maskTarget[y][x] >= maskThreshold) {
          binaryGrid[y][x] = true;
        }
      }
    }

    // Bước 4: Boundary Tracing trên ma trận nhị phân inputSize x inputSize
    final List<Point<int>> boundaryPoints = _traceBoundary(
      binaryGrid,
      boxX1, boxY1, boxX2, boxY2,
      gridSize: inputSize,
    );
    if (boundaryPoints.isEmpty) return [];

    final List<Offset> pointsTarget = [];
    for (var pt in boundaryPoints) {
      pointsTarget.add(Offset(pt.x.toDouble(), pt.y.toDouble()));
    }

    return pointsTarget;
  }

  /// Tự động dò độ phân giải Prototype Mask (104x104, 160x160...)
  static ({int width, int height}) _getProtoDimensions(dynamic rawProto) {
    if (rawProto is Float32List || rawProto is List<double> || rawProto is List<num>) {
      int totalLen = rawProto.length;
      int spatialSize = sqrt(totalLen / 32.0).round();
      if (spatialSize > 0) return (width: spatialSize, height: spatialSize);
    }

    if (rawProto is List) {
      dynamic level = rawProto;
      if (level.length == 1 && level[0] is List) {
        level = level[0];
      }
      if (level is List && level.isNotEmpty) {
        dynamic channel0 = level[0];
        if (channel0 is List) {
          int h = channel0.length;
          if (h > 0 && channel0[0] is List) {
            int w = (channel0[0] as List).length;
            return (width: w, height: h);
          } else if (h > 0 && channel0[0] is num) {
            int spatialSize = sqrt(h).round();
            return (width: spatialSize, height: spatialSize);
          }
        }
      }
    }
    return (width: 160, height: 160);
  }

  /// Bilinear Resize ma trận 2D Float từ (srcW x srcH) lên (dstW x dstH)
  static List<Float32List> _bilinearResize(
    List<Float32List> src, {
    required int srcW,
    required int srcH,
    required int dstW,
    required int dstH,
  }) {
    final List<Float32List> dst = List.generate(dstH, (_) => Float32List(dstW));
    final double scaleX = srcW / dstW;
    final double scaleY = srcH / dstH;

    for (int y = 0; y < dstH; y++) {
      double gy = (y + 0.5) * scaleY - 0.5;
      int y1 = gy.floor().clamp(0, srcH - 2);
      int y2 = y1 + 1;
      double dy = gy - y1;

      for (int x = 0; x < dstW; x++) {
        double gx = (x + 0.5) * scaleX - 0.5;
        int x1 = gx.floor().clamp(0, srcW - 2);
        int x2 = x1 + 1;
        double dx = gx - x1;

        double v11 = src[y1][x1];
        double v21 = src[y1][x2];
        double v12 = src[y2][x1];
        double v22 = src[y2][x2];

        double val = (1.0 - dx) * (1.0 - dy) * v11 +
            dx * (1.0 - dy) * v21 +
            (1.0 - dx) * dy * v12 +
            dx * dy * v22;

        dst[y][x] = val;
      }
    }
    return dst;
  }

  /// Trích xuất giá trị từ Tensor Proto Mask
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

  /// Moore-Neighbor Tracing Algorithm trên ma trận nhị phân gridSize x gridSize
  static List<Point<int>> _traceBoundary(
    List<List<bool>> grid,
    int minX,
    int minY,
    int maxX,
    int maxY, {
    required int gridSize,
  }) {
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
    const int maxIterations = 4000;

    do {
      result.add(currPt);
      bool foundNext = false;
      int startDir = (backtrackDir + 1) % 8;

      for (int i = 0; i < 8; i++) {
        int dir = (startDir + i) % 8;
        int nx = currPt.x + dx[dir];
        int ny = currPt.y + dy[dir];

        if (nx >= 0 && nx < gridSize && ny >= 0 && ny < gridSize && grid[ny][nx]) {
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
