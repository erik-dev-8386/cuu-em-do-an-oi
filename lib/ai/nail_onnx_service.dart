import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'image_processor.dart';

class NailOnnxInferenceResult {
  final List<OrtValue?>? outputs;
  final LetterboxResult letterbox;

  NailOnnxInferenceResult({
    required this.outputs,
    required this.letterbox,
  });
}

class NailOnnxService {
  OrtSession? _session;

  Future<void> initModel() async {
    if (_session != null) return;

    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final rawBytes = await rootBundle.load('assets/models/best.onnx');
    final bytes = rawBytes.buffer.asUint8List();

    _session = OrtSession.fromBuffer(bytes, sessionOptions);
  }

  Future<NailOnnxInferenceResult> processImage(img.Image rawImage, {bool isSync = false}) async {
    await initModel();

    final letterboxResult = isSync
        ? ImageProcessor.imageToTensorSync(rawImage)
        : await ImageProcessor.imageToTensorAsync(rawImage);

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

    if (outputs != null && kDebugMode) {
      debugPrint("🔍 ONNX Input Names: ${_session?.inputNames}");
      debugPrint("🔍 ONNX Output Names: ${_session?.outputNames}");
      debugPrint("🔍 ONNX Output Count: ${outputs.length}");
    }

    return NailOnnxInferenceResult(
      outputs: outputs,
      letterbox: letterboxResult,
    );
  }

  void dispose() {
    _session?.release();
  }
}
