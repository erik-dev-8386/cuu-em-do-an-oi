import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../camera/frame_converter.dart';
import '../camera/frame_scheduler.dart';
import '../isolate/inference_worker.dart';

import '../painter/nail_painter.dart';
import 'polygon_smoother.dart';

class ArCameraPage extends StatefulWidget {
  const ArCameraPage({super.key});

  @override
  State<ArCameraPage> createState() => _ArCameraPageState();
}

class _ArCameraPageState extends State<ArCameraPage> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIdx = 0;

  final InferenceWorker _worker = InferenceWorker();
  final FrameScheduler _scheduler = FrameScheduler(minFrameInterval: const Duration(milliseconds: 90));
  final PolygonSmoother _polygonSmoother = PolygonSmoother(alpha: 0.4, minIouThreshold: 0.25);

  bool _isCameraReady = false;
  List<List<Offset>> _nailPolygons = [];
  Color _selectedColor = const Color(0xFFFF4081);

  double _frameWidth = 0;
  double _frameHeight = 0;

  // Performance metrics
  int _fps = 0;
  int _frameCount = 0;
  Timer? _fpsTimer;
  Duration? _lastInferenceTime;

  @override
  void initState() {
    super.initState();
    _startARPipeline();

    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _fps = _frameCount;
          _frameCount = 0;
        });
      }
    });
  }

  Future<void> _startARPipeline() async {
    try {
      // 1. Await Worker & ONNX Initialization
      await _worker.init();

      // 2. Initialize Camera
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final camera = _cameras[_selectedCameraIdx];
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
      });

      // 3. Start Camera Image Stream with FrameScheduler
      await _controller!.startImageStream((CameraImage frame) async {
        if (!_scheduler.shouldProcessFrame() || !mounted) return;
        _scheduler.markBusy();

        try {
          // Fast YUV/BGRA -> RGB conversion
          var rgbImage = FrameConverter.convertCameraImageSync(frame);

          if (rgbImage != null && mounted) {
            // Handle Camera Sensor Rotation
            final sensorOrientation = camera.sensorOrientation;
            if (sensorOrientation == 90) {
              rgbImage = img.copyRotate(rgbImage, angle: 90);
            } else if (sensorOrientation == 270) {
              rgbImage = img.copyRotate(rgbImage, angle: 270);
            }

            // Run Inline YOLOv8-Seg Decoder Pipeline
            final result = await _worker.processFrame(rgbImage);

            if (mounted) {
              final smoothedPolygons = _polygonSmoother.smooth(result.polygons);

              setState(() {
                _nailPolygons = smoothedPolygons;
                _frameWidth = result.originalWidth.toDouble();
                _frameHeight = result.originalHeight.toDouble();
                _lastInferenceTime = result.inferenceTime;
                _frameCount++;
              });
            }
          }
        } catch (e) {
          debugPrint("⚠️ Lỗi suy luận Realtime AR frame: $e");
        } finally {
          _scheduler.markFree();
        }
      });
    } catch (e) {
      debugPrint("⚠️ Lỗi khởi tạo Pipeline Camera AR: $e");
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    _polygonSmoother.reset();
    _scheduler.reset();
    setState(() {
      _isCameraReady = false;
      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
    });

    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
    await _controller?.dispose();
    _startARPipeline();
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime AR Try-On (Live Camera)'),
        backgroundColor: const Color(0xFFFF4081),
        actions: [
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: _cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
      body: !_isCameraReady || _controller == null || !_controller!.value.isInitialized
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Đang khởi tạo Camera AR Stream & Ultralytics Pipeline...'),
                ],
              ),
            )
          : Stack(
              children: [
                // Live Camera Preview
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),

                // AR CustomPaint Overlay with CameraTransform Matrix Scaling
                if (_nailPolygons.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: NailPainter(
                        polygons: _nailPolygons,
                        nailColor: _selectedColor,
                        imageWidth: _frameWidth,
                        imageHeight: _frameHeight,
                      ),
                    ),
                  ),

                // Top Info Bar (FPS & Latency)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.speed, color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'FPS: $_fps | Latency: ${_lastInferenceTime?.inMilliseconds ?? 0}ms',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Color Selector
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildColorCircle(const Color(0xFFFF4081)),
                        _buildColorCircle(const Color(0xFFD50000)),
                        _buildColorCircle(const Color(0xFFAA00FF)),
                        _buildColorCircle(const Color(0xFF00B0FF)),
                        _buildColorCircle(const Color(0xFFFF6D00)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildColorCircle(Color color) {
    final isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () => setState(() => _selectedColor = color),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
      ),
    );
  }
}
