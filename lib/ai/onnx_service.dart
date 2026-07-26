import 'dart:io';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'letterbox.dart';

class YoloSegOutputs {
  final dynamic pred; // Output0 [1, 37, 8400] or [1, 8400, 37]
  final dynamic proto; // Output1 [1, 32, 160, 160]
  final LetterboxResult letterbox;

  YoloSegOutputs({
    required this.pred,
    required this.proto,
    required this.letterbox,
  });
}

class OnnxService {
  OrtSession? _session;

  Future<void> initModel() async {
    if (_session != null) return;

    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    // Measured on-device: neither multi-threading nor XNNPACK moved the needle
    // on this model/CPU (inference itself dominates at ~2.6-3.4s regardless).
    // Keeping graph optimization (always safe) and multi-threading (harmless
    // default) but dropped the XNNPACK attempt since it added complexity with
    // no measured benefit here.
    sessionOptions.setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    sessionOptions.setIntraOpNumThreads(Platform.numberOfProcessors);

    final rawBytes = await rootBundle.load('assets/models/best.onnx');
    final bytes = rawBytes.buffer.asUint8List();

    _session = OrtSession.fromBuffer(bytes, sessionOptions);
  }

  Future<YoloSegOutputs> runInference(img.Image rawImage) async {
    final letterboxResult = LetterboxProcessor.process(rawImage);
    return runInferenceOnTensor(letterboxResult);
  }

  /// Same as [runInference] but skips the letterbox step, for callers (the AR
  /// pipeline) that already prepared the tensor on a background isolate.
  Future<YoloSegOutputs> runInferenceOnTensor(LetterboxResult letterboxResult) async {
    await initModel();

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      letterboxResult.tensor,
      [1, 3, 640, 640],
    );

    String inputName = 'images';
    if (_session != null && _session!.inputNames.isNotEmpty) {
      if (!_session!.inputNames.contains('images')) {
        inputName = _session!.inputNames.first;
      }
    }

    final runOptions = OrtRunOptions();
    final outputs = await _session!.runAsync(runOptions, {inputName: inputOrt});
    inputOrt.release();

    dynamic predRaw;
    dynamic protoRaw;

    if (outputs != null && outputs.isNotEmpty) {
      predRaw = outputs[0]?.value;
      if (outputs.length > 1) {
        protoRaw = outputs[1]?.value;
      }
    }

    return YoloSegOutputs(
      pred: predRaw,
      proto: protoRaw,
      letterbox: letterboxResult,
    );
  }

  void dispose() {
    _session?.release();
  }
}
