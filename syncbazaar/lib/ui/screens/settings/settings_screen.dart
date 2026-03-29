import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

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
        final isAdmin = user.role == UserRole.admin;
        final isOwner = user.role == UserRole.owner;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Company Management'),
                    const SizedBox(height: 8),
                    if (user.role == UserRole.employee)
                      const Text('No access')
                    else
                      ...state.companies.map(
                        (c) => ListTile(
                          title: Text(c.name),
                          subtitle: Text(
                            'Incentive ${c.incentivePercent}% • Buffer ${c.bufferPercent}%',
                          ),
                          trailing: isAdmin
                              ? IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.edit_outlined),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('QR Code Upload (per company)'),
                    const SizedBox(height: 8),
                    if (!isAdmin)
                      Text(isOwner ? 'View only for Owner' : 'No access')
                    else
                      ElevatedButton(
                        onPressed: () async {
                          final picker = ImagePicker();
                          await picker.pickImage(source: ImageSource.gallery);
                          // TODO: plug image cropper for 1:1 cropping.
                          // TODO: plug real QR detection/validation service.
                        },
                        child: const Text('Upload Company QR'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
