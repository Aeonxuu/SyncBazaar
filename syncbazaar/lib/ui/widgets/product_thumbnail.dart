import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A product's image with a graceful placeholder fallback.
///
/// Shared by the POS grid card, the POS cart line, the master inventory table
/// and the product form, so every surface renders a product the same way —
/// same rounding logic, same "no photo yet" state, same decode behaviour.
///
/// Sources are tried in order of specificity:
/// 1. [imageBytes] — a photo the user picked on this device
/// 2. [imagePath] as an `http(s)` URL
/// 3. [imagePath] as a bundled asset
/// 4. the placeholder
///
/// Bytes come first because a locally picked photo is the most current thing
/// we know about the product, and because it's the only source that works
/// unchanged on web, desktop and mobile — see [Product.imageBytes].
class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.imagePath,
    this.imageBytes,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.iconSize = 28,
  });

  final String? imagePath;
  final Uint8List? imageBytes;
  final BorderRadius borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: borderRadius, child: _image(context));
  }

  Widget _image(BuildContext context) {
    final bytes = imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      // Sized to the box it's drawn in rather than the source resolution: a
      // phone photo is several thousand pixels wide, and decoding that at full
      // size for a 40px table thumbnail would cost megabytes of image cache
      // per row. LayoutBuilder gives the real target, so the same widget
      // decodes small in the table and large in the form's preview.
      return LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final target = constraints.maxWidth.isFinite
              ? (constraints.maxWidth * ratio).round()
              : null;
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: target,
            // A corrupt or unsupported file shouldn't take the row down with
            // it; fall back to the same placeholder as "no photo".
            errorBuilder: (_, __, ___) => _placeholder(),
          );
        },
      );
    }

    final path = imagePath;
    if (path != null && path.isNotEmpty) {
      final isRemote =
          path.startsWith('http://') || path.startsWith('https://');
      return isRemote
          ? Image.network(
              path,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : Image.asset(
              path,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _placeholder(),
            );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFF0F2F7),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: const Color(0xFF8B95A7),
        size: iconSize,
      ),
    );
  }
}
