enum UserRole { admin, owner, employee }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.assignedEventId,
  });

  final int id;
  final String name;
  final String email;
  final UserRole role;
  final int? assignedEventId;

  bool get isAdminOrOwner => role == UserRole.admin || role == UserRole.owner;

  AppUser copyWith({
    int? id,
    String? name,
    String? email,
    UserRole? role,
    int? assignedEventId,
    bool clearAssignedEventId = false,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      assignedEventId: clearAssignedEventId
          ? null
          : (assignedEventId ?? this.assignedEventId),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    'assigned_event_id': assignedEventId,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    role: UserRole.values.firstWhere((r) => r.name == json['role']),
    assignedEventId: json['assigned_event_id'] as int?,
  );
}
