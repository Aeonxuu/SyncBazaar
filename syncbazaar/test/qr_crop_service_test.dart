import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncbazaar/services/qr_crop_service.dart';
import 'package:zxing2/qrcode.dart';

/// Real QR codes end to end, not fixtures.
///
/// The point of the feature is that an automatic crop is safe to trust, and the
/// only evidence for that is a cropped image that still decodes to the same
/// text. So these build genuine codes, bury them in awkward pictures, crop, and
/// then read the result back.
void main() {
  const service = QrCropService();

  /// Paints a real QR for [content] at [moduleSize] pixels per module.
  img.Image qrImage(String content, {int moduleSize = 6}) {
    final code = Encoder.encode(content, ErrorCorrectionLevel.m);
    final matrix = code.matrix!;
    final image = img.Image(
      width: matrix.width * moduleSize,
      height: matrix.height * moduleSize,
    );
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) == 1) {
          img.fillRect(
            image,
            x1: x * moduleSize,
            y1: y * moduleSize,
            x2: x * moduleSize + moduleSize - 1,
            y2: y * moduleSize + moduleSize - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    return image;
  }

  /// Drops [qr] onto a larger canvas at an offset, the way a real upload has
  /// the code sitting somewhere inside a poster or screenshot.
  img.Image onCanvas(
    img.Image qr, {
    required int width,
    required int height,
    required int x,
    required int y,
    img.Color? background,
  }) {
    final canvas = img.Image(width: width, height: height);
    img.fill(canvas, color: background ?? img.ColorRgb8(235, 235, 240));
    img.compositeImage(canvas, qr, dstX: x, dstY: y);
    return canvas;
  }

  Uint8List png(img.Image image) => Uint8List.fromList(img.encodePng(image));

  /// Reads a QR back out of exported bytes, or null if it no longer scans.
  String? readBack(Uint8List bytes) {
    final image = img.decodeImage(bytes)!;
    try {
      final rgba = image.convert(numChannels: 4);
      final source = RGBLuminanceSource(
        image.width,
        image.height,
        rgba.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
      );
      return QRCodeReader()
          .decode(BinaryBitmap(GlobalHistogramBinarizer(source)))
          .text;
    } catch (_) {
      return null;
    }
  }

  /// Share of the image that is dark. A tight crop of a QR is roughly a third
  /// to a half dark; a crop that mostly caught the surrounding poster is barely
  /// dark at all, which is what makes this a usable measure of tightness.
  double darkFraction(Uint8List bytes) {
    final image = img.decodeImage(bytes)!;
    var dark = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (img.getLuminance(image.getPixel(x, y)) < 128) {
          dark++;
        }
      }
    }
    return dark / (image.width * image.height);
  }

  ({int width, int height}) sizeOf(Uint8List bytes) {
    final image = img.decodeImage(bytes)!;
    return (width: image.width, height: image.height);
  }

  group('cropping to the code', () {
    test('finds a QR sitting off-centre in a large picture', () async {
      const payload = 'https://gcash.example/pay/SVKICKZ';
      final source = png(
        onCanvas(
          qrImage(payload),
          width: 1400,
          height: 1800,
          x: 90,
          y: 1210,
        ),
      );

      final result = await service.cropToQr(source);

      expect(result.found, isTrue, reason: result.failureReason);
      // The whole promise: it still scans, and to the same thing.
      expect(readBack(result.bytes!), payload);
      expect(darkFraction(result.bytes!), greaterThan(0.15));
    });

    test('the export is square', () async {
      final source = png(
        onCanvas(qrImage('SQ'), width: 1200, height: 700, x: 800, y: 90),
      );

      final result = await service.cropToQr(source);

      final size = sizeOf(result.bytes!);
      expect(size.width, size.height);
    });

    test('throws away the surrounding picture', () async {
      // A code occupying a small part of a big canvas: if the crop were not
      // actually finding it, the export would still contain most of the poster.
      final qr = qrImage('TIGHT', moduleSize: 5);
      final source = png(
        onCanvas(qr, width: 2000, height: 2000, x: 1400, y: 120),
      );

      final result = await service.cropToQr(source);

      expect(result.found, isTrue, reason: result.failureReason);
      expect(readBack(result.bytes!), 'TIGHT');
      // The code covers about 3% of that canvas. If the crop had kept the
      // poster the export would be almost entirely pale background, so a
      // substantial dark share is evidence it actually cut to the code.
      expect(darkFraction(result.bytes!), greaterThan(0.15));
    });

    test('handles a QR that fills the whole picture', () async {
      const payload = 'FULL-BLEED';
      final result = await service.cropToQr(png(qrImage(payload)));

      expect(result.found, isTrue, reason: result.failureReason);
      expect(readBack(result.bytes!), payload);
    });

    test('survives a photo-sized source', () async {
      const payload = 'https://maya.example/pay/9917';
      final source = png(
        onCanvas(
          qrImage(payload, moduleSize: 12),
          width: 3000,
          height: 2200,
          x: 1900,
          y: 300,
        ),
      );

      final result = await service.cropToQr(source);

      expect(result.found, isTrue, reason: result.failureReason);
      expect(readBack(result.bytes!), payload);
    });
  });

  group('refusing what it cannot read', () {
    test('a picture with no QR in it is rejected', () async {
      final plain = img.Image(width: 900, height: 900);
      img.fill(plain, color: img.ColorRgb8(200, 120, 60));

      final result = await service.cropToQr(png(plain));

      expect(result.found, isFalse);
      expect(result.bytes, isNull);
      // The seller is told what to do next, not shown an error code.
      expect(result.failureReason, contains('QR'));
    });

    test('a file that is not an image is rejected', () async {
      final result = await service.cropToQr(
        Uint8List.fromList('this is not a picture'.codeUnits),
      );

      expect(result.found, isFalse);
      expect(result.failureReason, isNotNull);
    });
  });
}
