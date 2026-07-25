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

    final rawBytes = await rootBundle.load('assets/models/best.onnx');
    final bytes = rawBytes.buffer.asUint8List();

    _session = OrtSession.fromBuffer(bytes, sessionOptions);
  }

  Future<YoloSegOutputs> runInference(img.Image rawImage) async {
    await initModel();

    final letterboxResult = LetterboxProcessor.process(rawImage);

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
