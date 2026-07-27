import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../isolate/inference_worker.dart';
import '../models/nail_variant.dart';
import '../services/nail_variant_api_service.dart';
import '../widgets/nail_try_on_overlay.dart';
import '../widgets/nail_variant_card.dart';

class NailSnapshotPage extends StatefulWidget {
  const NailSnapshotPage({super.key});

  @override
  State<NailSnapshotPage> createState() => _NailSnapshotPageState();
}

class _NailSnapshotPageState extends State<NailSnapshotPage> {
  File? _imageFile;
  bool _isProcessing = false;
  bool _isLoadingVariants = false;
  final InferenceWorker _worker = InferenceWorker();
  List<List<Offset>> _nailPolygons = [];
  final Map<int, NailVariant> _variantDetailsCache = {};

  late List<NailVariant> _variants;
  late NailVariant _selectedVariant;

  double _imgWidth = 0;
  double _imgHeight = 0;
  Duration? _lastInferenceDuration;

  @override
  void initState() {
    super.initState();
    _variants = NailVariantApiService.getPresetVariants();
    _selectedVariant = _variants.first;
    _loadVariantsFromApi();
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

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _isProcessing = true;
        _nailPolygons = [];
      });

      await _processSelectedImage();
    }
  }

  Future<void> _processSelectedImage() async {
    if (_imageFile == null) return;

    await _worker.init();
    final imageBytes = await _imageFile!.readAsBytes();
    final decodedImage = img.decodeImage(imageBytes);

    if (decodedImage != null) {
      setState(() {
        _imgWidth = decodedImage.width.toDouble();
        _imgHeight = decodedImage.height.toDouble();
      });

      final result = await _worker.processFrame(
        decodedImage,
        useAsyncPreprocess: true,
      );

      if (!mounted) return;

      setState(() {
        _nailPolygons = result.polygons;
        _lastInferenceDuration = result.inferenceTime;
        _isProcessing = false;
      });
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Snapshot Try-On (Thử Móng Tĩnh)'),
        backgroundColor: const Color(0xFFFF4081),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại danh sách từ API',
            onPressed: _loadVariantsFromApi,
          ),
          if (_lastInferenceDuration != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  '${_lastInferenceDuration!.inMilliseconds}ms',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_lastInferenceDuration != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  'Nails: ${_nailPolygons.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: _imageFile == null || _imgWidth == 0 || _imgHeight == 0
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.photo_camera_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Vui lòng chọn hoặc chụp ảnh bàn tay để bắt đầu thử móng',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      : FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: _imgWidth,
                            height: _imgHeight,
                            child: Stack(
                              children: [
                                Image.file(_imageFile!),
                                if (_nailPolygons.isNotEmpty)
                                  Positioned.fill(
                                    child: NailTryOnOverlay(
                                      polygons: _nailPolygons,
                                      variant: _selectedVariant,
                                    ),
                                  ),
                                if (_isProcessing)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
                // Selected Variant Info Overlay Card
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.white.withValues(alpha: 0.92),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _selectedVariant.primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _selectedVariant.primaryColor
                                      .withValues(alpha: 0.4),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
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
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Form: ${_selectedVariant.shapeName} • Bề mặt: ${_selectedVariant.surfaceName}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(_selectedVariant.price / 1000).toStringAsFixed(0)}.000đ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF4081),
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${_selectedVariant.duration} phút',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Horizontal Nail Variant Tray
          Container(
            height: 128,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    bottom: 2,
                    right: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'DANH SÁCH MẪU MÓNG (TỪ API BACKEND)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (_isLoadingVariants)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                Expanded(
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
              ],
            ),
          ),

          // Bottom Action Buttons
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.grey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Chụp ảnh',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4081),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(
                    Icons.photo_library,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Chọn ảnh',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAB47BC),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _onBookVariant(_selectedVariant),
                  icon: const Icon(
                    Icons.calendar_month,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Đặt lịch',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
