import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../bloc/orders/orders_cubit.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/remote/api_client.dart';
import '../../../../data/remote/vendor_payment_method_api_mapper.dart';
import '../../../../data/repositories/refund_repository.dart';
import '../../../../models/bazaar_event.dart';
import '../../../../models/refund.dart';
import '../../../widgets/action_buttons.dart';
import '../../../widgets/floating_label_text_field.dart';
import '../../../widgets/selectable_option_button.dart';

/// The server's `reason` column is 255 characters; "Other: " takes seven.
const int _otherReasonLimit = 240;

const String _cash = 'CASH';

/// The reasons offered as one tap. Anything else goes under Other.
const List<String> kRefundReasons = [
  'Wrong size',
  'Defective',
  'Changed mind',
  'Other',
];

const String _otherReason = 'Other';

/// What the person sees when the server refuses the password. One message for
/// a wrong password and for a missing permission, because the server does not
/// say which it was.
const String kRefundPasswordRefused =
    "That password can't approve refunds at this bazaar.";

const String kRefundNeedsConnection = 'Refunds need a connection.';

/// Asks for the reason and the approver's password, then refunds [record].
///
/// Returns the [Refund] once the server has accepted it, and null if the
/// person backed out. The caller shows the confirmation and reloads, because
/// it holds the cubits; this holds only what the refund itself needs.
///
/// [loadMethods] supplies the payment-method catalog, which is where a method's
/// id comes from. A refund names its method by id and a sale only knows its
/// method by name.
Future<Refund?> showRefundDialog({
  required BuildContext context,
  required TransactionRecord record,
  required BazaarEvent event,
  required RefundRepository refunds,
  required Future<List<ModeOfPaymentCatalogEntry>> Function() loadMethods,
}) {
  return showDialog<Refund>(
    context: context,
    // A stray tap on the scrim would throw away a typed reason and, worse,
    // could dismiss while the request is in flight. Cancel and Esc remain.
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => RefundDialog(
      record: record,
      event: event,
      refunds: refunds,
      loadMethods: loadMethods,
    ),
  );
}

class RefundDialog extends StatefulWidget {
  const RefundDialog({
    super.key,
    required this.record,
    required this.event,
    required this.refunds,
    required this.loadMethods,
  });

  final TransactionRecord record;
  final BazaarEvent event;
  final RefundRepository refunds;
  final Future<List<ModeOfPaymentCatalogEntry>> Function() loadMethods;

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  /// Made once when the dialog opens and reused on every attempt. A retry after
  /// a lost answer then carries the same identity, which is what lets it be
  /// recognised as the refund it was instead of being refused as a second one.
  final String _clientUuid = const Uuid().v4();

  final TextEditingController _otherReasonText = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _approval = TextEditingController();

  String? _reason;

  List<ModeOfPaymentCatalogEntry>? _methods;
  bool _methodsFailed = false;

  bool _busy = false;
  String? _approvalError;
  String? _bannerError;

  /// The money goes back the way it came in: cash to cash, GCash to GCash. Not
  /// a choice, for record keeping and so a refund cannot be used to move money
  /// from one channel to another.
  late final String _method;

  @override
  void initState() {
    super.initState();
    final original = widget.record.paymentMethod.trim().toUpperCase();
    _method = original.isEmpty ? _cash : original;
    _loadMethods();
  }

  @override
  void dispose() {
    _otherReasonText.dispose();
    _reference.dispose();
    _approval.dispose();
    super.dispose();
  }

  Future<void> _loadMethods() async {
    try {
      final methods = await widget.loadMethods();
      if (!mounted) return;
      setState(() => _methods = methods);
    } catch (_) {
      if (!mounted) return;
      setState(() => _methodsFailed = true);
    }
  }

  ModeOfPaymentCatalogEntry? _entryFor(String name) => _methods
      ?.where((entry) => entry.name.trim().toUpperCase() == name)
      .firstOrNull;

  bool get _needsReference => _method != _cash;

  /// What the POS calls this method's extra field, so the refund asks for the
  /// same thing the sale did.
  String get _referenceLabel {
    final fromBazaar = widget.event.customOtherMethods
        .where((m) => m.name.trim().toUpperCase() == _method)
        .map((m) => m.extraFieldLabel)
        .firstOrNull;
    final label = (fromBazaar ?? _entryFor(_method)?.extraFieldLabel)?.trim();
    return label == null || label.isEmpty ? 'Reference number' : label;
  }

  /// The text sent as `reason`: the chip, or "Other: <text>".
  String? get _reasonToSend {
    final reason = _reason;
    if (reason == null) return null;
    if (reason != _otherReason) return reason;
    final text = _otherReasonText.text.trim();
    return text.isEmpty ? null : 'Other: $text';
  }

  bool get _canSubmit =>
      !_busy &&
      widget.record.onServer &&
      _entryFor(_method) != null &&
      _reasonToSend != null &&
      _approval.text.isNotEmpty &&
      (!_needsReference || _reference.text.trim().isNotEmpty);

