import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/remote/api_client.dart';
import '../../../../models/sale.dart' show ReferenceSource;
import '../../../../services/qr_payment_service.dart';

/// What the cashier ended up with.
class QrPaymentResult {
  const QrPaymentResult({required this.reference, required this.source});

  final String reference;
  final ReferenceSource source;
}

/// Takes payment by generated QR, watching for it to arrive.
///
/// Separate from [showQrPaymentDialog], which shows a stored code and takes a
/// typed reference. That one stays: it is the only thing that works with no
/// signal, and a bazaar with no signal is the ordinary case. This one is the
/// automatic path for when there is a connection.
///
/// Returns null if the cashier backed out without taking payment.
Future<QrPaymentResult?> showQrAutoPaymentDialog({
  required BuildContext context,
  required String paymentMethod,
  required double amount,
  required QrPaymentService service,
  String? extraFieldLabel,
  Uint8List? savedQrBytes,
}) {
  return showDialog<QrPaymentResult>(
    context: context,
    // The customer may be mid-scan; a stray tap outside must not close it.
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _QrAutoPaymentDialog(
      paymentMethod: paymentMethod,
      amount: amount,
      service: service,
      extraFieldLabel: extraFieldLabel,
      savedQrBytes: savedQrBytes,
    ),
  );
}

enum _Phase { preparing, waiting, paid, expired, failed, manual }

class _QrAutoPaymentDialog extends StatefulWidget {
  const _QrAutoPaymentDialog({
    required this.paymentMethod,
    required this.amount,
    required this.service,
    this.extraFieldLabel,
    this.savedQrBytes,
  });

  final String paymentMethod;
  final double amount;
  final QrPaymentService service;
  final String? extraFieldLabel;

  /// The stall's own code from Venues & Terms, shown in the manual fallback so
  /// a cashier with no signal has something for the customer to scan. Null when
  /// the method has none saved.
  final Uint8List? savedQrBytes;

  @override
  State<_QrAutoPaymentDialog> createState() => _QrAutoPaymentDialogState();
}

class _QrAutoPaymentDialogState extends State<_QrAutoPaymentDialog> {
  /// How often the server is asked whether the money has arrived.
  static const Duration _pollEvery = Duration(seconds: 3);

  final TextEditingController _manualReference = TextEditingController();

  _Phase _phase = _Phase.preparing;
  QrPaymentIntent? _intent;

  /// The decoded picture, when the gateway sent one inline. Decoded once here
  /// rather than in `build`, which runs again on every poll.
  Uint8List? _qrBytes;
  String? _message;

  /// True once the simulator link has been put on the clipboard, so the line
  /// can say so rather than leaving the cashier tapping it again.
  bool _testLinkCopied = false;

  /// True while the connection is down but the code is still up. The customer
  /// may already have paid, so this is a note rather than a failure.
  bool _reconnecting = false;

