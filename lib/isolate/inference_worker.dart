import 'dart:ui';
import 'package:image/image.dart' as img;
import '../ai/onnx_service.dart';
import '../ai/yolo_seg_decoder.dart';

class InferenceWorkerResult {
  final List<List<Offset>> polygons;
  final int originalWidth;
  final int originalHeight;
  final Duration inferenceTime;

  InferenceWorkerResult({
    required this.polygons,
    required this.originalWidth,
    required this.originalHeight,
    required this.inferenceTime,
  });
}

class InferenceWorker {
  final OnnxService _onnxService = OnnxService();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _onnxService.initModel();
    _isInitialized = true;
  }

  Future<InferenceWorkerResult> processFrame(
    img.Image frameImage, {
    double confThreshold = 0.35,
    double iouThreshold = 0.45,
    double maskThreshold = 0.5,
  }) async {
    final stopwatch = Stopwatch()..start();
    await init();

    final rawOutputs = await _onnxService.runInference(frameImage);

    final polygons = YoloSegDecoder.decode(
      rawOutputs: rawOutputs,
      confThreshold: confThreshold,
      iouThreshold: iouThreshold,
      maskThreshold: maskThreshold,
    );

    stopwatch.stop();

    return InferenceWorkerResult(
      polygons: polygons,
      originalWidth: frameImage.width,
      originalHeight: frameImage.height,
      inferenceTime: stopwatch.elapsed,
    );
  }

  void dispose() {
    _onnxService.dispose();
  }
}
