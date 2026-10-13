import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import 'app_dropdown.dart';

/// The choice itself, with no heading of its own: the dropdown, a spinner
/// while a request is out, and the reason when it failed.
///
/// For a place that supplies its own label, such as a row in a details dialog.
/// [RefundHandlerField] is this with a heading and a sentence above it.
class RefundHandlerDropdown extends StatelessWidget {
  const RefundHandlerDropdown({
    super.key,
    required this.candidates,
    required this.selectedId,
    required this.onChanged,
    this.busy = false,
    this.enabled = true,
    this.errorText,
    this.showSpinner = true,
  });

  /// The employees who can be chosen, as id and name.
  final List<MapEntry<int, String>> candidates;

  /// Null means nobody.
  final int? selectedId;

  /// Called with the chosen user's id, or null for None.
  final ValueChanged<int?> onChanged;

  /// A request is out. Dims the field.
  final bool busy;
  final bool enabled;
  final String? errorText;

  /// Draws the spinner beside the dropdown. A caller that shows progress
  /// elsewhere turns this off.
  final bool showSpinner;

  /// The option for nobody. An id of zero cannot be a real user, so it can
  /// share a list with the real ones.
  static const int _none = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = {for (final entry in candidates) entry.key: entry.value};
    final hasCandidates = candidates.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppDropdown<int>(
                options: hasCandidates ? [_none, ...names.keys] : const [],
                selected: hasCandidates ? (selectedId ?? _none) : null,
                labelOf: (id) =>
                    id == _none ? 'None' : (names[id] ?? 'Employee #$id'),
                hint: hasCandidates ? 'None' : 'Assign an employee first',
                leadingIcon: Icons.verified_user_outlined,
                enabled: enabled && !busy && hasCandidates,
                hasError: errorText != null,
                onSelected: (id) => onChanged(id == _none ? null : id),
              ),
            ),
            if (busy && showSpinner) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            errorText!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// Picks the one employee, besides the owner, who may approve refunds at a
/// bazaar.
///
/// A single-select because the server allows exactly one handler per bazaar,
/// and a control that offers one choice states that rule without a sentence.
/// It sits next to the staff list it draws from, so there is nothing to open
/// first.
///
/// Used in the Preparations form, where picking only changes the form. The
/// bazaar info dialog uses [RefundHandlerDropdown] in a row of its own.
class RefundHandlerField extends StatelessWidget {
  const RefundHandlerField({
    super.key,
    required this.candidates,
    required this.selectedId,
    required this.onChanged,
    this.busy = false,
    this.enabled = true,
    this.errorText,
  });

  final List<MapEntry<int, String>> candidates;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final bool busy;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Refund handler',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (busy) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Besides the owner, this person can approve refunds at this bazaar.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black45,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: RefundHandlerDropdown(
            candidates: candidates,
            selectedId: selectedId,
            onChanged: onChanged,
            busy: busy,
            enabled: enabled,
            errorText: errorText,
            showSpinner: false,
          ),
        ),
      ],
    );
  }
}