  Future<void> _submit() async {
    final entry = _entryFor(_method);
    final reason = _reasonToSend;
    // The server's id, never the local one: the server has no sale by the
    // number the till made up.
    final serverSaleId = widget.record.serverSaleId;
    if (!_canSubmit ||
        entry == null ||
        reason == null ||
        serverSaleId == null) {
      return;
    }
    setState(() {
      _busy = true;
      _bannerError = null;
      _approvalError = null;
    });
    try {
      final refund = await widget.refunds.approveRefund(
        eventId: widget.record.eventId,
        saleId: serverSaleId,
        amount: widget.record.total,
        methodId: entry.id,
        reason: reason,
        reference: _needsReference ? _reference.text : null,
        clientUuid: _clientUuid,
        password: _approval.text,
      );
      if (!mounted) return;
      Navigator.pop(context, refund);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error.isOffline) {
          _bannerError = kRefundNeedsConnection;
        } else if (error.kind == ApiErrorKind.forbidden) {
          // Cleared so the next person types theirs rather than adding to it.
          _approval.clear();
          _approvalError = kRefundPasswordRefused;
        } else {
          _bannerError = error.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _bannerError = 'The refund could not be completed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.record;

    return PopScope(
      // Not while the request is out: closing would hide whether it landed.
      canPop: !_busy,
      child: Dialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summary(theme, record),
                      const SizedBox(height: 20),
                      _sectionLabel(theme, 'Reason'),
                      const SizedBox(height: 8),
                      _reasonChips(),
                      if (_reason == _otherReason) ...[
                        const SizedBox(height: 12),
                        FloatingLabelTextField(
                          labelText: 'What happened?',
                          controller: _otherReasonText,
                          enabled: !_busy,
                          onChanged: (_) => setState(() {}),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(_otherReasonLimit),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      _sectionLabel(theme, 'Refund via'),
                      const SizedBox(height: 8),
                      Text(
                        _method,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                      if (_needsReference) ...[
                        const SizedBox(height: 14),
                        FloatingLabelTextField(
                          labelText: _referenceLabel,
                          controller: _reference,
                          enabled: !_busy,
                          helperText:
                              'Reference of the money sent back to the customer.',
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _stockLine(theme),
                      const SizedBox(height: 20),
                      RefundApprovalField(
                        controller: _approval,
                        enabled: !_busy,
                        errorText: _approvalError,
                        onChanged: (_) => setState(() => _approvalError = null),
                      ),
                      if (_methods != null && _entryFor(_method) == null) ...[
                        const SizedBox(height: 14),
                        _InlineError(
                          message:
                              '$_method is not in the payment-method list, so '
                              'this sale cannot be refunded here.',
                        ),
                      ],
                      if (_methodsFailed) ...[
                        const SizedBox(height: 14),
                        const _InlineError(
                          message:
                              'Payment methods could not be loaded, so this '
                              'refund cannot be sent. Close and try again.',
                        ),
                      ],
                      AnimatedSize(
                        duration: AppMotion.small,
                        curve: AppMotion.easeOut,
                        alignment: Alignment.topCenter,
                        child: _bannerError == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: _InlineError(message: _bannerError!),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_busy) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    QuietActionButton(
                      label: 'Cancel',
                      color: Colors.black54,
                      onPressed: _busy ? null : () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    FilledActionButton(
                      label: _busy
                          ? 'Refunding…'
                          : 'Refund ${formatPeso(record.total)}',
                      color: AppColors.error,
                      onPressed: _canSubmit ? _submit : null,
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

  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.undo_rounded,
              size: 19,
              color: AppColors.error,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Refund sale',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(ThemeData theme, TransactionRecord record) {
    final time = record.timestamp;
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final when =
        '${formatDate(time)} · $hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';

    return Column(
      children: [
        _SummaryRow(label: 'Customer', value: record.customerName),
        _SummaryRow(label: 'Product', value: record.productLabel),
        _SummaryRow(label: 'Paid with', value: record.paymentMethod),
        _SummaryRow(label: 'Sold', value: when),
        _SummaryRow(
          label: 'Total',
          value: formatPeso(record.total),
          emphasize: true,
          last: true,
        ),
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    ),
  );

  Widget _reasonChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final reason in kRefundReasons)
          SelectableOptionButton(
            label: reason,
            isSelected: _reason == reason,
            onTap: _busy ? null : () => setState(() => _reason = reason),
          ),
      ],
    );
  }

  Widget _stockLine(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.inventory_2_outlined,
            size: 17,
            color: Colors.black45,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "The item goes back to this bazaar's stock.",
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

/// Where the approver proves who they are.
///
/// Its own widget because it is the one part of the dialog that will have a
/// second form. The dialog only reads [controller]'s text as the credential, so
/// a different way of approving replaces this field and nothing around it.
class RefundApprovalField extends StatelessWidget {
  const RefundApprovalField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return FloatingLabelTextField(
      labelText: 'Owner or refund handler password',
      controller: controller,
      obscureText: true,
      enabled: enabled,
      onChanged: onChanged,
      errorText: errorText,
      helperText:
          "Ask the owner or this bazaar's refund handler to enter their "
          'password.',
    );
  }
}

/// A label and its value on a hairline-ruled row. No panel around the group,
/// the same as the approvals review dialog.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.last = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF3F3F6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black45,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A problem with the request as a whole, shown beside what caused it.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 17,
              color: AppColors.error,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
