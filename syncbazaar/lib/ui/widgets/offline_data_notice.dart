import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';

/// Says that what is on screen came from storage, and when it was taken.
///
/// The figures underneath this are not merely old: a till that has missed
/// another device's sales is showing a number that is wrong, and the same bold
/// type as a live figure invites someone to act on it. The difference between
/// "the day's takings" and "the day's takings as this device last saw them" is
/// the sort of thing that ends an argument at closing time.
///
/// Deliberately a quiet line rather than a banner or a dialog. A cashier cannot
/// do anything about a missing signal, so interrupting them helps nobody; they
/// need to be able to find the answer when a total looks wrong, not to be
/// stopped every time they glance at the screen.
class OfflineDataNotice extends StatelessWidget {
  const OfflineDataNotice({super.key, required this.storedAt});

  /// When the copy being shown was fetched.
  final DateTime storedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.statusUpcoming.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 15,
            color: AppColors.statusUpcoming,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Offline. Showing saved figures from ${describeStoredAt(storedAt)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.statusUpcoming,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A time for today, a date and time for anything older.
  ///
  /// "9:14 PM" is enough while it is the same day and reads faster than a full
  /// date. Past midnight it stops being enough: a copy taken yesterday evening
  /// shown as "9:14 PM" looks like it was taken an hour ago.
  static String describeStoredAt(DateTime storedAt, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final sameDay =
        storedAt.year == today.year &&
        storedAt.month == today.month &&
        storedAt.day == today.day;

    final hour = storedAt.hour % 12 == 0 ? 12 : storedAt.hour % 12;
    final minute = storedAt.minute.toString().padLeft(2, '0');
    final meridiem = storedAt.hour < 12 ? 'AM' : 'PM';
    final time = '$hour:$minute $meridiem';

    if (sameDay) {
      return time;
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${storedAt.day} ${months[storedAt.month - 1]}, $time';
  }
}
