import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../bloc/settings/settings_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';
import '../../../data/remote/api_client.dart';
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
    final cubit = context.read<SettingsCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_VenueDraft>(
      context: context,
      builder: (_) => _VenueEditorDialog(
        existing: existing,
        existingMethods: existingMethods,
      ),
    );
    if (result == null) {
      return;
    }

    // Wrapped because it was not: a rejected save threw out of this method
    // into a button's async callback, where an uncaught error is simply
    // nothing happening. The venue did not appear and nothing said why.
    try {
      if (existing == null) {
        await cubit.createLocation(
          name: result.name,
          address: result.address,
          contact: result.contact,
          incentivePercent: result.incentivePercent,
          bufferPercent: result.bufferPercent,
          qrImagePath: result.qrImagePath,
          paymentMethods: result.methods,
        );
      } else {
        await cubit.saveLocationConfiguration(
          company: existing.copyWith(
            name: result.name,
            address: result.address,
            contact: result.contact,
            incentivePercent: result.incentivePercent,
            bufferPercent: result.bufferPercent,
            qrImagePath: result.qrImagePath,
          ),
          paymentMethods: result.methods,
        );
      }
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.isOffline
                ? 'Cannot reach the server, so ${result.name} was not saved.'
                : '${result.name} could not be saved. ${error.message}',
          ),
        ),
      );
    }
  }
}

/// What the venue editor agreed to.
class _VenueDraft {
  const _VenueDraft({
    required this.name,
    required this.address,
    required this.contact,
    required this.incentivePercent,
    required this.bufferPercent,
    required this.qrImagePath,
    required this.methods,
  });

  final String name;
  final String address;
  final String contact;
  final double incentivePercent;
  final double bufferPercent;
  final String? qrImagePath;
  final List<PaymentMethodMeta> methods;
}

/// The hairline shared by every control on the add-a-method row.
const Color _venueControlBorder = Color(0xFFDCDCE3);

