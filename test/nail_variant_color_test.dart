import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thanhdthaichink/models/nail_variant.dart';

void main() {
  NailVariant variantFromColorJson(String colorJson) {
    return NailVariant.fromJson({
      'nailVariantId': 1,
      'name': 'Test',
      'price': 100000,
      'colorJson': colorJson,
    });
  }

  test('parses backend solid colorJson', () {
    final variant = variantFromColorJson(
      '{"mode":"solid","color":"#ecdfe3","gradient":null}',
    );

    expect(variant.colorMode, NailColorMode.solid);
    expect(variant.primaryColor, const Color(0xFFECDFE3));
  });

  test('parses backend full nail gradient colorJson', () {
    final variant = variantFromColorJson(
      '{"mode":"gradient","color":"#FF4081","gradient":{"enabled":true,"type":"linear","stops":["#ff0000","#0a0000","#000000"],"stopCount":2}}',
    );

    expect(variant.colorMode, NailColorMode.gradient);
    expect(variant.gradientColors, const [
      Color(0xFFFF0000),
      Color(0xFF0A0000),
      Color(0xFF000000),
    ]);
  });

  test('parses backend per finger colorJson', () {
    final variant = variantFromColorJson(
      '{"mode":"perFinger","fingers":[{"fingerIndex":1,"color":"#FF0000","gradient":null},{"fingerIndex":2,"color":"#F5CBA7","gradient":null},{"fingerIndex":3,"color":"#FF4081","gradient":null},{"fingerIndex":4,"color":"#0000FF","gradient":null},{"fingerIndex":5,"color":"#0000FF","gradient":null}]}',
    );

    expect(variant.colorMode, NailColorMode.perFinger);
    expect(variant.colorForFingerIndex(1), const Color(0xFFFF0000));
    expect(variant.colorForFingerIndex(2), const Color(0xFFF5CBA7));
    expect(variant.colorForFingerIndex(3), const Color(0xFFFF4081));
    expect(variant.colorForFingerIndex(4), const Color(0xFF0000FF));
    expect(variant.colorForFingerIndex(5), const Color(0xFF0000FF));
  });

  test('parses nested backend shape image and surface shader param', () {
    final variant = NailVariant.fromApiJson({
      'nailVariantId': 7,
      'name': 'Christmas Snow Sparkle',
      'price': 600000,
      'duration': 45,
      'imageUrl': '/uploads/design.png',
      'colorJson': '{"mode":"solid","color":"#990000"}',
      'nailShape': {
        'nailShapeId': 2,
        'name': 'Oval',
        'imageUrl': '/uploads/oval-mask.png',
      },
      'nailSurface': {
        'nailSurfaceId': 3,
        'name': 'Glossy',
        'shaderParam': 'glitter',
      },
    }, baseUrl: 'http://10.0.2.2:5004');

    expect(variant.shapeImageUrl, 'http://10.0.2.2:5004/uploads/oval-mask.png');
    expect(variant.surfaceShaderParam, 'glitter');
    expect(variant.surfaceType, SurfaceType.glitter);
  });

  test('ignores swagger placeholder imageUrl values', () {
    final variant = NailVariant.fromApiJson({
      'nailVariantId': 8,
      'name': 'Placeholder',
      'price': 0,
      'colorJson': 'string',
      'nailShape': {'imageUrl': 'string'},
      'nailSurface': {'shaderParam': 'string'},
    });

    expect(variant.shapeImageUrl, isEmpty);
    expect(variant.imageUrl, isEmpty);
    expect(variant.surfaceType, SurfaceType.glossy);
  });
}
