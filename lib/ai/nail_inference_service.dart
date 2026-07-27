import 'dart:ui';
import 'package:image/image.dart' as img;
import 'nail_onnx_service.dart';
import 'nail_post_processor.dart';

class NailInferenceResult {
  final List<List<Offset>> polygons;
  final int originalWidth;
  final int originalHeight;
  final Duration inferenceTime;

  NailInferenceResult({
    required this.polygons,
    required this.originalWidth,
    required this.originalHeight,
    required this.inferenceTime,
  });
}

class NailInferenceService {
  final NailOnnxService _onnxService = NailOnnxService();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _onnxService.initModel();
    _isInitialized = true;
  }

  /// Entry point for both Snapshot (photo) and AR (camera frame) inference
  Future<NailInferenceResult> processImage(
    img.Image rawImage, {
    double confThreshold = 0.12,
    double iouThreshold = 0.45,
    double maskThreshold = 0.35,
    bool isSync = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    await init();

    final onnxResult = await _onnxService.processImage(
      rawImage,
      isSync: isSync,
    );

    var polygons = NailPostProcessor.decodeOutputs(
      outputs: onnxResult.outputs,
      letterbox: onnxResult.letterbox,
      confThreshold: confThreshold,
      iouThreshold: iouThreshold,
      maskThreshold: maskThreshold,
    );
    // Disable FallbackNailDetector by default to prevent drawing fake nails on skin/faces
    // if (polygons.isEmpty) {
    //   polygons = FallbackNailDetector.estimate(rawImage);
    // }

    stopwatch.stop();

    return NailInferenceResult(
      polygons: polygons,
      originalWidth: rawImage.width,
      originalHeight: rawImage.height,
      inferenceTime: stopwatch.elapsed,
    );
  }

  void dispose() {
    _onnxService.dispose();
  }
}
