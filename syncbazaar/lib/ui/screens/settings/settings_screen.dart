import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/settings/settings_cubit.dart';
import '../../../bloc/sync/sync_cubit.dart';
import '../../../models/user.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                title: const Text('Auto-sync on reconnect'),
                value: state.autoSync,
                onChanged: context.read<SettingsCubit>().updateAutoSync,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () => context.read<SyncCubit>().syncNow(),
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
            ),
          ],
        );
      },
    );
  }
}
