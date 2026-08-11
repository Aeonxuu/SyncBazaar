import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/settings/settings_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/user.dart';

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
          return ListView(
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
              // Keyed by the loaded name so the field picks up the stored
              // value once the cubit's first load resolves, instead of
              // staying empty behind an already-built controller.
              _StoreProfileCard(
                key: ValueKey(state.storeName),
                storeName: state.storeName,
              ),
              const SizedBox(height: 16),
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
            ],
          );
        },
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
  const _StoreProfileCard({super.key, required this.storeName});

  final String storeName;

  @override
  State<_StoreProfileCard> createState() => _StoreProfileCardState();
}

class _StoreProfileCardState extends State<_StoreProfileCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.storeName);
    _focusNode = FocusNode();
    // Saving on blur as well as on submit: a cashier who types a name and
    // taps straight into the app would otherwise lose it silently.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _save();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value == widget.storeName) {
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
            'Printed at the top of every receipt, above the bazaar venue.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black45,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'e.g. SV KICKz',
              hintStyle: const TextStyle(color: Colors.black38),
              filled: true,
              fillColor: AppColors.inputFill,
              isDense: true,
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
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
