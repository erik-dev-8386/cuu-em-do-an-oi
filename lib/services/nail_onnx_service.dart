import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'image_processor.dart';
import 'package:image/image.dart' as img;

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
  String _currentModelPath = '';

  Future<void> initModel({String modelPath = 'assets/models/nail_seg.onnx'}) async {
    if (_session != null && _currentModelPath == modelPath) return;

    _session?.release();
    _session = null;
    _currentModelPath = modelPath;

    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final rawBytes = await rootBundle.load(modelPath);
    final bytes = rawBytes.buffer.asUint8List();

    _session = OrtSession.fromBuffer(bytes, sessionOptions);
    print("🎉 NẠP MODEL ONNX ($modelPath) THÀNH CÔNG!");
  }

  Future<NailOnnxInferenceResult> processImage(img.Image rawImage) async {
    await initModel();

    int targetSize = 640;
    if (_currentModelPath.contains('nail_seg.onnx')) {
      targetSize = 416;
    }

    final letterboxResult = await ImageProcessor.imageToTensorAsync(
      rawImage,
      targetSize: targetSize,
    );

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      letterboxResult.tensor,
      [1, 3, targetSize, targetSize],
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

    if (outputs != null) {
      print("🔍 ONNX Input Names: ${_session?.inputNames}");
      print("🔍 ONNX Output Names: ${_session?.outputNames}");
      print("🔍 ONNX Output Count: ${outputs.length}");
      for (int i = 0; i < outputs.length; i++) {
        final val = outputs[i]?.value;
        print("  🔹 Output $i runtimeType: ${val.runtimeType}");
      }
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
