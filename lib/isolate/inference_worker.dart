import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../ai/onnx_service.dart';
import '../ai/yolo_seg_decoder.dart';
import 'frame_prep.dart';
import 'polygon_decode.dart';
import 'raw_camera_frame.dart';

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

  /// One-shot path for Snapshot Try-On: a single still image, already decoded.
  /// Runs synchronously on the calling isolate — acceptable for a one-off
  /// user action (the UI already shows a loading spinner while this runs).
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

  /// Hot-loop path for Realtime AR Try-On: every heavy, pure-Dart step (YUV/BGRA
  /// conversion, rotation, letterbox, mask reconstruction, contour tracing,
  /// resampling) runs on background isolates via `compute()`, so the UI isolate
  /// stays free to render the camera preview smoothly. The ONNX call itself is
  /// invoked from here, but the `onnxruntime` plugin is FFI-based (not platform
  /// channels) and `runAsync` already dispatches the native `Run` call to its
  /// own persistent worker isolate (`OrtIsolateSession`) internally — so it was
  /// never actually blocking the UI isolate in the first place.
  Future<InferenceWorkerResult> processCameraFrame(
    RawCameraFrame rawFrame, {
    double confThreshold = 0.35,
    double iouThreshold = 0.45,
    double maskThreshold = 0.5,
  }) async {
    final stopwatch = Stopwatch()..start();
    await init();

    final letterboxResult = await compute(prepareFrameForInference, rawFrame);

    final rawOutputs = await _onnxService.runInferenceOnTensor(letterboxResult);
    // Materialize the plugin's output values on this isolate *before* they
    // cross into the decode isolate — only plain Dart data may cross.
    final dynamic pred = rawOutputs.pred;
    final dynamic proto = rawOutputs.proto;

    final polygons = await compute(
      decodePolygons,
      DecodeInput(
        pred: pred,
        proto: proto,
        letterbox: letterboxResult,
        confThreshold: confThreshold,
        iouThreshold: iouThreshold,
        maskThreshold: maskThreshold,
      ),
    );

    stopwatch.stop();

    return InferenceWorkerResult(
      polygons: polygons,
      originalWidth: letterboxResult.originalWidth,
      originalHeight: letterboxResult.originalHeight,
      inferenceTime: stopwatch.elapsed,
    );
  }

  void dispose() {
    _onnxService.dispose();
  }
}
