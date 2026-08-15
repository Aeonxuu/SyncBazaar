import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../models/company.dart';
import '../../../../models/user.dart';
import '../../../widgets/app_dropdown.dart';
import '../pre_bazaar_form_field.dart';

/// Step 1: what the bazaar *is* — name, where, when, and who runs it.
///
/// Ordered by how the answers actually get decided rather than by field type:
/// you know the name, then you pick the venue, and only then do the dates and
/// the venue's payment methods mean anything. Payment methods sit directly
/// under the venue because they're a consequence of it, not a separate choice.
class BazaarDetailsStep extends StatelessWidget {
  const BazaarDetailsStep({
    super.key,
    required this.eventNameController,
    required this.locations,
    required this.selectedCompanyId,
    required this.onCompanyChanged,
    required this.dateRange,
    required this.onPickDates,
    required this.configuredPaymentMethods,
    required this.employees,
    required this.assignedEmployees,
    required this.onAssignEmployee,
    required this.onRemoveAssignedEmployee,
    required this.showEmployeeAssignment,
    this.schedulingConflicts = const {},
  });

  final TextEditingController eventNameController;
  final List<Company> locations;
  final int? selectedCompanyId;
  final ValueChanged<int> onCompanyChanged;
  final DateTimeRange? dateRange;
  final VoidCallback onPickDates;
  final List<PaymentMethodMeta> configuredPaymentMethods;
  final List<AppUser> employees;
  final List<MapEntry<int, String>> assignedEmployees;
  final ValueChanged<int> onAssignEmployee;
  final ValueChanged<int> onRemoveAssignedEmployee;
  final bool showEmployeeAssignment;

  /// Employee id to the bazaar they are already working over these dates.
  /// Empty until the dates are chosen — there is nothing to clash with yet.
  final Map<int, String> schedulingConflicts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedLocation = locations
        .where((location) => location.id == selectedCompanyId)
        .firstOrNull;
    final hasDates = dateRange != null;
    // Only offer people who aren't already on the roster — listing an assigned
    // employee again invites a tap that does nothing.
    final assignedIds = assignedEmployees.map((e) => e.key).toSet();
    final assignable = employees
        .where((employee) => !assignedIds.contains(employee.id))
        .where((employee) => !schedulingConflicts.containsKey(employee.id))
        .toList();
    // Shown rather than silently dropped: "where did Missy go?" is a worse
    // question than "why can't I pick Missy?", and the answer to the second
    // is a bazaar name.
    final unavailable = employees
        .where((employee) => !assignedIds.contains(employee.id))
        .where((employee) => schedulingConflicts.containsKey(employee.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PreBazaarFormField(
          label: 'Event name',
          child: TextField(
            controller: eventNameController,
            textCapitalization: TextCapitalization.words,
            style: theme.textTheme.bodyMedium,
            decoration: preBazaarInputDecoration(
              hint: 'e.g. SyncBazaar Summer Pop-up',
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Venue and dates share a row on wide screens: they're the two
        // "where and when" facts, and pairing them keeps the form from
        // becoming one long column of identical boxes.
        LayoutBuilder(
          builder: (context, constraints) {
            final location = PreBazaarFormField(
              label: 'Venue',
              child: AppDropdown<Company>(
                options: locations,
                selected: selectedLocation,
                labelOf: (location) => location.name,
                hint: locations.isEmpty
                    ? 'No venues set up yet'
                    : 'Select a venue',
                leadingIcon: Icons.storefront_outlined,
                onSelected: (location) => onCompanyChanged(location.id),
              ),
            );
            final dates = PreBazaarFormField(
              label: 'Event dates',
              child: _DateRangeField(dateRange: dateRange, onTap: onPickDates),
            );

            if (constraints.maxWidth < 620) {
              return Column(
                children: [location, const SizedBox(height: 16), dates],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: location),
                const SizedBox(width: 16),
                Expanded(child: dates),
              ],
            );
          },
        ),
        const SizedBox(height: 8),

        // Read-only consequence of the venue, so it's shown as a quiet
        // caption plus chips rather than as another editable-looking field.
        _PaymentMethodsSummary(methods: configuredPaymentMethods),

        if (showEmployeeAssignment) ...[
          const SizedBox(height: 24),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staffing',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDates
                          ? 'Optional — assign who will run the booth. '
                                'Anyone already working these dates is '
                                'listed as unavailable.'
                          : 'Pick the bazaar dates first. Until then there '
                                'is no way to tell who is free.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black45,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: AppDropdown<AppUser>(
              // Dates decide who is free, so there is nothing sound to offer
              // before they are set. Assigning first and checking afterwards
              // is how somebody ends up rostered at two stalls at once.
              options: hasDates ? assignable : const [],
              selected: null,
              labelOf: (employee) => employee.name,
              hint: !hasDates
                  ? 'Choose the dates first'
                  : employees.isEmpty
                  ? 'No employees available'
                  : assignable.isEmpty
                  ? (unavailable.isEmpty
                        ? 'Everyone is already assigned'
                        : 'Nobody is free on these dates')
                  : 'Add an employee',
              leadingIcon: Icons.person_add_alt,
              onSelected: (employee) => onAssignEmployee(employee.id),
            ),
          ),
          if (hasDates && unavailable.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final employee in unavailable)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_busy_outlined,
                      size: 14,
                      color: Colors.black38,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${employee.name} — already at '
                        '${schedulingConflicts[employee.id]}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          if (assignedEmployees.isEmpty)
            Text(
              'Nobody assigned yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black38,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final employee in assignedEmployees)
                  _AssignedChip(
                    name: employee.value,
                    onRemove: () => onRemoveAssignedEmployee(employee.key),
                  ),
              ],
            ),
        ],

        // A quiet, always-present readout of what's still missing. It sits at
        // the bottom of the step, next to where the eye lands before reaching
        // for Continue, instead of surfacing as an error only after a failed
        // tap.
        const SizedBox(height: 24),
        _CompletionHint(
          hasName: eventNameController.text.trim().isNotEmpty,
          hasLocation: selectedCompanyId != null,
          hasDates: hasDates,
          hasPaymentMethods: configuredPaymentMethods.isNotEmpty,
        ),
      ],
    );
  }
}

