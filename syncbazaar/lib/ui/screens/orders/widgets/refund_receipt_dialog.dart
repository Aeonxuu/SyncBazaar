import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../models/receipt.dart';
import '../../../../services/receipt_service.dart';
import '../../../widgets/action_buttons.dart';
import '../../pos/widgets/receipt_document.dart';

/// Tells the person the refund went through, shows the receipt, and offers to
/// save it.
///
/// The refund is already done by the time this opens, so nothing here can undo
/// it: failing to save a receipt costs the customer a copy, not their money.
/// That is why a failure offers "Try again" against the same receipt and the
/// dialog can always be closed.
///
/// Offered rather than done for you. A sale prints without being asked because
/// every sale hands over a receipt; a refund is rarer, and the person may want
/// to hand over nothing, or save it once the customer has gone. The save itself
/// is the same pipeline as a sale receipt's -- a PNG, to Photos on the tablet
/// and a file on a desktop.
Future<void> showRefundReceiptDialog({
  required BuildContext context,
  required RefundReceiptData data,
  ReceiptService service = const ReceiptService(),
}) {
  return showDialog<void>(
    context: context,
    // Not while saving: closing mid-write hides whether it landed.
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => RefundReceiptDialog(data: data, service: service),
  );
}

enum _SavePhase { idle, saving, saved, failed }

class RefundReceiptDialog extends StatefulWidget {
  const RefundReceiptDialog({
    super.key,
    required this.data,
    this.service = const ReceiptService(),
  });

  final RefundReceiptData data;
  final ReceiptService service;

  @override
  State<RefundReceiptDialog> createState() => _RefundReceiptDialogState();
}

class _RefundReceiptDialogState extends State<RefundReceiptDialog> {
  _SavePhase _phase = _SavePhase.idle;
  String _where = '';
  String _error = '';

  Future<void> _save() async {
    setState(() => _phase = _SavePhase.saving);
    try {
      final where = await widget.service.printRefundReceipt(
        widget.data,
        context: context,
      );
      if (!mounted) return;
      setState(() {
        _where = where;
        _phase = _SavePhase.saved;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _phase = _SavePhase.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saving = _phase == _SavePhase.saving;

    return PopScope(
      canPop: !saving,
      child: Dialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        size: 19,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Refund issued',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Approved by ${widget.data.approvedByName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              // The receipt as it will be saved, mounted for real: a preview
              // beats saving it to find out it is wrong. Capped and scrollable
              // so a long reason cannot push the buttons off a short screen.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: RefundReceiptDocument(data: widget.data),
                  ),
                ),
              ),
              if (_phase == _SavePhase.failed) ...[
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(
                    "Couldn't save the receipt. $_error",
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: Row(
                  children: [
                    if (_phase == _SavePhase.saved)
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _where,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const Spacer(),
                    if (saving) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_phase != _SavePhase.saved) ...[
                      QuietActionButton(
                        label: 'Close',
                        color: Colors.black54,
                        onPressed: saving ? null : () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                    ],
                    FilledActionButton(
                      label: switch (_phase) {
                        _SavePhase.idle => 'Save receipt',
                        _SavePhase.saving => 'Saving…',
                        _SavePhase.saved => 'Done',
                        _SavePhase.failed => 'Try again',
                      },
                      color: AppColors.primary,
                      autofocus: true,
                      onPressed: switch (_phase) {
                        _SavePhase.saving => null,
                        _SavePhase.saved => () => Navigator.pop(context),
                        _ => _save,
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
