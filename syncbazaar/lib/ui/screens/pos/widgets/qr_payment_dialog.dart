import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../core/utils/formatters.dart';

/// Shows the customer the QR to scan, and takes the reference number back.
///
/// Sits between pressing Finish and the confirm-sale dialog, because that is
/// the real order of events at a stall: the customer scans, pays in their own
/// app, reads the reference out, and only then is there a sale to confirm.
/// Collecting the reference in the side panel beforehand asked the cashier to
/// type a number that did not exist yet.
///
/// Returns the reference on "Payment Received", or null if the cashier backed
/// out. Null must leave the sale uncommitted: a payment that did not arrive is
/// the ordinary reason for closing this.
Future<String?> showQrPaymentDialog({
  required BuildContext context,
  required String paymentMethod,
  required Uint8List qrBytes,
  required double amount,
  String? extraFieldLabel,
}) {
  return showDialog<String>(
    context: context,
    // The customer may be mid-scan; a stray tap outside must not close it.
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _QrPaymentDialog(
      paymentMethod: paymentMethod,
      qrBytes: qrBytes,
      amount: amount,
      extraFieldLabel: extraFieldLabel,
    ),
  );
}

class _QrPaymentDialog extends StatefulWidget {
  const _QrPaymentDialog({
    required this.paymentMethod,
    required this.qrBytes,
    required this.amount,
    this.extraFieldLabel,
  });

  final String paymentMethod;
  final Uint8List qrBytes;
  final double amount;
  final String? extraFieldLabel;

  @override
  State<_QrPaymentDialog> createState() => _QrPaymentDialogState();
}

class _QrPaymentDialogState extends State<_QrPaymentDialog> {
  final TextEditingController _reference = TextEditingController();

  bool get _needsReference =>
      widget.extraFieldLabel != null &&
      widget.extraFieldLabel!.trim().isNotEmpty;

  bool get _canConfirm =>
      !_needsReference || _reference.text.trim().isNotEmpty;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.97, end: 1),
        duration: AppMotion.entrance,
        curve: AppMotion.easeOut,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(theme),
              const Divider(height: 1, color: AppColors.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _qr(),
                      const SizedBox(height: 16),
                      _amount(theme),
                      if (_needsReference) ...[
                        const SizedBox(height: 16),
                        _referenceField(theme),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _footer(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              size: 19,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pay with ${widget.paymentMethod.toUpperCase()}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ask the customer to scan this code',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qr() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Always on white with a margin, whatever the app's surface is: a
          // scanner needs the quiet zone around the code to find its edges.
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Image.memory(
          widget.qrBytes,
          width: 236,
          height: 236,
          // contain, never cover: cropping a QR to fill a box can cut the
          // quiet zone and stop it scanning.
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 236,
            height: 236,
            child: Center(
              child: Text(
                'This QR could not be displayed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _amount(ThemeData theme) {
    return Row(
      children: [
        Text(
          'Amount due',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            formatPeso(widget.amount),
            textAlign: TextAlign.right,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _referenceField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.extraFieldLabel!,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _reference,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.inputFill,
            hintText: 'Input here',
            // Muted to the app's hint weight, matching every other field's
            // placeholder. At full strength a hint reads as text already
            // entered, which at a till invites the cashier to skip the box.
            hintStyle: const TextStyle(color: Colors.black38),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A disabled button has to say why it is disabled, rather than just
          // refusing to respond.
          if (!_canConfirm)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Enter the ${widget.extraFieldLabel!.toLowerCase()} to continue.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black45,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black54,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _canConfirm ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: 0.35,
                  ),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Payment Received'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirm() {
    if (!_canConfirm) {
      return;
    }
    // Empty string rather than null when no reference is required: null is
    // reserved for "the cashier cancelled", and the two must not be confused.
    Navigator.pop(context, _reference.text.trim());
  }
}
