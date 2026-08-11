class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.createdAt,
    required this.read,
  });

  final int id;

  /// Coarse category — `sync`, `approval`, and so on. Drives the leading icon
  /// so a list of notices is scannable by kind before it is read.
  final String type;

  final String message;
  final DateTime createdAt;
  final bool read;

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      type: type,
      message: message,
      createdAt: createdAt,
      read: read ?? this.read,
    );
  }
}
