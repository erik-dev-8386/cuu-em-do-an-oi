import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:thanhdthaichink/config/model_assets.dart';

void main() {
  test('Inspect nail segmentation ONNX model structure', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final file = File(ModelAssets.nailSegOnnx);
    expect(file.existsSync(), isTrue);

    final bytes = await file.readAsBytes();
    final session = OrtSession.fromBuffer(bytes, sessionOptions);

    debugPrint('\n================ ONNX MODEL INSPECTION ================');
    debugPrint('Input Names: ${session.inputNames}');
    debugPrint('Output Names: ${session.outputNames}');
    debugPrint('========================================================\n');

    expect(session.inputNames, isNotEmpty);
    expect(session.outputNames, isNotEmpty);

    session.release();
  });

  test('TFLite nail segmentation asset is bundled for mobile runtime', () {
    final file = File(ModelAssets.nailSegTflite);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));
  });
}