class _DateRangeField extends StatelessWidget {
  const _DateRangeField({required this.dateRange, required this.onTap});

  final DateTimeRange? dateRange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('MMM d, y');
    final label = dateRange == null
        ? 'Select start and end date'
        : '${format.format(dateRange!.start)} – ${format.format(dateRange!.end)}';

    return Material(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // Matches the text fields and dropdowns beside it, so the row of
        // inputs shares one baseline and one height.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: Colors.black45,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: dateRange == null ? Colors.black38 : AppColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodsSummary extends StatelessWidget {
  const _PaymentMethodsSummary({required this.methods});

  final List<PaymentMethodMeta> methods;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (methods.isEmpty) {
      // A blocker, not a note — this is the one prerequisite the user can't
      // fix from this screen, so it says where to go instead.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFB45309).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: Color(0xFFB45309),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This venue has no payment methods yet. Add them under '
                'Venues & Terms before creating a bazaar here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB45309),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Accepted payments at this venue',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black45,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in methods)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  method.extraFieldLabel != null &&
                          method.extraFieldLabel!.trim().isNotEmpty
                      ? '${method.name} · ${method.extraFieldLabel}'
                      : method.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AssignedChip extends StatelessWidget {
  const _AssignedChip({required this.name, required this.onRemove});

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists what's still outstanding before this step can be left.
///
/// Shown continuously rather than as a snackbar after a rejected tap: the
/// requirements are knowable up front, so stating them costs one line and
/// removes a dead-end interaction.
class _CompletionHint extends StatelessWidget {
  const _CompletionHint({
    required this.hasName,
    required this.hasLocation,
    required this.hasDates,
    required this.hasPaymentMethods,
  });

  final bool hasName;
  final bool hasLocation;
  final bool hasDates;
  final bool hasPaymentMethods;

  @override
  Widget build(BuildContext context) {
    final missing = <String>[
      if (!hasName) 'event name',
      if (!hasLocation) 'venue',
      if (!hasDates) 'dates',
      if (!hasPaymentMethods) 'payment methods at this venue',
    ];

    final theme = Theme.of(context);
    if (missing.isEmpty) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          Text(
            'Details complete — continue to stock allocation.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF2E7D32),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: Colors.black38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Still needed: ${missing.join(', ')}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black45,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
