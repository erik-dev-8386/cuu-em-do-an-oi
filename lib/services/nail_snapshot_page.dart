import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../widgets/nail_painter.dart';
import 'nail_onnx_service.dart';
import 'nail_post_processor.dart';



class NailSnapshotPage extends StatefulWidget {
  const NailSnapshotPage({Key? key}) : super(key: key);

  @override
  State<NailSnapshotPage> createState() => _NailSnapshotPageState();
}

class _NailSnapshotPageState extends State<NailSnapshotPage> {
  File? _imageFile;
  bool _isProcessing = false;
  final NailOnnxService _onnxService = NailOnnxService();
  List<List<Offset>> _nailPolygons = [];
  Color _selectedColor = const Color(0xFFFF4081);
  double _imgWidth = 0;
  double _imgHeight = 0;
  String _selectedModel = 'assets/models/nail_seg.onnx';

  @override
  void initState() {
    super.initState();
    _onnxService.initModel(modelPath: _selectedModel);
  }

  Future<void> _changeModel(String newModel) async {
    if (_selectedModel == newModel) return;
    setState(() {
      _selectedModel = newModel;
      _isProcessing = true;
    });
    await _onnxService.initModel(modelPath: newModel);
    if (_imageFile != null) {
      await _processSelectedImage();
    } else {
      setState(() => _isProcessing = false);
    }
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

    final imageBytes = await _imageFile!.readAsBytes();
    final decodedImage = img.decodeImage(imageBytes);

    if (decodedImage != null) {
      setState(() {
        _imgWidth = decodedImage.width.toDouble();
        _imgHeight = decodedImage.height.toDouble();
      });

      await _onnxService.initModel(modelPath: _selectedModel);
      final result = await _onnxService.processImage(decodedImage);

      if (!mounted) return;

      final polygons = NailPostProcessor.decodeOutputs(
        outputs: result.outputs,
        letterbox: result.letterbox,
      );

      setState(() {
        _nailPolygons = polygons;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nailify - AR Try-On'),
        backgroundColor: const Color(0xFFFF4081),
        actions: [
          DropdownButton<String>(
            value: _selectedModel,
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            items: const [
              DropdownMenuItem(
                value: 'assets/models/nail_seg.onnx',
                child: Text('nail_seg.onnx', style: TextStyle(color: Colors.black)),
              ),
              DropdownMenuItem(
                value: 'assets/models/best.onnx',
                child: Text('best.onnx', style: TextStyle(color: Colors.black)),
              ),
            ],
            onChanged: (val) {
              if (val != null) _changeModel(val);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _imageFile == null || _imgWidth == 0 || _imgHeight == 0
                  ? const Text('Vui lòng chọn hoặc chụp ảnh bàn tay')
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
                                child: CustomPaint(
                                  painter: NailPainter(
                                    polygons: _nailPolygons,
                                    nailColor: _selectedColor,
                                  ),
                                ),
                              ),
                            if (_isProcessing)
                              const Center(child: CircularProgressIndicator()),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: Colors.white,
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Chụp ảnh'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Chọn từ máy'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFAB47BC)),
                ),
              ],
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
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.black, width: 3) : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            )
          ],
        ),
      ),
    );
  }
}
