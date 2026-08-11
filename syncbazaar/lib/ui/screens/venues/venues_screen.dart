import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../bloc/settings/settings_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../models/company.dart';
import '../../../models/user.dart';

/// Venues the bazaars are held at, and the commercial terms agreed with each.
///
/// Named "Location" until 2026-08-03, which undersold it: a venue row also
/// carries the incentive and buffer percentages that come off the payout and
/// the payment methods the POS will offer there. Nobody hunting for "where do
/// I enable GCash" was going to look under a word that sounds like an address.
class VenuesScreen extends StatelessWidget {
  const VenuesScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final canManage = user.isAdminOrOwner;

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Venues & Terms',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (canManage)
                  ElevatedButton.icon(
                    onPressed: () => _openVenueEditor(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add venue'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!canManage)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No access'),
                ),
              )
            else if (state.companies.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No venues yet. Add the first place you sell at.',
                  ),
                ),
              )
            else
              ...state.companies.map((company) {
                final methods =
                    state.locationPaymentMethodsByCompanyId[company.id] ??
                    const [];
                return Card(
                  child: ListTile(
                    title: Text(company.name),
                    subtitle: Text(
                      'Incentive ${company.incentivePercent.toStringAsFixed(1)}% • Buffer ${company.bufferPercent.toStringAsFixed(1)}% • Methods ${methods.length}',
                    ),
                    trailing: IconButton(
                      onPressed: () => _openVenueEditor(
                        context,
                        existing: company,
                        existingMethods: methods,
                      ),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _openVenueEditor(
    BuildContext context, {
    Company? existing,
    List<PaymentMethodMeta> existingMethods = const [],
  }) async {
    final isCreate = existing == null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final addressController = TextEditingController(
      text: existing?.address ?? '',
    );
    final contactController = TextEditingController(
      text: existing?.contact ?? '',
    );
    final incentiveController = TextEditingController(
      text: existing == null ? '10' : existing.incentivePercent.toString(),
    );
    final bufferController = TextEditingController(
      text: existing == null ? '10' : existing.bufferPercent.toString(),
    );
    var qrImagePath = existing?.qrImagePath;

    final methods = <PaymentMethodMeta>[
      if (existingMethods.isNotEmpty)
        ...existingMethods
      else ...const [PaymentMethodMeta(name: 'CASH')],
    ];

    final methodNameController = TextEditingController();
    final methodExtraFieldController = TextEditingController();
    var isPaymentStep = !isCreate;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> pickQr() async {
              final picker = ImagePicker();
              final file = await picker.pickImage(source: ImageSource.gallery);
              if (file != null) {
                setState(() {
                  qrImagePath = file.path;
                });
              }
            }

            void addMethod() {
              final name = methodNameController.text.trim();
              final extraField = methodExtraFieldController.text.trim();
              if (name.isEmpty) {
                return;
              }
              if (extraField.length > 28) {
                return;
              }
              final exists = methods.any(
                (method) => method.name.toUpperCase() == name.toUpperCase(),
              );
              if (exists) {
                return;
              }
              setState(() {
                methods.add(
                  PaymentMethodMeta(
                    name: name,
                    extraFieldLabel: extraField.isEmpty ? null : extraField,
                  ),
                );
                methodNameController.clear();
                methodExtraFieldController.clear();
              });
            }

            Future<void> editExtraField(int index) async {
              final initial = methods[index].extraFieldLabel ?? '';
              final controller = TextEditingController(text: initial);
              final saved = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text('Extra field for ${methods[index].name}'),
                    content: TextField(
                      controller: controller,
                      maxLength: 28,
                      decoration: const InputDecoration(
                        hintText: 'Optional (e.g. Employee ID)',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          controller.clear();
                          Navigator.pop(context, true);
                        },
                        child: const Text('Clear'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Save'),
                      ),
                    ],
                  );
                },
              );

              if (saved != true) {
                return;
              }

              final nextLabel = controller.text.trim();
              setState(() {
                methods[index] = PaymentMethodMeta(
                  name: methods[index].name,
                  extraFieldLabel: nextLabel.isEmpty ? null : nextLabel,
                );
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(isCreate ? 'Add venue' : 'Edit venue'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isPaymentStep) ...[
                        _label(context, 'Venue name'),
                        const SizedBox(height: 4),
                        _field(nameController),
                        const SizedBox(height: 12),
                        _label(context, 'Address (optional)'),
                        const SizedBox(height: 4),
                        _field(addressController),
                        const SizedBox(height: 12),
                        _label(context, 'Contact (optional)'),
                        const SizedBox(height: 4),
                        _field(contactController),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label(context, 'Incentive deduction %'),
                                  const SizedBox(height: 4),
                                  _field(
                                    incentiveController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label(context, 'Buffer deduction %'),
                                  const SizedBox(height: 4),
                                  _field(
                                    bufferController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          'Accepted payment methods',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...methods.asMap().entries.map((entry) {
                          final index = entry.key;
                          final method = entry.value;
                          final lockDefault =
                              method.name.toUpperCase() == 'CASH';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        method.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (method.extraFieldLabel != null &&
                                          method.extraFieldLabel!
                                              .trim()
                                              .isNotEmpty)
                                        Text(
                                          'Extra field: ${method.extraFieldLabel}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.black54),
                                        ),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => editExtraField(index),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Field'),
                                ),
                                IconButton(
                                  onPressed: lockDefault
                                      ? null
                                      : () {
                                          setState(() {
                                            methods.removeAt(index);
                                          });
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                methodNameController,
                                hintText: 'Add payment method',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _field(
                                methodExtraFieldController,
                                hintText: 'Extra field label (optional)',
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: addMethod,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Extra field label max: 28 characters.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              'QR code',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: pickQr,
                              icon: const Icon(Icons.qr_code_2),
                              label: Text(
                                qrImagePath == null ? 'Upload QR' : 'Change QR',
                              ),
                            ),
                          ],
                        ),
                        if (qrImagePath != null && qrImagePath!.isNotEmpty)
                          Text(
                            'QR ready: ${qrImagePath!.split('\\').last}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (isCreate && isPaymentStep)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        isPaymentStep = false;
                      });
                    },
                    child: const Text('Back'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final incentive = double.tryParse(
                      incentiveController.text.trim(),
                    );
                    final buffer = double.tryParse(
                      bufferController.text.trim(),
                    );

                    if (isCreate && !isPaymentStep) {
                      if (name.isEmpty || incentive == null || buffer == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Venue name, incentive, and buffer are required.',
                            ),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        isPaymentStep = true;
                      });
                      return;
                    }

                    if (name.isEmpty || incentive == null || buffer == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Venue name, incentive, and buffer are required.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (methods.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'At least one payment method is required.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (methods.any(
                      (method) => (method.extraFieldLabel?.length ?? 0) > 28,
                    )) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Extra field label must be 28 characters or less.',
                          ),
                        ),
                      );
                      return;
                    }

                    final cubit = context.read<SettingsCubit>();
                    if (isCreate) {
                      await cubit.createLocation(
                        name: name,
                        address: addressController.text.trim(),
                        contact: contactController.text.trim(),
                        incentivePercent: incentive,
                        bufferPercent: buffer,
                        qrImagePath: qrImagePath,
                        paymentMethods: methods,
                      );
                    } else {
                      await cubit.saveLocationConfiguration(
                        company: existing.copyWith(
                          name: name,
                          address: addressController.text.trim(),
                          contact: contactController.text.trim(),
                          incentivePercent: incentive,
                          bufferPercent: buffer,
                          qrImagePath: qrImagePath,
                        ),
                        paymentMethods: methods,
                      );
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isCreate && !isPaymentStep ? 'Next' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.grey,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    String? hintText,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
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
      ),
    );
  }
}
