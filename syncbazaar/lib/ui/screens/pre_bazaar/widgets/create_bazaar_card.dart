import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../models/bazaar_event.dart';
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
    required this.acceptedPaymentMethods,
    required this.onPaymentMethodToggled,
    required this.otherPaymentMethodController,
    required this.otherRequiresEmployeeId,
    required this.onOtherRequiresEmployeeIdChanged,
    required this.onAddOtherMethod,
    required this.customOtherMethods,
    required this.onRemoveOtherMethod,
    this.isNextEnabled = true,
  });

  final TextEditingController eventNameController;
  final int? selectedCompanyId;
  final List<DropdownMenuItem<int>> companyItems;
  final DateTimeRange? dateRange;
  final ValueChanged<int?> onCompanyChanged;
  final VoidCallback onPickDates;
  final VoidCallback onCancel;
  final VoidCallback onNext;
  final Set<String> acceptedPaymentMethods;
  final void Function(String method, bool enabled) onPaymentMethodToggled;
  final TextEditingController otherPaymentMethodController;
  final bool otherRequiresEmployeeId;
  final ValueChanged<bool> onOtherRequiresEmployeeIdChanged;
  final VoidCallback onAddOtherMethod;
  final List<BazaarPaymentMethod> customOtherMethods;
  final ValueChanged<String> onRemoveOtherMethod;
  final bool isNextEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  color: AppColors.primary.withOpacity(0.12),
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
          TextField(
            controller: eventNameController,
            decoration: const InputDecoration(
              labelText: 'Event name',
              hintText: 'e.g. SyncBazaar Summer Pop-up',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: selectedCompanyId,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: companyItems,
            onChanged: onCompanyChanged,
            decoration: const InputDecoration(
              labelText: 'Company',
              hintText: 'Select a company',
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPickDates,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFFF5F1FB),
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
            'Accepted payment methods',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _paymentChip('CASH'),
              _paymentChip('COOP'),
              _paymentChip('OTHER'),
            ].map((chip) {
              return FilterChip(
                label: Text(chip),
                selected: acceptedPaymentMethods.contains(chip),
                onSelected: (value) => onPaymentMethodToggled(chip, value),
              );
            }).toList(),
          ),
          if (acceptedPaymentMethods.contains('OTHER')) ...[
            const SizedBox(height: 10),
            TextField(
              controller: otherPaymentMethodController,
              decoration: const InputDecoration(
                labelText: 'Other payment method name',
                hintText: 'e.g. GCASH, MAYA, BANK TRANSFER',
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Requires Employee ID'),
              value: otherRequiresEmployeeId,
              onChanged: onOtherRequiresEmployeeIdChanged,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onAddOtherMethod,
                icon: const Icon(Icons.add),
                label: const Text('Add OTHER option'),
              ),
            ),
            if (customOtherMethods.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...customOtherMethods.map(
                (method) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${method.name}${method.requiresEmployeeId ? ' (Needs Employee ID)' : ''}',
                          ),
                        ),
                        IconButton(
                          onPressed: () => onRemoveOtherMethod(method.name),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.35),
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

  String _paymentChip(String method) => method;
}
