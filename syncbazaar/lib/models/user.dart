enum UserRole { admin, owner, employee }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.assignedEventId,
    this.assignedEventIds = const [],
  });

  final int id;
  final String name;
  final String email;
  final UserRole role;
  final int? assignedEventId;
  final List<int> assignedEventIds;

  List<int> get assignedEventIdsEffective {
    if (assignedEventIds.isNotEmpty) {
      return assignedEventIds;
    }
    if (assignedEventId != null) {
      return [assignedEventId!];
    }
    return const [];
  }

  bool get isAdminOrOwner => role == UserRole.admin || role == UserRole.owner;

  AppUser copyWith({
    int? id,
    String? name,
    String? email,
    UserRole? role,
    int? assignedEventId,
    List<int>? assignedEventIds,
    bool clearAssignedEventId = false,
    bool clearAssignedEventIds = false,
  }) {
    final shouldClearAssignments = clearAssignedEventId || clearAssignedEventIds;
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      assignedEventId: shouldClearAssignments
          ? null
          : (assignedEventId ?? this.assignedEventId),
      assignedEventIds: shouldClearAssignments
          ? const []
          : List<int>.from(assignedEventIds ?? this.assignedEventIds),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    'assigned_event_id': assignedEventId,
    'assigned_event_ids': assignedEventIds,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    role: UserRole.values.firstWhere((r) => r.name == json['role']),
    assignedEventId: json['assigned_event_id'] as int?,
    assignedEventIds: ((json['assigned_event_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
  );
}
