import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/settings/settings_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/repositories/save_folder_repository.dart';
import '../../../models/user.dart';
import '../../widgets/confirmation_dialog.dart';
import 'widgets/info_document_dialog.dart';
import 'legal_documents.dart';

/// Whether this device can show the folder picker at all.
///
/// macOS only. Android/iOS get a folder choice through the system save sheet
/// on every export already (see `DocumentSaver.usesSaveSheet`), so a second
/// control here would just be a setting that does nothing. A web download has
/// no folder for the app to remember -- the browser owns that decision.
bool get _supportsSaveFolders =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// App preferences.
///
/// The "Sync now" button that used to sit here moved onto the sidebar's sync
/// status line: pressing in one place and watching the result in another is a
/// round trip for no reason, and two entry points to one action is one too
/// many. What is left is genuinely a preference.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: AppColors.background,
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return Center(
            child: ConstrainedBox(
              // Capped rather than left to stretch edge to edge: a switch
              // tile or document row at full tablet/desktop width reads as
              // sparse, with the label pinned far from the control it
              // describes. 720 is wide enough that nothing here wraps
              // awkwardly, narrow enough to still read as one column.
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Settings',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Preferences for this device',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // "General" groups the two single-card settings under one
                  // header instead of each floating unlabeled or, worse, each
                  // claiming a header of its own -- a heading over one card is a
                  // label, not a group (see DESIGN_GUIDELINES.md section 7's
                  // nav-rail rule, which applies here too). Neither card repeats
                  // this heading's job with a restated purpose line; they already
                  // carry their own.
                  const _SectionHeader(title: 'General'),
                  const SizedBox(height: 12),
                  // Keyed by the loaded name so the field picks up the stored
                  // value once the cubit's first load resolves, instead of
                  // staying empty behind an already-built controller.
                  _StoreProfileCard(
                    key: ValueKey('${state.storeName}|${state.storeNameError}'),
                    storeName: state.storeName,
                    isVendor: state.storeNameIsVendor,
                    // Renaming the vendor changes every receipt and every
                    // statement of account the business issues, so it is the
                    // owner's to do -- not a cashier's, mid-shift.
                    canEdit: user.isAdminOrOwner,
                    error: state.storeNameError,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      activeThumbColor: AppColors.primary,
                      title: Text(
                        'Auto-sync on reconnect',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Push pending sales and orders as soon as the connection '
                        'comes back. Sync manually any time from the status line '
                        'at the bottom of the menu.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                          height: 1.4,
                        ),
                      ),
                      value: state.autoSync,
                      onChanged: context.read<SettingsCubit>().updateAutoSync,
                    ),
                  ),
                  if (_supportsSaveFolders) ...[
                    const SizedBox(height: 24),
                    const _SectionHeader(
                      title: 'Save locations',
                      subtitle:
                          'Pick a folder once and future saves default there '
                          '-- change it any time.',
                    ),
                    const SizedBox(height: 12),
                    _SaveLocationsCard(saveFolders: state.saveFolders),
                  ],
                  const SizedBox(height: 24),
                  const _SectionHeader(
                    title: 'About',
                    subtitle:
                        'How this app handles your information, and answers to '
                        'common questions',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < settingsDocuments.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: AppColors.border),
                          _DocumentRow(document: settingsDocuments[i]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A section header, title plus optional one-line subtitle, shared by every
/// group on the screen so a new section can't drift into its own one-off
/// style. Subtitle is left off for a group whose cards already state their
/// own purpose (`General`) -- printing it twice would be the redundancy this
/// screen is trying to avoid, not a consistency win.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black45),
          ),
        ],
      ],
    );
  }
}

/// One tappable line opening a reference document.
///
/// A row rather than a card each: three documents as three cards would give
/// reading matter the same weight as the settings above them, which are things
/// a person came here to change.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document});

  final InfoDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => showInfoDocument(context: context, document: document),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    document.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    document.summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black45,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

/// The seller's own name, printed as the header of every receipt.
///
/// Separate from the venue list under "Venues & Terms": a `Company` there is
/// the mall hosting the bazaar, not the stall taking the money, and a receipt
/// has to name both.
///
/// A real [StatefulWidget] rather than a controller built inline, so the
/// controller is disposed — see section 10 of DESIGN_GUIDELINES.md.
class _StoreProfileCard extends StatefulWidget {
  const _StoreProfileCard({
    super.key,
    required this.storeName,
    required this.isVendor,
    required this.canEdit,
    this.error,
  });

  final String storeName;

  /// Whether this renames the vendor on the server or only this device.
  final bool isVendor;

  final bool canEdit;

  /// Why the last attempt did not save, or null.
  final String? error;

  @override
  State<_StoreProfileCard> createState() => _StoreProfileCardState();
}

class _StoreProfileCardState extends State<_StoreProfileCard> {
  /// Fits the sidebar and receipt header on one line without an ellipsis.
  static const int _maxLength = 14;

