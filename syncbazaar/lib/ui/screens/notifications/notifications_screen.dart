import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../bloc/notifications/notifications_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';
import '../../../models/notification.dart';

/// The destination behind the sidebar's Notifications row.
///
/// Replaces a hardcoded bell badge (`isAdminOrOwner ? 2 : 1`) that opened a
/// SnackBar with invented text, while the real [NotificationService] — which
/// `SyncService` has always written to — had no reader at all.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: BlocBuilder<NotificationsCubit, NotificationsState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(state: state),
              Expanded(
                child: state.isEmpty
                    ? const _EmptyState()
                    : _NotificationList(items: state.items),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final NotificationsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = state.unreadCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Notifications',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  switch ((state.items.length, unread)) {
                    (0, _) => 'Activity from syncs and approvals shows here',
                    (_, 0) => '${state.items.length} notice(s), all read',
                    _ => '$unread unread of ${state.items.length}',
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          // Only offered when it would do something — a permanently visible
          // "Mark all as read" on an already-read list is a dead control.
          if (unread > 0)
            TextButton.icon(
              onPressed: () => context.read<NotificationsCubit>().markAllRead(),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              label: const Text('Mark all as read'),
            ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.items});

  final List<AppNotification> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _NotificationRow(item: items[index]),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item});

  final AppNotification item;

  static const Map<String, IconData> _icons = {
    'sync': Icons.cloud_sync_outlined,
    'approval': Icons.pending_actions_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !item.read;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: unread
            ? () => context.read<NotificationsCubit>().markRead(item.id)
            : null,
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: unread ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: unread
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _icons[item.type] ?? Icons.notifications_outlined,
                  size: 17,
                  color: unread ? AppColors.primary : Colors.black38,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.text,
                        height: 1.4,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('MMM d, h:mm a').format(item.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              // The one unread marker. Bold text alone is ambiguous next to a
              // long message; a dot says "new" at a glance and disappears the
              // moment the row is opened.
              if (unread) ...[
                const SizedBox(width: 12),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 34,
            color: Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            'You are all caught up',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sync results and approval activity\nwill appear here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black45,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
