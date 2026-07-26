import 'dart:ui';
import '../ai/letterbox.dart';
import '../ai/onnx_service.dart';
import '../ai/yolo_seg_decoder.dart';

/// Input for [decodePolygons]. [pred]/[proto] must already be materialized
/// plain Dart data (the `.value` of the ONNX outputs, read on the isolate
/// that owns the inference session) — never pass a native/plugin handle here.
class DecodeInput {
  final dynamic pred;
  final dynamic proto;
  final LetterboxResult letterbox;
  final double confThreshold;
  final double iouThreshold;
  final double maskThreshold;

  DecodeInput({
    required this.pred,
    required this.proto,
    required this.letterbox,
    required this.confThreshold,
    required this.iouThreshold,
    required this.maskThreshold,
  });
}

/// Runs entirely on a background isolate via `compute()`: NMS, ROI mask
/// reconstruction, marching-squares contour tracing and radial resampling.
/// Pure Dart / pure math — no plugin or platform-channel calls, so it is
/// always safe off the UI isolate.
List<List<Offset>> decodePolygons(DecodeInput input) {
  return YoloSegDecoder.decode(
    rawOutputs: YoloSegOutputs(
      pred: input.pred,
      proto: input.proto,
      letterbox: input.letterbox,
    ),
    confThreshold: input.confThreshold,
    iouThreshold: input.iouThreshold,
    maskThreshold: input.maskThreshold,
  );
}
