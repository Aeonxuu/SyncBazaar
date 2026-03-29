import 'package:flutter/material.dart';

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({
    super.key,
    required this.isSyncing,
    required this.message,
  });

  final bool isSyncing;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(isSyncing ? Icons.sync : Icons.cloud_done_outlined, size: 18),
        const SizedBox(width: 6),
        Text(message),
      ],
    );
  }
}
