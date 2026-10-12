import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import 'app_dropdown.dart';

/// Picks the one employee, besides the owner, who may approve refunds at a
/// bazaar.
///
/// A single-select because the server allows exactly one handler per bazaar,
/// and a control that offers one choice states that rule without a sentence.
/// It sits next to the staff list it draws from, so there is nothing to open
/// first.
///
/// Used in the Preparations form, where picking only changes the form, and in
/// the bazaar info dialog, where picking is a request to the server. [busy]
/// and [errorText] are for the second: a spinner while it runs and the reason
/// when it fails, beside the field rather than in a message elsewhere.
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

  /// The employees who can be chosen, as id and name.
  final List<MapEntry<int, String>> candidates;

  /// Null means nobody.
  final int? selectedId;

  /// Called with the chosen user's id, or null for None.
  final ValueChanged<int?> onChanged;

  /// A request is out. Dims the field and shows a spinner.
  final bool busy;

  final bool enabled;
  final String? errorText;

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
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}