  late final TextEditingController _controller;
  bool _isDirty = false;

  /// Client-side validation problem with the text currently in the field, or
  /// null. Kept separate from [SettingsCubit.storeNameError] (a save the
  /// server rejected) so typing to fix one doesn't wait on a round trip to
  /// clear the other.
  String? _localError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.storeName)
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final isDirty = _controller.text.trim() != widget.storeName;
    if (isDirty != _isDirty || _localError != null) {
      setState(() {
        _isDirty = isDirty;
        _localError = null;
      });
    }
  }

  Future<void> _attemptSave() async {
    if (!widget.canEdit || !_isDirty) {
      return;
    }
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _localError = "Store name can't be empty.");
      return;
    }

    // Read back exactly what will change, and where it will show up --
    // renaming the vendor touches every receipt and statement of account,
    // so the confirmation names the consequence, not just the arithmetic of
    // "are you sure".
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Change store name?',
      message: widget.isVendor
          ? 'The store name will change to "$value". This renames your '
                'business on every receipt and statement of account.'
          : 'The store name will change to "$value". This updates the name '
                'printed at the top of every receipt.',
      confirmLabel: 'Save',
    );
    if (!confirmed || !mounted) {
      return;
    }
    context.read<SettingsCubit>().updateStoreName(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Store name',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.isVendor
                // Says where it goes, because it is no longer a setting on
                // this tablet -- it renames the business everywhere.
                ? 'Your business name. Printed on every receipt and on the '
                      'statement of account each venue is paid against. '
                      'Renaming here renames it for everyone.'
                : 'Printed at the top of every receipt, above the bazaar '
                      'venue.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black45,
              height: 1.4,
            ),
          ),
          if (!widget.canEdit) ...[
            const SizedBox(height: 12),
            _ReadOnlyName(name: widget.storeName),
          ] else ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final effectiveError = _localError ?? widget.error;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _controller,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              maxLength: _maxLength,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(_maxLength),
                              ],
                              onSubmitted: (_) => _attemptSave(),
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                hintText: 'e.g. SV KICKz',
                                hintStyle: const TextStyle(
                                  color: Colors.black38,
                                ),
                                filled: true,
                                fillColor: AppColors.inputFill,
                                isDense: true,
                                // Default counter renders below the field,
                                // widening the row's footprint; folded into
                                // `suffix` instead so it sits inside the
                                // field on the right, next to the text it's
                                // counting.
                                counterText: '',
                                suffix:
                                    ValueListenableBuilder<TextEditingValue>(
                                      valueListenable: _controller,
                                      builder: (context, value, _) => Text(
                                        '${value.text.length}/$_maxLength',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: Colors.black38),
                                      ),
                                    ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
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
                                  borderSide: BorderSide(
                                    color: effectiveError == null
                                        ? AppColors.primary
                                        : AppColors.error,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: _isDirty ? _attemptSave : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.primary
                                  .withValues(alpha: 0.4),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                    if (effectiveError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 15,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              effectiveError,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// One row per export kind, each with its own remembered folder.
class _SaveLocationsCard extends StatelessWidget {
  const _SaveLocationsCard({required this.saveFolders});

  final Map<SaveDocumentKind, String> saveFolders;

  static const _kinds = [
    (SaveDocumentKind.soa, 'Statement of Account'),
    (SaveDocumentKind.orderList, 'Order List'),
    (SaveDocumentKind.receipts, 'Receipts'),
    (SaveDocumentKind.inventory, 'Inventory Export'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < _kinds.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _SaveLocationRow(
              kind: _kinds[i].$1,
              label: _kinds[i].$2,
              folder: saveFolders[_kinds[i].$1],
            ),
          ],
        ],
      ),
    );
  }
}

class _SaveLocationRow extends StatelessWidget {
  const _SaveLocationRow({
    required this.kind,
    required this.label,
    required this.folder,
  });

  final SaveDocumentKind kind;
  final String label;
  final String? folder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<SettingsCubit>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  folder ?? 'Not set -- you will be asked every time',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (folder != null)
            IconButton(
              tooltip: 'Forget this folder',
              icon: const Icon(Icons.close, size: 18, color: Colors.black45),
              onPressed: () => cubit.clearSaveFolder(kind),
            ),
          TextButton(
            onPressed: () => cubit.pickSaveFolder(kind),
            child: Text(folder == null ? 'Choose folder' : 'Change'),
          ),
        ],
      ),
    );
  }
}

/// The business name as a cashier sees it: legible, but plainly not a field.
///
/// Shown rather than a disabled TextField, which reads as broken -- a greyed
/// box invites tapping and says nothing about why it will not take.
class _ReadOnlyName extends StatelessWidget {
  const _ReadOnlyName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.lock_outline,
            size: 15,
            color: Colors.black.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}
