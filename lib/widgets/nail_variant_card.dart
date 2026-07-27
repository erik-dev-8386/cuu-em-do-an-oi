import 'package:flutter/material.dart';
import '../models/nail_variant.dart';

class NailVariantCard extends StatelessWidget {
  final NailVariant variant;
  final bool isSelected;
  final VoidCallback onTap;

  const NailVariantCard({
    super.key,
    required this.variant,
    required this.isSelected,
    required this.onTap,
  });

  bool get isFromApi => variant.isRemote;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 98,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.pink.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF4081) : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFFFF4081).withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isSelected ? 6 : 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 2),
                // Image Thumbnail or Color & Surface Badge
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _thumbnailGradient == null
                            ? variant.primaryColor
                            : null,
                        gradient: _thumbnailGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: variant.primaryColor.withValues(alpha: 0.4),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _thumbnailUrl.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                _thumbnailUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(color: variant.primaryColor),
                              ),
                            )
                          : null,
                    ),
                    if (_thumbnailUrl.isEmpty) ...[
                      if (variant.surfaceType == SurfaceType.matte)
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        )
                      else if (variant.surfaceType == SurfaceType.glitter)
                        const Icon(Icons.star, color: Colors.white70, size: 18)
                      else if (variant.surfaceType == SurfaceType.catEye)
                        Transform.rotate(
                          angle: 0.7,
                          child: Container(
                            width: 30,
                            height: 3.5,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        )
                      else if (variant.surfaceType == SurfaceType.chrome)
                        const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 18,
                        )
                      else if (variant.surfaceType == SurfaceType.holographic)
                        const Icon(
                          Icons.wb_sunny_outlined,
                          color: Colors.white,
                          size: 18,
                        )
                      else if (variant.surfaceType == SurfaceType.pearl)
                        const Icon(Icons.blur_on, color: Colors.white, size: 18)
                      else if (variant.surfaceType == SurfaceType.satin)
                        const Icon(Icons.waves, color: Colors.white, size: 18),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Variant name
                Text(
                  variant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? const Color(0xFFFF4081)
                        : Colors.black87,
                  ),
                ),
                const SizedBox(height: 1),
                // Price Tag
                Text(
                  '${(variant.price / 1000).toStringAsFixed(0)}k đ',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            // API Indicator Badge
            if (isFromApi)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'API',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Gradient? get _thumbnailGradient {
    if (variant.colorMode == NailColorMode.gradient &&
        variant.gradientColors.length > 1) {
      return LinearGradient(
        colors: variant.gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    if (variant.colorMode == NailColorMode.perFinger &&
        variant.perFingerColors.length > 1) {
      return SweepGradient(colors: variant.perFingerColors.values.toList());
    }

    return null;
  }

  String get _thumbnailUrl {
    if (variant.imageUrl.isNotEmpty) return variant.imageUrl;
    return variant.shapeImageUrl;
  }
}
