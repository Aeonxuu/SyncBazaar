import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../widgets/custom_card.dart';

class CreateBazaarCard extends StatelessWidget {
  const CreateBazaarCard({
    super.key,
    required this.eventNameController,
    required this.selectedCompanyId,
    required this.companyItems,
    required this.dateRange,
    required this.onCompanyChanged,
    required this.onPickDates,
    required this.onCancel,
    required this.onNext,
    required this.configuredPaymentMethods,
    required this.employeeItems,
    required this.selectedEmployeeId,
    required this.assignedEmployees,
    required this.onEmployeeChanged,
    required this.onRemoveAssignedEmployee,
    this.isNextEnabled = true,
    this.showEmployeeAssignment = false,
  });

  final TextEditingController eventNameController;
  final int? selectedCompanyId;
  final List<DropdownMenuItem<int>> companyItems;
  final DateTimeRange? dateRange;
  final ValueChanged<int?> onCompanyChanged;
  final VoidCallback onPickDates;
  final VoidCallback onCancel;
  final VoidCallback onNext;
  final List<PaymentMethodMeta> configuredPaymentMethods;
  final List<DropdownMenuItem<int>> employeeItems;
  final int? selectedEmployeeId;
  final List<MapEntry<int, String>> assignedEmployees;
  final ValueChanged<int?> onEmployeeChanged;
  final ValueChanged<int> onRemoveAssignedEmployee;
  final bool isNextEnabled;
  final bool showEmployeeAssignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelectedEmployeeInItems = employeeItems
      .map((item) => item.value)
      .contains(selectedEmployeeId);
    final effectiveSelectedEmployeeId =
      hasSelectedEmployeeInItems ? selectedEmployeeId : null;
    final dateLabel = dateRange == null
        ? 'Select start and end date'
        : '${DateFormat('MMM d, y').format(dateRange!.start)} - ${DateFormat('MMM d, y').format(dateRange!.end)}';

    return CustomCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Bazaar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Set up event details before allocation',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _fieldLabel(context, 'Event name'),
          const SizedBox(height: 4),
          TextField(
            controller: eventNameController,
            decoration: _filledDecoration(
              hintText: 'e.g. SyncBazaar Summer Pop-up',
            ),
          ),
          const SizedBox(height: 12),
          _fieldLabel(context, 'Location'),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            initialValue: selectedCompanyId,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: companyItems,
            onChanged: onCompanyChanged,
            decoration: _filledDecoration(
              hintText: 'Select a location',
            ),
          ),
          const SizedBox(height: 12),
          _fieldLabel(context, 'Event dates'),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPickDates,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFFF5F1FB),
                border: Border.all(color: Colors.transparent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Accepted payment methods (from Location)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (configuredPaymentMethods.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'No payment methods configured for this location. Configure it in Location section.',
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: configuredPaymentMethods
                  .map(
                    (method) => Chip(
                      label: Text(
                        method.requiresEmployeeId
                            ? '${method.name} (Needs Employee ID)'
                            : method.name,
                      ),
                      backgroundColor: const Color(0xFFF5F1FB),
                    ),
                  )
                  .toList(),
            ),
          if (showEmployeeAssignment) ...[
            const SizedBox(height: 12),
            _fieldLabel(context, 'Assign employee(s)'),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: effectiveSelectedEmployeeId,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: employeeItems,
              onChanged: employeeItems.isEmpty ? null : onEmployeeChanged,
              decoration: _filledDecoration(
                hintText: employeeItems.isEmpty
                    ? 'No available employees to assign'
                    : 'Select employee',
              ),
            ),
            const SizedBox(height: 8),
            if (assignedEmployees.isEmpty)
              Text(
                'No employees assigned yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: assignedEmployees
                    .map(
                      (employee) => InputChip(
                        label: Text(employee.value),
                        onDeleted: () => onRemoveAssignedEmployee(employee.key),
                        backgroundColor: const Color(0xFFF5F1FB),
                      ),
                    )
                    .toList(),
              ),
          ],
          const Spacer(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isNextEnabled ? onNext : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white70,
                ),
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.grey,
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
    );
  }

  InputDecoration _filledDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      filled: true,
      fillColor: const Color(0xFFF5F1FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
