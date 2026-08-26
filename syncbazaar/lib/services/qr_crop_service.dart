import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Finds the QR code inside an uploaded picture and cuts it out as a square.
///
/// A seller's QR arrives as whatever they had to hand: a screenshot of a wallet
/// app, a photo of a printed poster, a picture with the code small and off in
/// one corner. Showing that to a customer at the till is unusable, so the code
/// is located and cropped to on upload rather than asking the seller to crop it
/// themselves.
///
/// The guarantee that makes automatic cropping safe is [_verify]: every candidate
/// crop is decoded again before it is returned, and only a crop that still scans
/// is accepted. A trim that clipped a corner fails that check and is widened
/// instead of being handed back broken.
///
/// Pure Dart on both packages, so this behaves identically on the tablet, on
/// macOS and in a browser.
class QrCropService {
  const QrCropService();

  /// Long edge of the working copy. A phone photo is several thousand pixels
  /// wide and every pass here is O(pixels); detection does not improve above
  /// this, it just costs more. Matters most on web, which has no isolates and
  /// so does this work on the thread that draws the UI.
  static const int _workingMaxEdge = 1600;

  /// Side of the exported square. Comfortably sharp on a tablet held at arm's
  /// length by a customer, without storing a photo-sized blob per method.
  static const int _outputSize = 720;

  /// Fractions of the detected box added on each side, tried in order. The
  /// finder patterns zxing reports are the *centres* of the three corner
  /// squares, which sit inside the code's true edge, so the box always needs
  /// growing; how much depends on the version of the code, which is why this
  /// is a widening search verified by decode rather than a single guess.
  static const List<double> _paddingSteps = [0.18, 0.30, 0.45, 0.65];

  Future<QrCropResult> cropToQr(Uint8List source) async {
    final decoded = img.decodeImage(source);
    if (decoded == null) {
      return const QrCropResult.failed('That file is not an image we can read.');
    }

    final working = _fitWithin(decoded, _workingMaxEdge);
    // Ratio back to the original, so the final crop is taken at full resolution
    // even though detection ran on the smaller copy.
    final scale = decoded.width / working.width;

    final located = _locate(working);
    if (located == null) {
      return const QrCropResult.failed(
        "We couldn't find a QR code in this picture. "
        'Try a clearer, straight-on photo or a screenshot.',
      );
    }

    for (final padding in _paddingSteps) {
      final square = _squareAround(
        located,
        padding: padding,
        scale: scale,
        bounds: decoded,
      );
      final candidate = img.copyCrop(
        decoded,
        x: square.x,
        y: square.y,
        width: square.side,
        height: square.side,
      );
      if (_verify(candidate)) {
        final sized = img.copyResize(
          candidate,
          width: _outputSize,
          height: _outputSize,
        );
        return QrCropResult.cropped(
          Uint8List.fromList(img.encodePng(sized)),
        );
      }
    }

    // Located but never survived its own re-scan: the code is in there but too
    // damaged, blurred or angled to be relied on. Better refused than saved as
    // a QR that fails in front of a customer.
    return const QrCropResult.failed(
      'We found a QR code but it was too blurry to read reliably. '
      'Try a sharper picture.',
    );
  }

  /// Runs the detector over progressively more aggressive treatments, stopping
  /// at the first that reads.
  ///
  /// More than one pass because a refusal here is final for the seller: the
  /// upload is rejected outright, so it is worth working for a result before
  /// giving up. Ordered cheapest first.
  _Located? _locate(img.Image working) {
    final attempts = <img.Image>[
      working,
      img.adjustColor(img.grayscale(working.clone()), contrast: 1.6),
      // Helps when the code is small inside a large poster: the binarizer has
      // more pixels per module to work with.
      img.copyResize(
        working,
        width: working.width * 2,
        height: working.height * 2,
      ),
      // Light-on-dark codes, which the binarizer will not otherwise see.
      img.invert(working.clone()),
    ];

    for (var i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      final result = _decode(attempt);
      if (result == null) {
        continue;
      }
      // Points come back in the attempt's own pixel space; the upscaled pass
      // is twice the working copy, so bring it back before anyone uses it.
      final back = attempt.width / working.width;
      final points = result.resultPoints
          .whereType<ResultPoint>()
          .map((p) => math.Point<double>(p.x / back, p.y / back))
          .toList();
      if (points.length < 3) {
        continue;
      }
      return _Located(points: points, text: result.text);
    }
    return null;
  }

  /// Decodes one image, or null when there is nothing readable in it.
  ///
  /// zxing signals "no code here" by throwing, and that is an ordinary outcome
  /// on most passes rather than an error worth propagating.
  Result? _decode(img.Image image) {
    try {
      final rgba = image.convert(numChannels: 4);
      final source = RGBLuminanceSource(
        image.width,
        image.height,
        rgba.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
      );
      // A valueless flag: its presence is the instruction, so it takes no
      // argument. Worth the extra time here because a failed read rejects the
      // seller's upload outright.
      final hints = DecodeHints()..put(DecodeHintType.tryHarder);
      return QRCodeReader().decode(
        BinaryBitmap(GlobalHistogramBinarizer(source)),
        hints: hints,
      );
    } catch (_) {
      return null;
    }
  }

  bool _verify(img.Image candidate) => _decode(candidate) != null;

  /// The square to cut, in the original image's coordinates.
  ///
  /// Squared around the detected centre rather than by stretching the box, so
  /// the code keeps its proportions; a squashed QR does not scan.
  _Square _squareAround(
    _Located located, {
    required double padding,
    required double scale,
    required img.Image bounds,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final point in located.points) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }

    final centreX = (minX + maxX) / 2 * scale;
    final centreY = (minY + maxY) / 2 * scale;
    final widest = math.max(maxX - minX, maxY - minY) * scale;
    var side = widest * (1 + padding * 2);

    // Never larger than the picture it came from, and never degenerate.
    side = side.clamp(8.0, math.min(bounds.width, bounds.height).toDouble());

    final half = side / 2;
    final x = (centreX - half).clamp(0.0, bounds.width - side);
    final y = (centreY - half).clamp(0.0, bounds.height - side);

    return _Square(x: x.round(), y: y.round(), side: side.round());
  }

  /// Downscales so the long edge is at most [maxEdge], leaving smaller images
  /// untouched. Upscaling here would only invent pixels.
  img.Image _fitWithin(img.Image image, int maxEdge) {
    final longest = math.max(image.width, image.height);
    if (longest <= maxEdge) {
      return image;
    }
    final ratio = maxEdge / longest;
    return img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
    );
  }
}

/// Where the code was found, and what it says.
class _Located {
  const _Located({required this.points, required this.text});

  final List<math.Point<double>> points;
  final String text;
}

class _Square {
  const _Square({required this.x, required this.y, required this.side});

  final int x;
  final int y;
  final int side;
}

/// A cropped, re-verified QR, or the reason there isn't one.
class QrCropResult {
  const QrCropResult.cropped(Uint8List this.bytes)
    : found = true,
      failureReason = null;

  const QrCropResult.failed(String this.failureReason)
    : found = false,
      bytes = null;

  /// A square PNG containing only the code. Null when [found] is false.
  final Uint8List? bytes;

  final bool found;

  /// Phrased for the seller, not the developer: it is shown in the upload
  /// dialog and has to tell them what to do differently.
  final String? failureReason;
}
