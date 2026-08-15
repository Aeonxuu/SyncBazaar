import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../models/receipt.dart';
import '../../../../services/receipt_service.dart';

/// Prints the receipt, then says so.
///
/// The sale is already committed by the time this opens, so the dialog can
/// never block or undo it: a failure here costs the customer a copy, not the
/// transaction. That is why the failure state offers "Try again" against the
/// same [ReceiptData] rather than anything resembling a rollback.
///
/// The wait is deliberately floored at [_minimumPrintDuration]. Rendering and
/// saving a PNG takes well under a second, and a confirmation that appears
/// instantly reads as a button that did nothing — where a pause reads as a
/// printer. The floor runs concurrently with the real work, so it sets the
/// minimum, never adds to a slow save.
Future<void> showReceiptPrintDialog({
  required BuildContext context,
  required ReceiptData data,
  ReceiptService service = const ReceiptService(),
}) {
  return showDialog<void>(
    context: context,
    // Not dismissible: the printing phase has no safe interruption point, and
    // the done phase has a single obvious button.
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _ReceiptPrintDialog(data: data, service: service),
  );
}

const Duration _minimumPrintDuration = Duration(milliseconds: 2400);

enum _PrintPhase { printing, done, failed }

class _ReceiptPrintDialog extends StatefulWidget {
  const _ReceiptPrintDialog({required this.data, required this.service});

  final ReceiptData data;
  final ReceiptService service;

  @override
  State<_ReceiptPrintDialog> createState() => _ReceiptPrintDialogState();
}

class _ReceiptPrintDialogState extends State<_ReceiptPrintDialog> {
  _PrintPhase _phase = _PrintPhase.printing;
  String _destination = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame, not started here. Capturing the
    // receipt reads MediaQuery off this context, and reading an inherited
    // widget before initState has finished is an error — it threw on device
    // and took the print down with it.
    //
    // It survived earlier only by accident: the old `await
    // GoogleFonts.pendingFonts()` yielded before the capture, so the read
    // landed after initState had returned. Removing that download exposed a
    // fault that was always here. Waiting for the frame also means the
    // "Printing receipt…" state is on screen before the heavy work starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _print();
    });
  }

  Future<void> _print() async {
    setState(() => _phase = _PrintPhase.printing);

    try {
      final results = await Future.wait([
        widget.service.printReceipt(widget.data, context: context),
        Future<String>.delayed(_minimumPrintDuration, () => ''),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _destination = results.first;
        _phase = _PrintPhase.done;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _phase = _PrintPhase.failed;
      });
    }
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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusBadge(phase: _phase),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            switch (_phase) {
                              _PrintPhase.printing => 'Printing receipt…',
                              _PrintPhase.done => 'Receipt printed',
                              _PrintPhase.failed => 'Couldn\'t print receipt',
                            },
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            switch (_phase) {
                              _PrintPhase.printing =>
                                'Receipt ${widget.data.receiptNo}',
                              _PrintPhase.done => _destination,
                              _PrintPhase.failed =>
                                'The sale was still '
                                    'recorded.',
                            },
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.black45,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_phase == _PrintPhase.failed) ...[
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Text(
                    _error,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _footerActions(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _footerActions() {
    switch (_phase) {
      case _PrintPhase.printing:
        // No action while the printer is "running": there is nothing useful to
        // press, and an enabled button here would invite a second capture.
        return [
          Text(
            'Please wait…',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black38),
          ),
        ];
      case _PrintPhase.done:
        return [
          ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            style: _primaryButtonStyle,
            child: const Text('Done'),
          ),
        ];
      case _PrintPhase.failed:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('Close'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            autofocus: true,
            onPressed: _print,
            style: _primaryButtonStyle,
            child: const Text('Try again'),
          ),
        ];
    }
  }

  static final ButtonStyle _primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

/// The 36×36 header chip, carrying the phase as both icon and colour.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.phase});

  final _PrintPhase phase;

  @override
  Widget build(BuildContext context) {
    final color = switch (phase) {
      _PrintPhase.printing => AppColors.primary,
      _PrintPhase.done => AppColors.success,
      _PrintPhase.failed => AppColors.error,
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: switch (phase) {
          _PrintPhase.printing => SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          _PrintPhase.done => Icon(
            Icons.check_circle_outline,
            size: 19,
            color: color,
          ),
          _PrintPhase.failed => Icon(
            Icons.error_outline,
            size: 19,
            color: color,
          ),
        },
      ),
    );
  }
}
