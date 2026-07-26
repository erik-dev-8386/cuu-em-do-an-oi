import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  // The heavy per-frame work now runs off the UI isolate (see InferenceWorker.processCameraFrame),
  // so this only needs to bound worst-case throughput/battery use, not protect UI smoothness.
  final FrameScheduler _scheduler = FrameScheduler(minFrameInterval: const Duration(milliseconds: 50));
  final PolygonSmoother _polygonSmoother = PolygonSmoother(alpha: 0.4, minIouThreshold: 0.25);

  bool _isCameraReady = false;
  String? _initError;
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
    setState(() {
      _initError = null;
    });
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
          // Extract plane bytes cheaply here (UI isolate); the actual
          // YUV/BGRA -> RGB conversion + rotation + letterbox + decode all
          // run off the UI isolate inside processCameraFrame.
          final rawFrame = FrameConverter.extractRawFrame(
            frame,
            rotationDegrees: camera.sensorOrientation,
          );

          if (rawFrame != null && mounted) {
            final result = await _worker.processCameraFrame(rawFrame);

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
      if (mounted) {
        setState(() {
          _initError = e.toString();
        });
      }
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
          ? Center(
              child: _initError != null
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Không khởi tạo được Camera AR',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _initError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _startARPipeline,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  : const Column(
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
                // Live Camera Preview + AR Overlay, sharing one letterboxed box so
                // polygon coordinates (in inference-frame space) always map 1:1
                // onto the preview regardless of device screen aspect ratio.
                Positioned.fill(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: (_frameWidth > 0 && _frameHeight > 0)
                          ? _frameWidth / _frameHeight
                          : _controller!.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_controller!),
                          if (_nailPolygons.isNotEmpty)
                            CustomPaint(
                              painter: NailPainter(
                                polygons: _nailPolygons,
                                nailColor: _selectedColor,
                                imageWidth: _frameWidth,
                                imageHeight: _frameHeight,
                              ),
                            ),
                        ],
                      ),
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
