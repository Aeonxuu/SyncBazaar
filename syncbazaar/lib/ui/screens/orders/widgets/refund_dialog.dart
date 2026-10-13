import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/detail_rows.dart';
import '../../../widgets/floating_label_text_field.dart';

/// The server's `reason` column is 255 characters; "Other: " takes seven.
const int _otherReasonLimit = 240;

const String _cash = 'CASH';

/// The reasons offered. Anything else goes under Other.
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

/// Shown under the reference when it is the original payment's own.
const String kRefundReusedReference =
    "This is the original payment's reference. Enter the reference of the "
    'money you sent back.';

const String kRefundNeedsConnection = 'Refunds need a connection.';

/// The tinted surface the sale's facts sit on.
const Color _panelFill = Color(0xFFF7F7F9);

/// Walks the person through refunding [record]: what and why, then a last look
/// and the approver's password.
///
/// Returns the [Refund] once the server has accepted it, and null if the
/// person backed out. The caller shows the confirmation and reloads, because
/// it holds the cubits; this holds only what the refund itself needs.
///
/// [loadMethods] supplies the payment-method catalog, which is where a method's
/// id comes from. A refund names its method by id and a sale only knows its
/// method by name. [soldByName] is who rang the sale up, for the summary.
Future<Refund?> showRefundDialog({
  required BuildContext context,
  required TransactionRecord record,
  required BazaarEvent event,
  required RefundRepository refunds,
  required Future<List<ModeOfPaymentCatalogEntry>> Function() loadMethods,
  String? soldByName,
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
      soldByName: soldByName,
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
    this.soldByName,
  });

  final TransactionRecord record;
  final BazaarEvent event;
  final RefundRepository refunds;
  final Future<List<ModeOfPaymentCatalogEntry>> Function() loadMethods;
  final String? soldByName;

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

  /// 0 is what and why; 1 is the last look and the password. One dialog whose
  /// content swaps, so going back keeps everything that was entered.
  int _step = 0;

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

  ModeOfPaymentCatalogEntry? get _entry => _methods
      ?.where((entry) => entry.name.trim().toUpperCase() == _method)
      .firstOrNull;

  /// The method as the vendor spells it ("GCash") once the list has loaded,
  /// else as the sale recorded it.
  String get _methodName => _entry?.name.trim() ?? widget.record.paymentMethod;

  bool get _needsReference => _method != _cash;

  /// What the POS calls this method's extra field, so the refund asks for the
  /// same thing the sale did.
  String get _referenceLabel {
    final fromBazaar = widget.event.customOtherMethods
        .where((m) => m.name.trim().toUpperCase() == _method)
        .map((m) => m.extraFieldLabel)
        .firstOrNull;
    final label = (fromBazaar ?? _entry?.extraFieldLabel)?.trim();
    return label == null || label.isEmpty ? 'Reference number' : label;
  }

  /// Strips spaces and case, so "gc 77" and "GC77" are the same reference.
  static String _comparable(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// Whether what was typed is the reference of the original payment.
  ///
  /// A GCash reference cannot be checked against GCash from here, but this slip
  /// can be: the money sent back has a reference of its own, and typing the one
  /// the customer paid with is the likeliest mistake. It would put a payment's
  /// reference on a refund, where an audit would take it for the same
  /// transaction.
  bool get _reusesPaymentReference {
    final original = _comparable(widget.record.paymentReference);
    return _needsReference &&
        original.isNotEmpty &&
        _comparable(_reference.text) == original;
  }

  /// The text sent as `reason`: the choice, or "Other: <text>".
  String? get _reasonToSend {
    final reason = _reason;
    if (reason == null) return null;
    if (reason != _otherReason) return reason;
    final text = _otherReasonText.text.trim();
    return text.isEmpty ? null : 'Other: $text';
  }

  /// Everything step one asks for, and nothing the server would refuse for a
  /// reason that was knowable here: a sale it does not hold, or a payment method
  /// it has no id for.
  bool get _canContinue =>
      widget.record.onServer &&
      _entry != null &&
      _reasonToSend != null &&
      (!_needsReference || _reference.text.trim().isNotEmpty) &&
      !_reusesPaymentReference;

  bool get _canRefund => !_busy && _canContinue && _approval.text.isNotEmpty;

  Future<void> _submit() async {
    final entry = _entry;
    final reason = _reasonToSend;
    // The server's id, never the local one: the server has no sale by the
    // number the till made up.
    final serverSaleId = widget.record.serverSaleId;
    if (!_canRefund ||
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
          // The dialog resizes to the step it shows, and the step itself
          // fades, so the swap reads as the same surface changing rather than
          // one dialog replacing another.
          child: AnimatedSize(
            duration: AppMotion.entrance,
            curve: AppMotion.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.entrance,
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeOut,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.03, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey<int>(_step),
                child: _step == 0 ? _whatAndWhy(theme) : _confirm(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- step one

  Widget _whatAndWhy(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, title: 'Refund sale'),
        const Divider(height: 1, color: AppColors.border),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summary(theme),
                const SizedBox(height: 16),
                AppDropdown<String>(
                  options: kRefundReasons,
                  selected: _reason,
                  labelOf: (reason) => reason,
                  hint: 'Select a reason',
                  onSelected: (reason) => setState(() => _reason = reason),
                ),
                _reveal(
                  show: _reason == _otherReason,
                  child: FloatingLabelTextField(
                    labelText: 'Describe the reason',
                    controller: _otherReasonText,
                    onChanged: (_) => setState(() {}),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_otherReasonLimit),
                    ],
                  ),
                ),
                _reveal(
                  show: _needsReference,
                  child: FloatingLabelTextField(
                    labelText: _referenceLabel,
                    controller: _reference,
                    helperText: 'Reference of the money sent back',
                    // Under the field it concerns, in place of the helper.
                    errorText: _reusesPaymentReference
                        ? kRefundReusedReference
                        : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_methods != null && _entry == null)
                  _below(
                    _InlineError(
                      message:
                          '$_method is not in the payment-method list, so '
                          'this sale cannot be refunded here.',
                    ),
                  ),
                if (_methodsFailed)
                  _below(
                    const _InlineError(
                      message:
                          'Payment methods could not be loaded, so this '
                          'refund cannot be sent. Close and try again.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        _footer(
          leading: QuietActionButton(
            label: 'Cancel',
            color: Colors.black54,
            onPressed: () => Navigator.pop(context),
          ),
          primary: FilledActionButton(
            label: 'Continue',
            color: AppColors.primary,
            onPressed: _canContinue ? () => setState(() => _step = 1) : null,
          ),
        ),
      ],
    );
  }

  /// All the facts about the sale, in one place on one surface.
  ///
  /// The product leads, the amount is the largest thing in it, and the rest sit
  /// below a rule as label and value pairs. One grouped block rather than a
  /// list of rows, so the eye reads it as a single thing to check.
  Widget _summary(ThemeData theme) {
    final record = widget.record;
    final name = record.productName ?? _split(record.productLabel).$1;
    final variant = record.variantDetail ?? _split(record.productLabel).$2;
    final sold = DateFormat('MMM d, y · h:mm a').format(record.timestamp);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (variant.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              variant,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            formatPeso(record.total),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE6E6EC)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: DetailFact('Customer', record.customerName)),
              const SizedBox(width: 16),
              Expanded(child: DetailFact('Sold', sold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: DetailFact('Sold by', widget.soldByName ?? '—')),
              const SizedBox(width: 16),
              Expanded(
                child: DetailFact(
                  'Refund via',
                  '$_methodName (same as payment)',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Product and variant from the combined label, for a record that was built
  /// without them: "Nike Air Max SC (Color Black, Size 42)".
  static (String, String) _split(String label) {
    final bracket = label.indexOf('(');
    if (bracket == -1) {
      return (label, '');
    }
    return (
      label.substring(0, bracket).trim(),
      label.substring(bracket + 1).replaceAll(')', '').trim(),
    );
  }

  // ---------------------------------------------------------------- step two

  Widget _confirm(ThemeData theme) {
    final record = widget.record;
    final how = _method == _cash ? 'in cash' : 'via $_methodName';
    final what =
        record.stockLabel ??
        record.productName ??
        _split(record.productLabel).$1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, title: 'Confirm refund'),
        const Divider(height: 1, color: AppColors.border),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Refund ${formatPeso(record.total)} $how to '
                  '${record.customerName}.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _Consequence(
                  icon: Icons.inventory_2_outlined,
                  text: "The $what goes back to this bazaar's stock.",
                ),
                const SizedBox(height: 8),
                const _Consequence(
                  icon: Icons.info_outline_rounded,
                  text: "This can't be undone.",
                  emphasize: true,
                ),
                const SizedBox(height: 20),
                RefundApprovalField(
                  controller: _approval,
                  enabled: !_busy,
                  errorText: _approvalError,
                  autofocus: true,
                  onChanged: (_) => setState(() => _approvalError = null),
                  onSubmitted: (_) => _submit(),
                ),
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
        _footer(
          leading: QuietActionButton(
            label: 'Back',
            color: Colors.black54,
            onPressed: _busy ? null : () => setState(() => _step = 0),
          ),
          busy: _busy,
          primary: FilledActionButton(
            label: _busy ? 'Refunding…' : 'Refund ${formatPeso(record.total)}',
            color: AppColors.error,
            onPressed: _canRefund ? _submit : null,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ shared parts

  Widget _header(ThemeData theme, {required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Said because there are two steps. A flow whose length is hidden
          // reads as endless.
          Text(
            'Step ${_step + 1} of 2',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
        ],
      ),
    );
  }

  /// The way out on the left, the way forward on the right and larger, with
  /// space between so the two are never confused under a thumb.
  Widget _footer({
    required Widget leading,
    required Widget primary,
    bool busy = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        children: [
          leading,
          const Spacer(),
          if (busy) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 12),
          ],
          primary,
        ],
      ),
    );
  }

  /// Slides a field into place under the one above it, so what a choice adds
  /// appears where the eye already is instead of the form jumping.
  Widget _reveal({required bool show, required Widget child}) {
    return AnimatedSize(
      duration: AppMotion.small,
      curve: AppMotion.easeOut,
      alignment: Alignment.topCenter,
      child: show
          ? Padding(padding: const EdgeInsets.only(top: 12), child: child)
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _below(Widget child) =>
      Padding(padding: const EdgeInsets.only(top: 14), child: child);
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
    this.onSubmitted,
    this.errorText,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onChanged;

  /// Enter in the field; the dialog points this at its Refund button.
  final ValueChanged<String>? onSubmitted;

  /// Brings up the keyboard on arrival. The password is the only thing this
  /// step asks for.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FloatingLabelTextField(
      labelText: 'Owner or refund handler password',
      controller: controller,
      obscureText: true,
      enabled: enabled,
      autofocus: autofocus,
      onChanged: onChanged,
      errorText: errorText,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
    );
  }
}

/// One line of what confirming will do.
class _Consequence extends StatelessWidget {
  const _Consequence({
    required this.icon,
    required this.text,
    this.emphasize = false,
  });

  final IconData icon;
  final String text;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 17, color: Colors.black45),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: emphasize ? AppColors.text : Colors.black54,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
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
