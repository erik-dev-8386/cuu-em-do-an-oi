import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../camera/frame_converter.dart';
import '../camera/frame_scheduler.dart';
import '../isolate/inference_worker.dart';

import '../models/nail_variant.dart';
import '../services/nail_variant_api_service.dart';
import '../widgets/nail_try_on_overlay.dart';
import '../widgets/nail_variant_card.dart';
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
  final FrameScheduler _scheduler = FrameScheduler(
    minFrameInterval: const Duration(milliseconds: 90),
  );
  final PolygonSmoother _polygonSmoother = PolygonSmoother(
    alpha: 0.4,
    minIouThreshold: 0.25,
  );

  bool _isCameraReady = false;
  bool _isLoadingVariants = false;
  List<List<Offset>> _nailPolygons = [];
  final Map<int, NailVariant> _variantDetailsCache = {};

  late List<NailVariant> _variants;
  late NailVariant _selectedVariant;

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
    _variants = NailVariantApiService.getPresetVariants();
    _selectedVariant = _variants.first;
    _startARPipeline();
    _loadVariantsFromApi();

    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _fps = _frameCount;
          _frameCount = 0;
        });
      }
    });
  }

  Future<void> _loadVariantsFromApi() async {
    setState(() => _isLoadingVariants = true);
    final fetched = await NailVariantApiService.fetchNailVariants();
    if (mounted && fetched.isNotEmpty) {
      setState(() {
        _variants = fetched;
        if (!_variants.any(
          (item) => item.nailVariantId == _selectedVariant.nailVariantId,
        )) {
          _selectedVariant = fetched.first;
        }
        _isLoadingVariants = false;
      });
    }
  }

  Future<void> _startARPipeline() async {
    try {
      await _worker.init();

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

      await _controller!.startImageStream((CameraImage frame) async {
        if (!_scheduler.shouldProcessFrame() || !mounted) return;
        _scheduler.markBusy();

        try {
          var rgbImage = FrameConverter.convertCameraImageSync(frame);

          if (rgbImage != null && mounted) {
            final sensorOrientation = camera.sensorOrientation;
            if (sensorOrientation == 90) {
              rgbImage = img.copyRotate(rgbImage, angle: 90);
            } else if (sensorOrientation == 270) {
              rgbImage = img.copyRotate(rgbImage, angle: 270);
            }

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

  void _onBookVariant(NailVariant variant) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFFF4081),
        content: Text(
          'Đã chọn "${variant.name}" (${(variant.price / 1000).toStringAsFixed(0)}k đ) để đặt lịch!',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        action: SnackBarAction(
          label: 'ĐẶT LỊCH NGAY',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _selectVariant(NailVariant variant) async {
    setState(() {
      _selectedVariant = variant;
    });

    final cached = _variantDetailsCache[variant.nailVariantId];
    if (cached != null) {
      if (mounted && _selectedVariant.nailVariantId == cached.nailVariantId) {
        setState(() => _selectedVariant = cached);
      }
      return;
    }

    final detailed = await NailVariantApiService.fetchNailVariantById(
      variant.nailVariantId,
    );
    if (detailed == null || !mounted) return;

    _variantDetailsCache[detailed.nailVariantId] = detailed;
    final index = _variants.indexWhere(
      (item) => item.nailVariantId == detailed.nailVariantId,
    );

    setState(() {
      if (index >= 0) {
        _variants[index] = detailed;
      }
      if (_selectedVariant.nailVariantId == detailed.nailVariantId) {
        _selectedVariant = detailed;
      }
    });
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
        title: const Text('Realtime AR Try-On (Camera Động)'),
        backgroundColor: const Color(0xFFFF4081),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại danh sách từ API',
            onPressed: _loadVariantsFromApi,
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: _cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
      body:
          !_isCameraReady ||
              _controller == null ||
              !_controller!.value.isInitialized
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Đang khởi tạo Camera AR Stream & Pipeline AI...'),
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

                // AR CustomPaint Overlay
                if (_nailPolygons.isNotEmpty)
                  Positioned.fill(
                    child: NailTryOnOverlay(
                      polygons: _nailPolygons,
                      variant: _selectedVariant,
                      imageWidth: _frameWidth,
                      imageHeight: _frameHeight,
                    ),
                  ),

                // Top Info Overlay
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.speed,
                              color: Colors.greenAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'FPS: $_fps | ${_lastInferenceTime?.inMilliseconds ?? 0}ms | Nails: ${_nailPolygons.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_isLoadingVariants) ...[
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _onBookVariant(_selectedVariant),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4081),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.pink.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_month,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Đặt lịch ngay',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Selected Variant Floating Card
                Positioned(
                  bottom: 135,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _selectedVariant.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedVariant.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Form: ${_selectedVariant.shapeName} • ${_selectedVariant.surfaceName}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(_selectedVariant.price / 1000).toStringAsFixed(0)}k đ',
                          style: const TextStyle(
                            color: Color(0xFFFF80AB),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Nail Variant Tray
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 128,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    color: Colors.black.withValues(alpha: 0.85),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _variants.length,
                      itemBuilder: (context, index) {
                        final item = _variants[index];
                        return NailVariantCard(
                          variant: item,
                          isSelected:
                              item.nailVariantId ==
                              _selectedVariant.nailVariantId,
                          onTap: () => _selectVariant(item),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