  Timer? _poll;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, not during it: this reads inherited widgets and
    // shows the preparing state before the work starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prepare();
      }
    });
  }

  @override
  void dispose() {
    // The one line that must not be forgotten. A timer left running keeps
    // asking the server about a payment nobody is waiting for, for the rest of
    // the shift.
    _poll?.cancel();
    _manualReference.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _phase = _Phase.preparing;
      _message = null;
      _reconnecting = false;
      // A new code has a new link, so a previous copy is stale.
      _testLinkCopied = false;
    });

    try {
      final intent = await widget.service.create(amount: widget.amount);
      if (!mounted) {
        return;
      }
      setState(() {
        _intent = intent;
        _qrBytes = intent.qrImageBytes;
        _phase = _Phase.waiting;
      });
      _startPolling();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _message = error.message;
      });
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) => _checkOnce());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _checkOnce() async {
    final intent = _intent;
    // Skipped while one is still in flight, so a slow answer cannot stack up
    // a queue of requests behind it.
    if (intent == null || _polling || !mounted) {
      return;
    }
    _polling = true;

    try {
      final update = await widget.service.statusOf(intent.intentId);
      if (!mounted) {
        return;
      }

      if (_reconnecting) {
        setState(() => _reconnecting = false);
      }

      switch (update.status) {
        case QrPaymentStatus.paid:
          _stopPolling();
          setState(() => _phase = _Phase.paid);
          final reference = update.referenceNumber ?? '';
          // Held briefly so the confirmation is seen rather than flashing past
          // on the way to the next screen.
          await Future<void>.delayed(const Duration(milliseconds: 900));
          if (mounted) {
            Navigator.pop(
              context,
              QrPaymentResult(
                reference: reference,
                source: ReferenceSource.automatic,
              ),
            );
          }
        case QrPaymentStatus.expired:
          _stopPolling();
          setState(() => _phase = _Phase.expired);
        case QrPaymentStatus.failed:
          _stopPolling();
          setState(() {
            _phase = _Phase.failed;
            _message = 'The payment did not go through.';
          });
        case QrPaymentStatus.pending:
          break;
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      // Keep the code up and keep trying. The customer may have paid already,
      // and declaring failure over one dropped request would lose that.
      if (error.isOffline) {
        setState(() => _reconnecting = true);
      } else {
        _stopPolling();
        setState(() {
          _phase = _Phase.failed;
          _message = error.message;
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _copyTestLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      setState(() => _testLinkCopied = true);
    }
  }

  void _switchToManual() {
    _stopPolling();
    setState(() => _phase = _Phase.manual);
  }

  void _confirmManual() {
    final reference = _manualReference.text.trim();
    if (widget.extraFieldLabel != null && reference.isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      QrPaymentResult(reference: reference, source: ReferenceSource.manual),
    );
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
                  child: _body(theme),
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
    final subtitle = switch (_phase) {
      _Phase.preparing => 'Preparing the code',
      _Phase.waiting =>
        _reconnecting
            ? 'Reconnecting. The code is still valid.'
            : 'Ask the customer to scan this code',
      _Phase.paid => 'Payment received',
      _Phase.expired => 'This code has expired',
      _Phase.failed => 'Payment could not be completed',
      _Phase.manual => 'Enter the reference from the customer',
    };

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
            child: Icon(
              _phase == _Phase.paid
                  ? Icons.check_circle_outline
                  : Icons.qr_code_2_rounded,
              size: 19,
              color: _phase == _Phase.paid
                  ? AppColors.success
                  : AppColors.primary,
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
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _reconnecting
                        ? AppColors.statusUpcoming
                        : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        switch (_phase) {
          _Phase.preparing => const SizedBox(
            height: 236,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          _Phase.waiting || _Phase.paid => _qr(),
          _Phase.expired || _Phase.failed => _problem(theme),
          _Phase.manual => _manualField(theme),
        },
        const SizedBox(height: 16),
        _amountRow(theme),
      ],
    );
  }

  Widget _qr() {
    final intent = _intent;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Always white with a margin: a scanner needs the quiet zone around
          // the code to find its edges.
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: SizedBox(
          width: 236,
          height: 236,
          child: intent == null ? const SizedBox.shrink() : _qrImage(intent),
        ),
      ),
    );
  }

  /// The code itself, fetched or decoded depending on how it was sent.
  ///
  /// `filterQuality: none` on both: a QR is hard pixel edges, and smoothing
  /// them is what makes a scanner hesitate.
  Widget _qrImage(QrPaymentIntent intent) {
    final bytes = _qrBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, _, _) => _qrUnavailable,
      );
    }
    return Image.network(
      intent.qrImage,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (_, _, _) => _qrUnavailable,
    );
  }

  static const Widget _qrUnavailable = Center(
    child: Text(
      'The code could not be loaded.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.black54),
    ),
  );

  Widget _problem(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _message ??
            'This code has expired. Create a new one, or enter the reference '
                'by hand.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.error,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _manualField(ThemeData theme) {
    final saved = widget.savedQrBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The stall's own code, when it has one. Falling back to typing a
        // reference with nothing on screen leaves the customer no way to pay
        // at all, which is the situation this fallback exists to rescue.
        if (saved != null) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: SizedBox(
                width: 150,
                height: 150,
                child: Image.memory(
                  saved,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          widget.extraFieldLabel ?? 'Reference number',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _manualReference,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirmManual(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.inputFill,
            hintText: 'Input here',
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

  Widget _amountRow(ThemeData theme) {
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

  Widget _footer(ThemeData theme) {
    final testUrl = _intent?.testUrl;
    final manualIsBlocked =
        widget.extraFieldLabel != null && _manualReference.text.trim().isEmpty;
    final showManual = _phase != _Phase.paid && _phase != _Phase.manual;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only in test mode, which is the only time the server sends a
          // simulator link. Without it there is no way to pay the code on
          // screen: the one thing a cashier must never do is scan it, because
          // PayMongo issues real QR codes in test mode and scanning one moves
          // real money.
          if (testUrl != null && _phase == _Phase.waiting)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => _copyTestLink(testUrl),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  // 14 vertical against a ~16 line box clears the 44px tap
                  // target this app holds checkout controls to.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _testLinkCopied ? Icons.check : Icons.copy_outlined,
                        size: 16,
                        color: AppColors.statusUpcoming,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _testLinkCopied
                              ? 'Link copied. Paste it in a browser to simulate payment.'
                              : 'Test mode. Do not scan. Tap to copy the simulator link.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.statusUpcoming,
                            fontWeight: FontWeight.w600,
                            decoration: _testLinkCopied
                                ? null
                                : TextDecoration.underline,
                            decorationColor: AppColors.statusUpcoming,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // The secondary ways out get their own line. Three controls across a
          // 420pt dialog overflowed, which pushed Cancel off the edge and left
          // the dialog with no way to close it.
          if (showManual || _phase == _Phase.expired)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                children: [
                  if (showManual)
                    TextButton(
                      onPressed: _switchToManual,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('Enter reference manually'),
                    ),
                  if (_phase == _Phase.expired)
                    TextButton(
                      onPressed: _prepare,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('New code'),
                    ),
                ],
              ),
            ),
          // Wrapped rather than a Row for the same reason as above: an
          // ElevatedButton renders far wider than its padding implies (see
          // section 10 of DESIGN_GUIDELINES.md), and "Payment Received" beside
          // "Cancel" overflowed a 420pt dialog by 42px.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (_phase != _Phase.paid)
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
              if (_phase == _Phase.manual)
                ElevatedButton(
                  onPressed: manualIsBlocked ? null : _confirmManual,
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
}
