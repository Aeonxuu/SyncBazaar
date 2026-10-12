import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../bloc/approvals/approvals_cubit.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/approval_request.dart';
import '../../../widgets/action_buttons.dart';
import '../../../widgets/app_message.dart';
import '../../../widgets/confirmation_dialog.dart';
import '../../../widgets/loading_dialog.dart';
import '../../../widgets/step_marker.dart';

/// Opens a request in two steps: the bazaar being asked for, then what stock
/// it wants.
///
/// [canDecide] is whether the viewer may answer it. Only owners and admins
/// decide; an employee sees the same detail with nothing to press.
Future<void> showApprovalDetailsDialog({
  required BuildContext context,
  required ApprovalRequest request,
  required bool canDecide,
}) {
  // Handed down explicitly: a dialog route is built above the screen, so it
  // only sees the cubit where the provider happens to sit over the navigator.
  final approvals = context.read<ApprovalsCubit>();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => BlocProvider.value(
      value: approvals,
      child: _ApprovalDetailsDialog(request: request, canDecide: canDecide),
    ),
  );
}

class _ApprovalDetailsDialog extends StatefulWidget {
  const _ApprovalDetailsDialog({
    required this.request,
    required this.canDecide,
  });

  final ApprovalRequest request;
  final bool canDecide;

  @override
  State<_ApprovalDetailsDialog> createState() => _ApprovalDetailsDialogState();
}

class _ApprovalDetailsDialogState extends State<_ApprovalDetailsDialog> {
  static const _lastStep = 1;

  int _step = 0;
  late final _Details _details;
  late final Future<Map<int, String>> _staffNames;

  @override
  void initState() {
    super.initState();
    _details = _Details.parse(widget.request);
    // Looked up rather than carried in the request, which holds only ids. A
    // failure just leaves ids showing; it never stops the request opening.
    _staffNames = context.read<ApprovalsCubit>().employeeNames(
      _details.assignedIds,
    );
  }

  Future<void> _reject() async {
    final approvals = context.read<ApprovalsCubit>();
    final dialogNavigator = Navigator.of(context, rootNavigator: true);
    showLoadingDialog(context, 'Rejecting request…');
    try {
      await approvals.reject(widget.request);
    } finally {
      dialogNavigator.pop();
    }
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
    showAppMessage(
      'Request rejected.',
      kind: AppMessageKind.success,
      title: 'Request rejected',
    );
  }

