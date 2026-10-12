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
    this.dateHired,
  });

  final int id;
  final String name;
  final String email;
  final UserRole role;
  final int? assignedEventId;
  final List<int> assignedEventIds;

  /// When they started. Null where nobody has recorded it, which is every
  /// account made before the field was editable.
  final DateTime? dateHired;

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
    DateTime? dateHired,
    bool clearDateHired = false,
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
      dateHired: clearDateHired ? null : (dateHired ?? this.dateHired),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    'assigned_event_id': assignedEventId,
    'assigned_event_ids': assignedEventIds,
    'date_hired': dateHired?.toIso8601String(),
  };

  /// Builds a user from `POST /api/auth/login/`.
  ///
  /// [email] is passed in because the login response does not echo it back —
  /// it returns `user_id`, `role`, `name`, `vendor_id`, `vendor_name` — and the
  /// address the cashier typed is the one they signed in with.
  ///
  /// `assigned_event_ids` matters more than it looks. The event list is scoped
  /// server-side for employees, but the client filters it again against these
  /// ids — so leaving them empty turned a correctly scoped list of four bazaars
  /// into none, and an employee signed in to an app with nothing to sell.
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
    assignedEventIds: ((json['assigned_event_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
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
    dateHired: parseApiDate(json['date_hired']),
  );

  /// The API's `date_hired` is a bare `YYYY-MM-DD`; parsed as a local date so
  /// it does not slide a day across a timezone.
  static DateTime? parseApiDate(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(raw);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// The form the API expects for a date field.
  static String toApiDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
