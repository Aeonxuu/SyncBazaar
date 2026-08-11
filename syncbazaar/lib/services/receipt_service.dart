import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import '../models/receipt.dart';
import '../ui/screens/pos/widgets/receipt_document.dart';
import 'receipt_saver.dart';

/// Renders a receipt to a PNG and saves it.
///
/// The one service in this app that imports Flutter. It has to: the receipt is
/// a widget, and capturing a widget needs a [BuildContext] to inherit the theme
/// from. Everything decidable without Flutter — what goes on the receipt, and
/// what each payment method contributes — lives in `receipt_payment_sections`
/// and `models/receipt.dart` instead, so only the pixels are in here.
///
/// Stateless, so it is constructed where it is used rather than wired through
/// `app.dart`, following `const DashboardAnalyticsService()`.
class ReceiptService {
  const ReceiptService({this.saver = const ReceiptSaver()});

  final ReceiptSaver saver;

  /// Conservative floor for GPU max texture size. Exceeding it is the likely
  /// cause of Impeller returning truncated captures for long widgets
  /// (screenshot#207), so the pixel ratio is scaled to stay inside it — a
  /// slightly softer receipt beats one missing its last five items.
  static const double _maxTextureDimension = 4096;

  /// Enough to look sharp on a tablet without inflating a long receipt past
  /// the texture limit.
  static const double _preferredPixelRatio = 3;

  /// Renders [data], saves it, and returns where it landed.
  ///
  /// Throws if either step fails; the caller surfaces that in the print dialog.
  Future<String> printReceipt(
    ReceiptData data, {
    required BuildContext context,
  }) async {
    // No font loading to wait on: Inter ships with the app (see AppTheme
    // .fontFamily), so it is available from the first frame and the capture
    // cannot bake in a fallback typeface.
    //
    // This used to `await GoogleFonts.pendingFonts()`. On an offline tablet
    // that call throws on the DNS lookup, and because it ran before anything
    // was drawn it failed the whole receipt — a sale completed but printed
    // nothing. A till must not depend on the network to hand over a receipt.
    if (!context.mounted) {
      throw StateError('Receipt context was disposed before rendering.');
    }

    final bytes = await ScreenshotController().captureFromLongWidget(
      ReceiptDocument(data: data),
      // Passing context makes the package wrap the document in the app's
      // InheritedTheme and MediaQuery, so AppTheme and Inter carry into the
      // detached render tree. It also wraps it in a *transparent* Material,
      // which is why ReceiptDocument paints its own white background.
      context: context,
      pixelRatio: _pixelRatioFor(data),
      // Width pinned, height free: this is what makes the PNG grow with the
      // basket instead of being cropped to a viewport.
      constraints: const BoxConstraints(
        minWidth: ReceiptDocument.width,
        maxWidth: ReceiptDocument.width,
        maxHeight: double.infinity,
      ),
      // The package delays *after* each capture to let a dirty tree settle.
      // The default second is dead time on a static document.
      delay: const Duration(milliseconds: 120),
    );

    return saver.save(bytes, data.fileName);
  }

  /// Picks the largest pixel ratio that keeps both dimensions under the texture
  /// limit, from an estimate of the rendered height.
  ///
  /// Estimated rather than measured because the real height is only known
  /// inside the capture, by which point the ratio is already fixed.
  ///
  /// The floor of 1.0 is a deliberate stop: below it the 10.5pt body text
  /// stops being readable, and an illegible receipt is no better than a
  /// truncated one. That caps what this can rescue at roughly **69 line
  /// items** — past there the document exceeds the texture limit at 1:1 and
  /// would need to be captured in tiles and stitched. A single bazaar
  /// transaction with 70 distinct products is far outside what a stall till
  /// does, so that is left unbuilt rather than built untested.
  static double _pixelRatioFor(ReceiptData data) {
    final estimatedHeight = ReceiptDocument.estimateHeight(data);
    final longestSide = math.max(ReceiptDocument.width, estimatedHeight);
    final ceiling = _maxTextureDimension / longestSide;
    return ceiling.clamp(1.0, _preferredPixelRatio).toDouble();
  }
}