  Future<void> _approve() async {
    // Taken before the confirmation: the dialog is popped on success, so
    // these must not be looked up through a context on its way out.
    final navigator = Navigator.of(context);
    final approvals = context.read<ApprovalsCubit>();
    final request = widget.request;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Confirm Stock Allocation',
      message: request.type == ApprovalType.stock
          ? 'Approve stock allocation request for ${_details.name}?'
          : 'Approve this request?',
      confirmLabel: 'Approve',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    // Checking staff and stock and writing the bazaar is several requests;
    // without this the dialog just sat there after Confirm.
    final dialogNavigator = Navigator.of(context, rootNavigator: true);
    showLoadingDialog(context, 'Approving bazaar…');
    final String? error;
    try {
      error = await approvals.approve(request);
    } finally {
      dialogNavigator.pop();
    }
    if (!mounted) {
      return;
    }
    if (error != null) {
      await showNoticeDialog(
        context: context,
        title: 'Bazaar cannot be approved',
        message: error,
        buttonLabel: 'Okay',
        tone: ConfirmationTone.destructive,
        icon: Icons.block_rounded,
      );
      return;
    }
    await showNoticeDialog(
      context: context,
      title: 'Bazaar approved',
      message: 'The request was approved and synced to the POS.',
      buttonLabel: 'Okay',
      icon: Icons.check_circle_outline_rounded,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: AppColors.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: _step == 0
                    ? _buildBazaarStep(context)
                    : _buildProductsStep(context),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approval Details',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _details.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                splashRadius: 18,
                tooltip: 'Close',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, right: 14),
            child: _buildStepper(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    const labels = ['Bazaar', 'Products'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: i <= _step ? AppColors.primary : AppColors.border,
              ),
            ),
          StepMarker(
            number: i + 1,
            label: labels[i],
            isDone: i < _step,
            isCurrent: i == _step,
            // Both steps are read-only, so nothing gates moving forward, but
            // the header still only offers the step already passed: the
            // footer's button is the way on.
            onTap: i < _step ? () => setState(() => _step = i) : null,
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------ steps

  Widget _buildBazaarStep(BuildContext context) {
    return Column(
      children: [
        _DetailRow(label: 'Bazaar', child: _valueText(context, _details.name)),
        _DetailRow(
          label: 'Venue',
          child: _valueText(context, _details.location),
        ),
        _DetailRow(
          label: 'Dates',
          child: _valueText(context, _details.dates ?? 'Not specified'),
        ),
        _DetailRow(
          label: 'Assigned',
          isLast: true,
          child: FutureBuilder<Map<int, String>>(
            future: _staffNames,
            builder: (context, snapshot) {
              if (_details.assignedIds.isEmpty) {
                return _valueText(context, 'Nobody assigned', muted: true);
              }
              final names = snapshot.data ?? const <int, String>{};
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in _details.assignedIds)
                    _StaffTag(label: names[id] ?? 'Employee #$id'),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductsStep(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _details.lines;
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _details.unreadable
              ? 'Unable to read the details of this request.'
              : 'No product details available.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
      );
    }

    final units = lines.fold<int>(0, (sum, line) => sum + (line.qty ?? 0));
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.black45,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Text(
            '${formatCount(lines.length)} '
            '${lines.length == 1 ? 'item' : 'items'}'
            ' · ${formatCount(units)} '
            '${units == 1 ? 'unit' : 'units'} requested',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
        ),
        Row(
          children: [
            Expanded(child: Text('Product', style: captionStyle)),
            SizedBox(
              width: 96,
              child: Text(
                'Price',
                textAlign: TextAlign.right,
                style: captionStyle,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                'Qty',
                textAlign: TextAlign.right,
                style: captionStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.border),
        for (var i = 0; i < lines.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lines[i].name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (lines[i].variant != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          lines[i].variant!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    lines[i].price ?? '—',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    lines[i].qty == null ? '—' : formatCount(lines[i].qty!),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < lines.length - 1)
            const Divider(height: 1, color: AppColors.border),
        ],
      ],
    );
  }

  Text _valueText(BuildContext context, String text, {bool muted = false}) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
        color: muted ? Colors.black45 : AppColors.text,
      ),
    );
  }

  // ----------------------------------------------------------------- footer

  Widget _buildFooter(BuildContext context) {
    final isLast = _step == _lastStep;
    final theme = Theme.of(context);

    // Reject stays at the left edge on both steps and the way forward at the
    // right, so the one destructive choice is never beside the button a
    // thumb is already heading for.
    final Widget leading = widget.canDecide
        ? QuietActionButton(
            label: 'Reject',
            color: AppColors.error,
            outlined: true,
            onPressed: _reject,
          )
        : (isLast
              ? Expanded(
                  child: Text(
                    'Waiting for an owner to review this request.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : const SizedBox.shrink());

    final Widget primary = !isLast
        ? FilledActionButton(
            label: 'Continue',
            color: AppColors.primary,
            autofocus: true,
            onPressed: () => setState(() => _step += 1),
          )
        : widget.canDecide
        ? FilledActionButton(
            label: 'Approve',
            color: AppColors.statusOngoing,
            autofocus: true,
            onPressed: _approve,
          )
        : FilledActionButton(
            label: 'Close',
            color: AppColors.primary,
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        children: [
          leading,
          if (leading is! Expanded) const Spacer(),
          if (isLast) ...[
            QuietActionButton(
              label: 'Back',
              color: Colors.black54,
              outlined: true,
              onPressed: () => setState(() => _step -= 1),
            ),
            const SizedBox(width: 12),
          ],
          primary,
        ],
      ),
    );
  }
}

/// A label and its value, stacked as a row with a hairline beneath. No panel
/// around the group: the rules alone say these belong together.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.child,
    this.isLast = false,
  });

  final String label;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black45),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A person on the bazaar's roster. Tag tier: small, content-sized, radius 6.
class _StaffTag extends StatelessWidget {
  const _StaffTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Line {
  const _Line({required this.name, this.variant, this.price, this.qty});

  final String name;
  final String? variant;
  final String? price;
  final int? qty;
}

/// What a request says, read once and tolerant of anything missing: a dialog
/// that throws while building never appears, and then the request can be
/// neither read nor decided.
class _Details {
  const _Details({
    required this.title,
    required this.name,
    required this.location,
    required this.dates,
    required this.assignedIds,
    required this.lines,
    required this.unreadable,
  });

  final String title;
  final String name;
  final String location;
  final String? dates;
  final List<int> assignedIds;
  final List<_Line> lines;
  final bool unreadable;

  static _Details parse(ApprovalRequest request) {
    final decoded = _decode(request.detailsJson);
    final map = decoded ?? const <String, dynamic>{};

    final rawName = map['eventName'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : 'Bazaar #${request.eventId}';

    final rawLocation = map['locationName'];
    final companyId = map['companyId'];
    final location = rawLocation is String && rawLocation.trim().isNotEmpty
        ? rawLocation.trim()
        : (companyId is int ? 'Venue ID: $companyId' : 'Venue not specified');

    final start = _date(map['dateStart']);
    final end = _date(map['dateEnd']);
    String? dates;
    if (start != null && end != null) {
      dates = formatDate(start) == formatDate(end)
          ? formatDate(start)
          : '${formatDate(start)} - ${formatDate(end)}';
    }

    final ids = <int>[];
    final rawIds = map['assignedEmployeeIds'];
    if (rawIds is List) {
      for (final value in rawIds) {
        final id = value is int ? value : int.tryParse('$value');
        if (id != null && !ids.contains(id)) {
          ids.add(id);
        }
      }
    }

    final lines = <_Line>[];
    final items = map['items'];
    if (items is List) {
      for (final item in items.whereType<Map>()) {
        final rawPrice = item['price'];
        final rawVariant = item['variant'];
        final variant = rawVariant?.toString().trim();
        final rawQty = item['qty'] ?? item['quantity'];
        lines.add(
          _Line(
            name: (item['name'] ?? '—').toString(),
            variant: variant == null || variant.isEmpty || variant == '—'
                ? null
                : variant,
            // Tolerates both shapes: requests raised before the payload
            // switched to a raw number still carry a string.
            price: rawPrice is num
                ? formatAmount(rawPrice)
                : rawPrice?.toString(),
            qty: rawQty is num ? rawQty.toInt() : int.tryParse('$rawQty'),
          ),
        );
      }
    } else if (map['allocations'] is Map) {
      for (final entry in (map['allocations'] as Map).entries) {
        lines.add(
          _Line(
            name: entry.key.toString(),
            qty: entry.value is num
                ? (entry.value as num).toInt()
                : int.tryParse('${entry.value}'),
          ),
        );
      }
    }

    return _Details(
      title: request.type == ApprovalType.stock
          ? 'Stock request for $name'
          : '${request.type.name.toUpperCase()} request #${request.id}',
      name: name,
      location: location,
      dates: dates,
      assignedIds: ids,
      lines: lines,
      unreadable: decoded == null,
    );
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  static Map<String, dynamic>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
