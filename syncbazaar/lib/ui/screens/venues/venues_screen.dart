import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/settings/settings_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/remote/api_client.dart';
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
                            onEdit: () =>
                                _openVenueEditor(context, existing: company),
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
  }) async {
    final cubit = context.read<SettingsCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_VenueDraft>(
      context: context,
      builder: (_) => _VenueEditorDialog(existing: existing),
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
        );
      } else {
        await cubit.saveLocation(
          company: existing.copyWith(
            name: result.name,
            address: result.address,
            contact: result.contact,
            incentivePercent: result.incentivePercent,
            bufferPercent: result.bufferPercent,
          ),
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
  });

  final String name;
  final String address;
  final String contact;
  final double incentivePercent;
  final double bufferPercent;
}

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
  const _VenueCard({required this.company, required this.onEdit});

  final Company company;
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
  const _VenueEditorDialog({required this.existing});

  final Company? existing;

  @override
  State<_VenueEditorDialog> createState() => _VenueEditorDialogState();
}

class _VenueEditorDialogState extends State<_VenueEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _contact;
  late final TextEditingController _incentive;
  late final TextEditingController _buffer;

  String? _nameError;
  String? _ratesError;

  /// The example the rates are previewed against. A round number, so the
  /// arithmetic stays legible rather than becoming the thing being read.
  static const double _previewSales = 10000;

  /// Long enough to say "Reference Number", short enough to fit the field's
  /// label on a till.
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

  void _submit() {
    if (!_validateDetails()) {
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
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: _detailsStep(theme),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                children: [
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
                    child: Text(_isCreate ? 'Add venue' : 'Save venue'),
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
}

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
