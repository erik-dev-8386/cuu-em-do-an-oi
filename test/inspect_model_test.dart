import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';

void main() {
  test('Inspect best.onnx model structure', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final file = File('assets/models/best.onnx');
    expect(file.existsSync(), isTrue);

    final bytes = await file.readAsBytes();
    final session = OrtSession.fromBuffer(bytes, sessionOptions);

    debugPrint('\n================ ONNX MODEL INSPECTION ================');
    debugPrint('Input Names: ${session.inputNames}');
    debugPrint('Output Names: ${session.outputNames}');
    debugPrint('========================================================\n');

    expect(session.inputNames, contains('images'));
    expect(session.outputNames, containsAll(['output0', 'output1']));

    session.release();
  });
}
