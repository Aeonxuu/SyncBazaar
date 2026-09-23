import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' show HttpExceptionWithStatus;

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
    this.fit = BoxFit.cover,
    this.backgroundColor = const Color(0xFFF0F2F7),
  });

  final String? imagePath;
  final Uint8List? imageBytes;
  final BorderRadius borderRadius;
  final double iconSize;

  /// [BoxFit.cover] (the default) fills the box and crops whatever doesn't
  /// fit — right for a small, icon-sized thumbnail (the table row, the cart
  /// line), where there's no room to spare and no expectation of seeing the
  /// whole product. [BoxFit.contain] shows the entire photo instead,
  /// letterboxed with [backgroundColor] — for a tile large enough that a
  /// crop actually loses something, and where the box's own shape (a fixed
  /// square, say) won't usually match the photo's.
  final BoxFit fit;

  /// Fills whatever [fit] leaves uncovered. Invisible under [BoxFit.cover],
  /// since that never leaves a gap.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: ColoredBox(color: backgroundColor, child: _image(context)),
    );
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
            fit: fit,
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
          ? _RetryingNetworkImage(url: path, fit: fit, placeholder: _placeholder)
          : Image.asset(
              path,
              fit: fit,
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

/// Loads a remote product photo through a disk-backed cache, retrying a
/// couple of times before giving up on a fresh load.
///
/// Bazaar wifi is flaky by nature, and a cold app start can fire off enough
/// parallel image requests to make Android's DNS resolver choke on a handful
/// of them even though the host is reachable a moment later. Retrying clears
/// most of those. An [HttpExceptionWithStatus] means the server actually
/// answered (a 404, most likely) rather than the connection failing, so that
/// case is not retried -- retrying wouldn't fix a file that genuinely isn't
/// there.
///
/// The cache is what makes a photo survive offline: `cached_network_image`
/// writes the decoded file to disk the first time it loads successfully, and
/// serves that copy on every later request for the same URL regardless of
/// connectivity -- unlike `Image.network`, which only ever lived in memory
/// and vanished on app restart or memory pressure.
class _RetryingNetworkImage extends StatefulWidget {
  const _RetryingNetworkImage({
    required this.url,
    required this.fit,
    required this.placeholder,
  });

  final String url;
  final BoxFit fit;
  final Widget Function() placeholder;

  @override
  State<_RetryingNetworkImage> createState() => _RetryingNetworkImageState();
}

class _RetryingNetworkImageState extends State<_RetryingNetworkImage> {
  static const _retryDelays = [Duration(milliseconds: 500), Duration(milliseconds: 1500)];

  int _attempt = 0;

  void _onError(Object error) {
    debugPrint(
      'ProductThumbnail failed to load ${widget.url} (attempt $_attempt): $error',
    );

    final isConnectionFailure = error is! HttpExceptionWithStatus;
    if (isConnectionFailure && _attempt < _retryDelays.length) {
      final delay = _retryDelays[_attempt];
      Future.delayed(delay, () {
        if (mounted) setState(() => _attempt++);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: widget.url,
      // Forces Flutter to treat each retry as a brand new image request
      // rather than reusing the failed one -- image_url never changes, so
      // without this the widget diffing sees "same provider" and never
      // re-resolves the stream.
      key: ValueKey(_attempt),
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => widget.placeholder(),
      errorWidget: (_, __, ___) => widget.placeholder(),
      errorListener: _onError,
    );
  }
}
