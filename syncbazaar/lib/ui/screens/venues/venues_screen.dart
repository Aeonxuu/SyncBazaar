import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../bloc/settings/settings_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../models/company.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/user.dart';

/// Venues the bazaars are held at, and the commercial terms agreed with each.
///
/// Named "Location" until 2026-08-03, which undersold it: a venue row also
/// carries the incentive and buffer percentages that come off the payout and
/// the payment methods the POS will offer there. Nobody hunting for "where do
/// I enable GCash" was going to look under a word that sounds like an address.
class VenuesScreen extends StatefulWidget {
  const VenuesScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = widget.user.isAdminOrOwner;

    if (!canManage) {
      return const Center(child: Text('Access denied'));
    }

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final query = _search.text.trim().toLowerCase();
        final visible = state.companies
            .where(
              (company) =>
                  query.isEmpty ||
                  company.name.toLowerCase().contains(query) ||
                  company.address.toLowerCase().contains(query),
            )
            .toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Venues & Terms',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          // Says what a venue row carries, because the name
                          // "venue" only covers half of it -- the rates here
                          // come off every payout.
                          state.companies.isEmpty
                              ? 'Where you sell, and the terms agreed there'
                              : _describeScope(
                                  state.companies.length,
                                  visible.length,
                                ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openVenueEditor(context),
                    icon: const Icon(Icons.add, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    label: const Text('Add venue'),
                  ),
                ],
              ),
              if (state.companies.length > 4) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: theme.textTheme.bodyMedium,
                    decoration: _venueFieldDecoration(
                      hint: 'Search venue or address',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: state.companies.isEmpty
                    ? _emptyState(
                        context,
                        icon: Icons.storefront_outlined,
                        message:
                            'No venues yet. Add the first place you sell at.',
                      )
                    : visible.isEmpty
                    ? _emptyState(
                        context,
                        icon: Icons.search_off_outlined,
                        message: 'No venue matches that search.',
                      )
                    : GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 420,
                              // Fixed height rather than an aspect ratio: a
                              // ratio derives height from width, so the same
                              // card grows taller as the window widens and
                              // its padding becomes a function of the
                              // viewport.
                              mainAxisExtent: 188,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final company = visible[index];
                          return _VenueCard(
                            company: company,
                            methods:
                                state.locationPaymentMethodsByCompanyId[company
                                    .id] ??
                                const [],
                            onEdit: () => _openVenueEditor(
                              context,
                              existing: company,
                              existingMethods:
                                  state
                                      .locationPaymentMethodsByCompanyId[company
                                      .id] ??
                                  const [],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _describeScope(int total, int shown) {
    if (total == shown) {
      return '$total ${total == 1 ? 'venue' : 'venues'}';
    }
    return '$shown of $total shown';
  }

  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black45),
          ),
        ],
      ),
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

InputDecoration _venueFieldDecoration({required String hint}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      prefixIcon: const Icon(Icons.search, size: 18, color: Colors.black38),
      filled: true,
      fillColor: AppColors.inputFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );

/// One venue and the terms agreed with it.
///
/// A card rather than a list row, because a venue is not one fact: it has an
/// address, a contact, two rates that come off every payout, and the payment
/// methods the till will offer there. All of that used to be a single run-on
/// subtitle -- "Incentive 10.0% • Buffer 5.0% • Methods 2" -- which buried the
/// two numbers that matter mid-sentence and never showed the address at all.
class _VenueCard extends StatelessWidget {
  const _VenueCard({
    required this.company,
    required this.methods,
    required this.onEdit,
  });

  final Company company;
  final List<PaymentMethodMeta> methods;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (company.address.trim().isNotEmpty) company.address,
                        if (company.contact.trim().isNotEmpty) company.contact,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _VenueRowAction(onPressed: onEdit),
            ],
          ),
          const Spacer(),
          // The two rates get their own row, in the accent colour. They are
          // the reason this screen is called "& Terms": every payout is
          // computed from them, and in a sentence they read as trivia.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _VenueFact(
                  label: 'Incentive',
                  value: formatPercent(company.incentivePercent),
                  emphasise: true,
                ),
              ),
              Expanded(
                child: _VenueFact(
                  label: 'Buffer',
                  value: formatPercent(company.bufferPercent),
                  emphasise: true,
                ),
              ),
              Expanded(
                flex: 2,
                child: _VenueFact(
                  label: 'Takes',
                  value: methods.isEmpty
                      ? 'CASH'
                      : methods.map((m) => m.name).join(' · '),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Label above, value below — the same shape used in the bazaar and staff
/// dialogs, so a fact reads the same wherever it appears.
class _VenueFact extends StatelessWidget {
  const _VenueFact({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.black38,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: emphasise ? AppColors.primary : AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _VenueRowAction extends StatefulWidget {
  const _VenueRowAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_VenueRowAction> createState() => _VenueRowActionState();
}

class _VenueRowActionState extends State<_VenueRowAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        onPressed: widget.onPressed,
        tooltip: 'Edit venue',
        splashRadius: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        icon: Icon(
          Icons.edit_outlined,
          size: 18,
          color: _hovered ? AppColors.primary : Colors.black38,
        ),
      ),
    );
  }
}
