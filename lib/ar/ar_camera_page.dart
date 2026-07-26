import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '../ai/nail_tracker.dart';
import '../camera/frame_converter.dart';
import '../camera/frame_scheduler.dart';
import '../isolate/inference_worker.dart';

import '../painter/nail_painter.dart';

/// A 90/270 rotation (see `image` package's `copyRotate`) swaps width/height;
/// 0/180 don't. Mirrors the same convention `frame_prep.dart` uses.
Size _orientedSize(int sensorWidth, int sensorHeight, int rotationDegrees) {
  final bool swapped = rotationDegrees == 90 || rotationDegrees == 270;
  return swapped
      ? Size(sensorHeight.toDouble(), sensorWidth.toDouble())
      : Size(sensorWidth.toDouble(), sensorHeight.toDouble());
}

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
  // Confirmed on-device: running the YOLO pipeline back-to-back (previous
  // 50ms interval was effectively a no-op, since a ~3.6s cycle always beats
  // it) starves MediaPipe's hand tracking of CPU — landmarkStream updates
  // went from a steady ~200ms with YOLO paused to bursty 69-2263ms with YOLO
  // running continuously. This cooldown is measured from cycle *completion*
  // (see FrameScheduler.markFree), giving MediaPipe genuine idle CPU time
  // between YOLO cycles. Shape only needs refreshing every few seconds
  // anyway, so trading YOLO frequency for tracking smoothness is a clear win.
  final FrameScheduler _scheduler = FrameScheduler(minFrameInterval: const Duration(milliseconds: 2500));

  // Nail *shape* comes from the slow YOLO pipeline below; nail *position*
  // comes from MediaPipe hand landmarks, which update every camera frame —
  // NailTracker re-projects the last known shape onto the current live
  // fingertip position/orientation, so the overlay tracks the hand in real
  // time even though the underlying segmentation only refreshes every few
  // seconds. See docs/adr/0003-mediapipe-hand-tracking-for-live-position.md.
  final NailTracker _nailTracker = NailTracker();
  HandLandmarkerPlugin? _handLandmarker;
  StreamSubscription<List<Hand>>? _handLandmarkSub;
  List<Hand> _lastHands = [];

  int _sensorWidth = 0;
  int _sensorHeight = 0;
  int _rotationDegrees = 0;

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

      _handLandmarker ??= HandLandmarkerPlugin.create(
        // Root cause of the earlier laggy tracking wasn't the delegate choice
        // — it was the YOLO pipeline running back-to-back and starving this
        // of CPU (see _scheduler above). CPU delegate + a single hand (all we
        // need for nail try-on) measured a steady ~200ms landmarkStream
        // interval once that contention was fixed.
        numHands: 1,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.cpu,
      );
      // This fires on (roughly) every camera frame — much faster than the
      // YOLO pipeline — and is what actually drives the live-tracking feel:
      // re-project whatever nail shapes NailTracker currently knows about
      // onto the hand's current position/orientation.
      _handLandmarkSub ??= _handLandmarker!.landmarkStream.listen((hands) {
        if (!mounted || _sensorWidth == 0) return;
        _lastHands = hands;
        final rendered = _nailTracker.render(
          hands: hands,
          sensorWidth: _sensorWidth,
          sensorHeight: _sensorHeight,
          rotationDegrees: _rotationDegrees,
        );
        setState(() {
          _nailPolygons = rendered;
          _frameCount++;
        });
      });

      setState(() {
        _isCameraReady = true;
      });

      // 3. Start Camera Image Stream with FrameScheduler
      await _controller!.startImageStream((CameraImage frame) async {
        _sensorWidth = frame.width;
        _sensorHeight = frame.height;
        _rotationDegrees = camera.sensorOrientation;
        final oriented = _orientedSize(frame.width, frame.height, _rotationDegrees);
        if (_frameWidth != oriented.width || _frameHeight != oriented.height) {
          setState(() {
            _frameWidth = oriented.width;
            _frameHeight = oriented.height;
          });
        }

        // Fire-and-forget: runs on its own native background thread, doesn't
        // compete with the (much slower) nail-detection pipeline below, and
        // is what keeps the overlay tracking the hand live (see above).
        _handLandmarker?.processFrame(frame, camera.sensorOrientation);

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
              _nailTracker.updateFromDetections(
                yoloPolygons: result.polygons,
                hands: _lastHands,
                sensorWidth: frame.width,
                sensorHeight: frame.height,
                rotationDegrees: camera.sensorOrientation,
                maxMatchDistance: 0.18 *
                    (result.originalWidth < result.originalHeight ? result.originalWidth : result.originalHeight),
              );

              setState(() {
                _lastInferenceTime = result.inferenceTime;
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
    _nailTracker.reset();
    _scheduler.reset();
    _lastHands = [];
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
    _handLandmarkSub?.cancel();
    _handLandmarker?.dispose();
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
