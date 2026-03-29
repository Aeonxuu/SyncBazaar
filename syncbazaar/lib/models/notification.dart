class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.createdAt,
    required this.read,
  });

  final int id;
  final String type;
  final String message;
  final DateTime createdAt;
  final bool read;
}
