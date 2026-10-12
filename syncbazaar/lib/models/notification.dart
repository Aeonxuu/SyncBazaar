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

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
    'read': read,
  };

  /// Null for a record that cannot be read, so one damaged entry is dropped
  /// rather than taking the whole list with it.
  static AppNotification? tryFromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final id = raw['id'];
    final type = raw['type'];
    final message = raw['message'];
    final createdAt = DateTime.tryParse('${raw['createdAt']}');
    if (id is! int || type is! String || message is! String) {
      return null;
    }
    if (createdAt == null) {
      return null;
    }
    return AppNotification(
      id: id,
      type: type,
      message: message,
      createdAt: createdAt,
      read: raw['read'] == true,
    );
  }
}