/// The filled style used by the stacked fields on the Details step, where a
/// field sits alone on its line and has nothing beside it to match.
InputDecoration _venuePlainDecoration({required String hint}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
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

/// Adding or editing a venue: what it is called, what it costs, and what the
/// till will accept there.
///
/// Two steps, both reachable in either mode. Editing used to open straight
/// onto payment methods with no way back, so a venue's name, address, contact
/// and both rates could be *saved* but never seen or changed -- the controllers
/// held the original values and wrote them back untouched.
class _VenueEditorDialog extends StatefulWidget {
  const _VenueEditorDialog({
    required this.existing,
    required this.existingMethods,
  });

  final Company? existing;
  final List<PaymentMethodMeta> existingMethods;

  @override
  State<_VenueEditorDialog> createState() => _VenueEditorDialogState();
}

class _VenueEditorDialogState extends State<_VenueEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _contact;
  late final TextEditingController _incentive;
  late final TextEditingController _buffer;
  final TextEditingController _methodName = TextEditingController();
  final TextEditingController _methodField = TextEditingController();

  late List<PaymentMethodMeta> _methods;
  String? _qrImagePath;
  int _step = 0;

  String? _nameError;
  String? _ratesError;
  String? _methodError;

  /// The example the rates are previewed against. A round number, so the
  /// arithmetic stays legible rather than becoming the thing being read.
  static const double _previewSales = 10000;

  /// Long enough to say "Reference Number", short enough to fit the field's
  /// label on a till.
  static const int _fieldLabelMax = 28;

  /// One height for every control on the add-a-method row.
  ///
  /// The button was pinned to 44 while the two fields took whatever their
  /// decoration worked out to, so three controls meant to read as one row
  /// stood at two different heights.
  static const double _controlHeight = 44;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _address = TextEditingController(text: existing?.address ?? '');
    _contact = TextEditingController(text: existing?.contact ?? '');
    _incentive = TextEditingController(
      text: existing == null ? '10' : _plain(existing.incentivePercent),
    );
    _buffer = TextEditingController(
      text: existing == null ? '10' : _plain(existing.bufferPercent),
    );
    _qrImagePath = existing?.qrImagePath;
    _methods = [
      if (widget.existingMethods.isNotEmpty)
        ...widget.existingMethods
      else
        const PaymentMethodMeta(name: 'CASH'),
    ];
  }

  static String _plain(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _contact.dispose();
    _incentive.dispose();
    _buffer.dispose();
    _methodName.dispose();
    _methodField.dispose();
    super.dispose();
  }

  double? get _incentiveValue => double.tryParse(_incentive.text.trim());
  double? get _bufferValue => double.tryParse(_buffer.text.trim());

  bool _validateDetails() {
    final name = _name.text.trim();
    final incentive = _incentiveValue;
    final buffer = _bufferValue;
    setState(() {
      _nameError = name.isEmpty ? 'A venue needs a name.' : null;
      _ratesError = (incentive == null || buffer == null)
          ? 'Both rates must be numbers.'
          : (incentive < 0 || buffer < 0)
          ? 'A rate cannot be negative.'
          : (incentive + buffer > 100)
          ? 'Together these take more than the whole sale.'
          : null;
    });
    return _nameError == null && _ratesError == null;
  }

  void _addMethod() {
    final name = _methodName.text.trim();
    final field = _methodField.text.trim();
    if (name.isEmpty) {
      setState(() => _methodError = 'Give the method a name.');
      return;
    }
    if (_methods.any((m) => m.name.toUpperCase() == name.toUpperCase())) {
      setState(() => _methodError = '$name is already accepted here.');
      return;
    }
    setState(() {
      _methods.add(
        PaymentMethodMeta(
          name: name,
          extraFieldLabel: field.isEmpty ? null : field,
        ),
      );
      _methodName.clear();
      _methodField.clear();
      _methodError = null;
    });
  }

  void _submit() {
    if (_step == 0) {
      if (_validateDetails()) {
        setState(() => _step = 1);
      }
      return;
    }
    // Details are validated on the way through, but an edit can land on step
    // two directly, so they are checked again rather than trusted.
    if (!_validateDetails()) {
      setState(() => _step = 0);
      return;
    }
    if (_methods.isEmpty) {
      setState(() => _methodError = 'A venue must accept at least one method.');
      return;
    }
    Navigator.pop(
      context,
      _VenueDraft(
        name: _name.text.trim(),
        address: _address.text.trim(),
        contact: _contact.text.trim(),
        incentivePercent: _incentiveValue!,
        bufferPercent: _bufferValue!,
        qrImagePath: _qrImagePath,
        methods: _methods,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isCreate ? 'Add venue' : 'Edit venue',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              // A completed step is tappable to revisit; forward movement is
              // what validation gates.
              child: Row(
                children: [
                  _VenueStep(
                    index: 1,
                    label: 'Details',
                    isCurrent: _step == 0,
                    isDone: _step > 0,
                    onTap: () => setState(() => _step = 0),
                  ),
                  const Expanded(
                    child: Divider(color: Color(0xFFEDEDF1), height: 1),
                  ),
                  _VenueStep(
                    index: 2,
                    label: 'Payment methods',
                    isCurrent: _step == 1,
                    isDone: false,
                    onTap: _step == 1 ? null : () => _submit(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: _step == 0 ? _detailsStep(theme) : _methodsStep(theme),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                children: [
                  if (_step == 1)
                    TextButton.icon(
                      onPressed: () => setState(() => _step = 0),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(_step == 0 ? 'Continue' : 'Save venue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsStep(ThemeData theme) {
    final incentive = _incentiveValue ?? 0;
    final buffer = _bufferValue ?? 0;
    final venueShare = _previewSales * (incentive + buffer) / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _VenueSectionLabel('Venue'),
        const SizedBox(height: 8),
        _VenueField(
          label: 'Name',
          controller: _name,
          hint: 'e.g. SM City Lucena',
          error: _nameError,
          onChanged: () => setState(() => _nameError = null),
        ),
        const SizedBox(height: 12),
        _VenueField(label: 'Address', controller: _address, hint: 'Optional'),
        const SizedBox(height: 12),
        _VenueField(label: 'Contact', controller: _contact, hint: 'Optional'),
        const SizedBox(height: 24),
        const _VenueSectionLabel('Terms'),
        const SizedBox(height: 4),
        Text(
          'Taken off every sale made at this venue.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _VenueField(
                label: 'Incentive %',
                controller: _incentive,
                hint: '10',
                numeric: true,
                onChanged: () => setState(() => _ratesError = null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _VenueField(
                label: 'Buffer %',
                controller: _buffer,
                hint: '5',
                numeric: true,
                onChanged: () => setState(() => _ratesError = null),
              ),
            ),
          ],
        ),
        if (_ratesError != null) ...[
          const SizedBox(height: 6),
          Text(
            _ratesError!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 12),
        // A percentage is abstract until it is money. This is the same
        // arithmetic the statement of account runs, on a round number.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                height: 1.4,
              ),
              children: [
                TextSpan(text: 'On ${formatPeso(_previewSales)} of sales, '),
                TextSpan(
                  text: formatPeso(venueShare),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' goes to the venue and '),
                TextSpan(
                  text: formatPeso(_previewSales - venueShare),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' is retained.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _methodsStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _VenueSectionLabel('Accepted at this venue'),
        const SizedBox(height: 4),
        Text(
          'What the till offers here. A method can ask the cashier for one '
          'extra detail, such as a reference number.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black45,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _methods.length; i++)
          _MethodRow(
            // Keyed by the method it shows: without this, removing a row
            // leaves the next one holding the removed row's controller and
            // therefore its text.
            key: ValueKey(_methods[i].name),
            method: _methods[i],
            // Cash is how a stall takes money when everything else fails, so
            // it is not removable.
            locked: _methods[i].name.toUpperCase() == 'CASH',
            onFieldChanged: (label) => setState(() {
              _methods[i] = PaymentMethodMeta(
                name: _methods[i].name,
                extraFieldLabel: label.trim().isEmpty ? null : label.trim(),
              );
            }),
            onRemove: () => setState(() => _methods.removeAt(i)),
            maxFieldLength: _fieldLabelMax,
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _VenueRowField(
                controller: _methodName,
                hint: 'e.g. GCASH',
                height: _controlHeight,
                capitalize: true,
                onChanged: () => setState(() => _methodError = null),
                onSubmitted: _addMethod,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _VenueRowField(
                controller: _methodField,
                hint: 'Asks for… (optional)',
                height: _controlHeight,
                maxLength: _fieldLabelMax,
                onSubmitted: _addMethod,
              ),
            ),
            const SizedBox(width: 8),
            // A plain box rather than an OutlinedButton. The button defaults
            // to a padded tap target, so it lays out taller than whatever
            // height it is given and cannot be matched to the fields beside
            // it -- which is why pinning all three to one SizedBox did not
            // make them equal.
            _AddMethodButton(height: _controlHeight, onPressed: _addMethod),
          ],
        ),
        if (_methodError != null) ...[
          const SizedBox(height: 6),
          Text(
            _methodError!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 24),
        const _VenueSectionLabel('Payment QR'),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final file = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                );
                if (file != null && mounted) {
                  setState(() => _qrImagePath = file.path);
                }
              },
              icon: const Icon(Icons.qr_code_2, size: 16),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFDCDCE3)),
                foregroundColor: AppColors.text,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              label: Text(_qrImagePath == null ? 'Upload QR' : 'Replace QR'),
            ),
            const SizedBox(width: 10),
            if (_qrImagePath != null)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 15,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Attached',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              Text(
                'None yet',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black38,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) => null;

class _VenueSectionLabel extends StatelessWidget {
  const _VenueSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.black38,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

/// Label, input, and the field's own error in one block.
///
/// Errors sit next to the input that caused them. They used to be SnackBars,
/// which name the problem at the bottom of the screen and leave the reader to
/// find which of five fields it belongs to.
class _VenueField extends StatelessWidget {
  const _VenueField({
    required this.label,
    required this.controller,
    required this.hint,
    this.error,
    this.numeric = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? error;
  final bool numeric;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged == null ? null : (_) => onChanged!(),
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: theme.textTheme.bodyMedium,
          decoration: _venuePlainDecoration(hint: hint).copyWith(
            enabledBorder: error == null
                ? null
                : OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.error),
                  ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class _VenueStep extends StatelessWidget {
  const _VenueStep({
    required this.index,
    required this.label,
    required this.isCurrent,
    required this.isDone,
    this.onTap,
  });

  final int index;
  final String label;
  final bool isCurrent;
  final bool isDone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = isCurrent || isDone;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : const Color(0xFFEDEDF1),
                shape: BoxShape.circle,
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : Colors.black45,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: active ? AppColors.primary : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One accepted payment method, with its extra field edited in place.
///
/// The label used to live behind a "Field" button opening a second dialog on
/// top of this one, to change one string.
class _MethodRow extends StatefulWidget {
  const _MethodRow({
    super.key,
    required this.method,
    required this.locked,
    required this.onFieldChanged,
    required this.onRemove,
    required this.maxFieldLength,
  });

  final PaymentMethodMeta method;
  final bool locked;
  final ValueChanged<String> onFieldChanged;
  final VoidCallback onRemove;
  final int maxFieldLength;

  @override
  State<_MethodRow> createState() => _MethodRowState();
}

class _MethodRowState extends State<_MethodRow> {
  /// Owned by the row rather than rebuilt in `build`. A controller created
  /// there is a new one every frame, so the cursor jumps to the start on each
  /// keystroke and the field cannot be typed into.
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: widget.method.extraFieldLabel ?? '');
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = widget.method;
    final locked = widget.locked;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              method.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _field,
              maxLength: widget.maxFieldLength,
              buildCounter: _noCounter,
              onChanged: widget.onFieldChanged,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: 'Asks for… (optional)',
                hintStyle: const TextStyle(color: Colors.black38),
                isDense: true,
                filled: true,
                // White inside a bordered row, so the two depths never read
                // as the same surface.
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: locked ? null : widget.onRemove,
            tooltip: locked ? 'Cash cannot be removed' : 'Remove',
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: locked ? Colors.black12 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Add control on the add-a-method row.
///
/// Built from a Container rather than an OutlinedButton so its height is
/// exactly what it is given. A material button carries a padded tap target
/// that lays out larger than any height set on it, which is what kept it
/// from matching the fields beside it however they were sized.
class _AddMethodButton extends StatefulWidget {
  const _AddMethodButton({required this.height, required this.onPressed});

  final double height;
  final VoidCallback onPressed;

  @override
  State<_AddMethodButton> createState() => _AddMethodButtonState();
}

class _AddMethodButtonState extends State<_AddMethodButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: AppMotion.feedback,
          curve: AppMotion.easeOut,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF2ECFC) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered ? AppColors.primary : _venueControlBorder,
            ),
          ),
          child: Text(
            'Add',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A text field on the add-a-method row.
///
/// The border is painted by a Container here, and the field inside carries no
/// decoration of its own. An InputDecorator sizes its outline from its content
/// and padding by rules that do not simply obey a height -- three attempts to
/// match it to the button beside it measured 44 in a headless test while
/// rendering visibly shorter on screen. A Container is exactly the height it
/// is given, which is the property this row needs.
class _VenueRowField extends StatefulWidget {
  const _VenueRowField({
    required this.controller,
    required this.hint,
    required this.height,
    this.maxLength,
    this.capitalize = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final double height;
  final int? maxLength;
  final bool capitalize;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  @override
  State<_VenueRowField> createState() => _VenueRowFieldState();
}

class _VenueRowFieldState extends State<_VenueRowField> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focus.hasFocus ? AppColors.primary : _venueControlBorder,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        maxLength: widget.maxLength,
        buildCounter: widget.maxLength == null ? null : _noCounter,
        textCapitalization: widget.capitalize
            ? TextCapitalization.characters
            : TextCapitalization.none,
        onChanged: widget.onChanged == null ? null : (_) => widget.onChanged!(),
        onSubmitted: widget.onSubmitted == null
            ? null
            : (_) => widget.onSubmitted!(),
        style: Theme.of(context).textTheme.bodyMedium,
        // Stripped bare: every visible edge belongs to the Container above.
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Colors.black38),
          isDense: true,
          filled: false,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}
