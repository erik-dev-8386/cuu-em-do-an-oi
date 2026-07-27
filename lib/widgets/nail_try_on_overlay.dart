import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/nail_variant.dart';
import '../painter/nail_painter.dart';

class NailTryOnOverlay extends StatefulWidget {
  final List<List<Offset>> polygons;
  final NailVariant variant;
  final double? imageWidth;
  final double? imageHeight;

  const NailTryOnOverlay({
    super.key,
    required this.polygons,
    required this.variant,
    this.imageWidth,
    this.imageHeight,
  });

  @override
  State<NailTryOnOverlay> createState() => _NailTryOnOverlayState();
}

class _NailTryOnOverlayState extends State<NailTryOnOverlay> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  ui.Image? _shapeTexture;
  String _loadedShapeUrl = '';

  @override
  void initState() {
    super.initState();
    _loadShapeTexture();
  }

  @override
  void didUpdateWidget(covariant NailTryOnOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant.shapeImageUrl != widget.variant.shapeImageUrl) {
      _loadShapeTexture();
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  void _loadShapeTexture() {
    _removeImageListener();

    final shapeUrl = widget.variant.shapeImageUrl;
    _loadedShapeUrl = shapeUrl;
    if (shapeUrl.isEmpty) {
      setState(() => _shapeTexture = null);
      return;
    }

    final provider = NetworkImage(shapeUrl);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted || _loadedShapeUrl != shapeUrl) return;
        setState(() => _shapeTexture = info.image);
      },
      onError: (_, _) {
        if (!mounted || _loadedShapeUrl != shapeUrl) return;
        setState(() => _shapeTexture = null);
      },
    );

    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: NailPainter(
        polygons: widget.polygons,
        variant: widget.variant,
        imageWidth: widget.imageWidth,
        imageHeight: widget.imageHeight,
        shapeTexture: _shapeTexture,
      ),
    );
  }
}
