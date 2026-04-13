import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/sync/sync_cubit.dart';
import '../../models/user.dart';
import 'offline_indicator.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.user,
    required this.notificationCount,
    required this.onOpenNotifications,
    required this.onLogout,
  });

  final AppUser user;
  final int notificationCount;
  final VoidCallback onOpenNotifications;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      color: Colors.white,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BlocBuilder<SyncCubit, SyncState>(
                builder: (context, state) => OfflineIndicator(
                  isSyncing: state.isSyncing,
                  message: state.lastMessage,
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onOpenNotifications,
                      icon: Badge(
                        isLabelVisible: notificationCount > 0,
                        label: Text('$notificationCount'),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
