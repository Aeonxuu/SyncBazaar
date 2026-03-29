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
