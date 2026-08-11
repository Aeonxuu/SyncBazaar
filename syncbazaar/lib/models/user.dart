enum UserRole { admin, owner, employee }

/// Translates between this app's role names and the two-letter codes the API
/// stores (`users.User.ROLE_*` on the backend).
///
/// Kept as a mapping rather than renaming the enum: `role.name` is already
/// written into `shared_preferences` by [AppUser.toJson] and read back by
/// sessions saved before the backend existed, and it reads better everywhere it
/// appears in the UI.
extension UserRoleApiCode on UserRole {
  String get apiCode => switch (this) {
    UserRole.admin => 'AD',
    UserRole.owner => 'OW',
    UserRole.employee => 'EM',
  };
}

/// Falls back to [UserRole.employee] for an unrecognised code, matching the
/// server's own default and failing closed: an unknown role gets the fewest
/// permissions rather than the most.
UserRole userRoleFromApiCode(String? code) => switch (code?.toUpperCase()) {
  'AD' => UserRole.admin,
  'OW' => UserRole.owner,
  _ => UserRole.employee,
};

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
    final shouldClearAssignments =
        clearAssignedEventId || clearAssignedEventIds;
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

  /// Builds a user from `POST /api/auth/login/`.
  ///
  /// [email] is passed in because the login response does not echo it back —
  /// it returns `user_id`, `role`, `name`, `vendor_id`, `vendor_name` — and the
  /// address the cashier typed is the one they signed in with.
  ///
  /// Event assignments are absent here by design: the server keeps them in
  /// `EventAssignment`, reachable at `/api/bazaar/event/<id>/assignment/`. Until
  /// that endpoint is wired, an employee signing in against the real API has no
  /// assigned events.
  factory AppUser.fromLoginResponse(
    Map<String, dynamic> json, {
    required String email,
  }) => AppUser(
    id: (json['user_id'] as num).toInt(),
    name: (json['name'] as String?)?.trim().isNotEmpty == true
        ? json['name'] as String
        : email,
    email: email,
    role: userRoleFromApiCode(json['role'] as String?),
  );

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
