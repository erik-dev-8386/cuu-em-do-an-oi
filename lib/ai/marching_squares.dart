import 'dart:math';
import 'dart:ui';
import 'mask_reconstruct.dart';

class MarchingSquaresProcessor {
  /// Extracts a smooth 2D contour polygon from a localized binary grid ROI
  static List<Offset> extractContour(LocalizedMaskRoi roi) {
    final grid = roi.binaryGrid;
    final int h = grid.length;
    if (h == 0) return [];
    final int w = grid[0].length;
    if (w == 0) return [];

    Point<int>? startPt;
    outerLoop:
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (grid[y][x]) {
          startPt = Point(x, y);
          break outerLoop;
        }
      }
    }

    if (startPt == null) return [];

    final List<Point<int>> boundaryPoints = [];
    const List<int> dx = [0, 1, 1, 1, 0, -1, -1, -1];
    const List<int> dy = [-1, -1, 0, 1, 1, 1, 0, -1];

    Point<int> currPt = startPt;
    int backtrackDir = 6;
    int iterations = 0;
    const int maxIterations = 2000;

    do {
      boundaryPoints.add(currPt);
      bool foundNext = false;
      int startDir = (backtrackDir + 1) % 8;

      for (int i = 0; i < 8; i++) {
        int dir = (startDir + i) % 8;
        int nx = currPt.x + dx[dir];
        int ny = currPt.y + dy[dir];

        if (nx >= 0 && nx < w && ny >= 0 && ny < h && grid[ny][nx]) {
          currPt = Point(nx, ny);
          backtrackDir = (dir + 4) % 8;
          foundNext = true;
          break;
        }
      }

      if (!foundNext) break;
      iterations++;
    } while (currPt != startPt && iterations < maxIterations);

    if (boundaryPoints.isEmpty) return [];

    // Map ROI local coordinates to 640 space coordinates
    final List<Offset> points640 = [];
    for (var pt in boundaryPoints) {
      points640.add(Offset(
        (roi.boxX1 + pt.x).toDouble(),
        (roi.boxY1 + pt.y).toDouble(),
      ));
    }

    return points640;
  }
}
