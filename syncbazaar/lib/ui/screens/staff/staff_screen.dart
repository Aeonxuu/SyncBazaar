import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/staff/staff_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/user.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/selectable_option_button.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  String _selectedRole = 'ALL';

  /// Bazaars by id, so a count can become names. Staff carry the ids their
  /// assignments resolve to and nothing else -- an id is not an answer to
  /// "which bazaars is Via on?".
  Map<int, BazaarEvent> _eventsById = const {};

  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The repository is resolved before the await, not after it -- reaching
    // through the context once the future has completed is what the analyzer
    // objects to, and rightly.
    final repository = context.read<EventRepository>();
    Future.microtask(() async {
      final events = await repository.listAll();
      if (!mounted) return;
      setState(() {
        _eventsById = {for (final event in events) event.id: event};
      });
    });
  }

  /// One employee's bazaars, soonest first.
  ///
  /// An id with no bazaar behind it is dropped rather than rendered as a
  /// placeholder: it means another vendor's event, or one since deleted, and
  /// "Bazaar #14" answers nothing.
  List<BazaarEvent> _bazaarsFor(AppUser user) {
    return [
      for (final id in user.assignedEventIdsEffective)
        if (_eventsById[id] != null) _eventsById[id]!,
    ]..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Future<void> _showAssignments(AppUser user) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _EmployeeBazaarsDialog(employee: user, bazaars: _bazaarsFor(user)),
    );
  }

  bool get _isAdmin => widget.currentUser.role == UserRole.admin;

  @override
  Widget build(BuildContext context) {
    if (widget.currentUser.role == UserRole.employee) {
      return const Center(child: Text('Access denied'));
    }
    final theme = Theme.of(context);

    return BlocBuilder<StaffCubit, List<AppUser>>(
      builder: (context, users) {
        // An owner manages employees only, so the role filter would be a
        // control with one possible answer. It is shown to admins alone.
        final base = widget.currentUser.role == UserRole.owner
            ? users.where((u) => u.role == UserRole.employee).toList()
            : users;
        final query = _search.text.trim().toLowerCase();
        final visible = base
            .where(
              (user) =>
                  _selectedRole == 'ALL' ||
                  user.role.name.toUpperCase() == _selectedRole,
            )
            .where(
              (user) =>
                  query.isEmpty ||
                  user.name.toLowerCase().contains(query) ||
                  user.email.toLowerCase().contains(query),
            )
            .toList();

        return Padding(
          // 24 all round: this is a top-level screen, and the gutter is the
          // same in both axes.
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staff',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          // Says the scope, so the list below never has to be
                          // counted to know whether it is all of them.
                          _describeScope(base.length, visible.length),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isAdmin)
                    ElevatedButton.icon(
                      onPressed: () => _showUserDialog(context),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      label: const Text('Add user'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  ConstrainedBox(
                    // Capped rather than stretched: a search field the width
                    // of a desk is harder to aim at, not easier.
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        style: theme.textTheme.bodyMedium,
                        decoration: _staffFieldDecoration(
                          hint: 'Search name or email',
                        ),
                      ),
                    ),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(width: 12),
                    // Four options, always visible: recognition beats recall,
                    // and a dropdown hides three of them behind a tap.
                    for (final role in const [
                      'ALL',
                      'ADMIN',
                      'OWNER',
                      'EMPLOYEE',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SelectableOptionButton(
                          label: role,
                          isSelected: _selectedRole == role,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          onTap: () => setState(() => _selectedRole = role),
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEDEDF1)),
                  ),
                  child: visible.isEmpty
                      ? _emptyState(context, base.isEmpty)
                      : Column(
                          children: [
                            _headerRow(context),
                            const Divider(height: 1, color: Color(0xFFEDEDF1)),
                            Expanded(
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: Color(0xFFF3F3F6),
                                ),
                                itemBuilder: (context, index) =>
                                    _staffRow(context, visible[index]),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _describeScope(int total, int shown) {
    if (total == shown) {
      return '$total ${total == 1 ? 'person' : 'people'}';
    }
    return '$shown of $total shown';
  }

  Widget _emptyState(BuildContext context, bool noStaffAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noStaffAtAll ? Icons.group_outlined : Icons.search_off_outlined,
              size: 28,
              color: Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              noStaffAtAll
                  ? 'No staff yet. Add someone to get started.'
                  : 'Nobody matches that search.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.black38,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('NAME', style: style)),
          Expanded(flex: 2, child: Text('ROLE', style: style)),
          Expanded(flex: 2, child: Text('BAZAARS', style: style)),
          if (_isAdmin) const SizedBox(width: 80) else const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _staffRow(BuildContext context, AppUser user) {
    final theme = Theme.of(context);
    final assignedCount = user.role == UserRole.employee
        ? user.assignedEventIdsEffective.length
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            // Name over email in one column rather than two. They identify
            // the same person, so splitting them spends a column heading on
            // saying so.
            child: Row(
              children: [
                _StaffAvatar(name: user.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 2, child: _RoleBadge(role: user.role)),
          Expanded(
            flex: 2,
            // The count is the way in to the names. A bare number answers
            // "how many" and leaves "which" unanswered, and the ids behind it
            // were already loaded.
            child: assignedCount == 0
                ? Text(
                    user.role == UserRole.employee ? 'None' : '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black38,
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () => _showAssignments(user),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$assignedCount',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          if (_isAdmin)
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _StaffRowAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    hoverColor: AppColors.primary,
                    onPressed: () => _showUserDialog(context, user: user),
                  ),
                  _StaffRowAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    hoverColor: AppColors.error,
                    onPressed: () => _deleteUser(context, user),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(BuildContext context, AppUser user) async {
    final approved = await showConfirmationDialog(
      context: context,
      title: 'Delete User',
      message: 'Delete ${user.name}?',
      confirmLabel: 'Delete',
      tone: ConfirmationTone.destructive,
    );
    if (approved != true || !context.mounted) {
      return;
    }
    await context.read<StaffCubit>().deleteUser(user.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('User deleted.')));
  }

  Future<void> _showUserDialog(BuildContext context, {AppUser? user}) async {
    final isEdit = user != null;
    final nameController = TextEditingController(text: user?.name ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    UserRole selectedRole = user?.role ?? UserRole.employee;
    final allowedRoles = widget.currentUser.role == UserRole.owner
        ? const [UserRole.employee]
        : UserRole.values;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return MediaQuery.removeViewInsets(
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          context: dialogContext,
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isEdit ? 'Edit user' : 'Add user',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _fieldLabel(context, 'Name'),
                        const SizedBox(height: 4),
                        TextField(
                          controller: nameController,
                          decoration: _dialogFieldDecoration('Enter full name'),
                        ),
                        const SizedBox(height: 8),
                        _fieldLabel(context, 'Email'),
                        const SizedBox(height: 4),
                        TextField(
                          controller: emailController,
                          decoration: _dialogFieldDecoration(
                            'Enter email address',
                          ),
                        ),
                        const SizedBox(height: 8),
                        _fieldLabel(context, 'Role'),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<UserRole>(
                          initialValue: selectedRole,
                          items: allowedRoles
                              .map(
                                (role) => DropdownMenuItem<UserRole>(
                                  value: role,
                                  child: Text(role.name.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              selectedRole = value;
                            });
                          },
                          decoration: _dialogFieldDecoration('Select role'),
                        ),
                        const SizedBox(height: 8),
                        _fieldLabel(
                          context,
                          isEdit ? 'New password (optional)' : 'Password',
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration:
                              _dialogFieldDecoration(
                                isEdit
                                    ? 'Enter new password'
                                    : 'Enter password',
                              ).copyWith(
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setDialogState(() {
                                      obscurePassword = !obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 18,
                                  ),
                                ),
                              ),
                        ),
                        if (isEdit) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Leave password blank to keep current password.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.black45,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(38),
                                  foregroundColor: const Color(0xFFC62828),
                                  side: const BorderSide(
                                    color: Color(0xFFC62828),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                label: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  final email = emailController.text.trim();
                                  final password = passwordController.text
                                      .trim();
                                  if (name.isEmpty || email.isEmpty) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Name and email are required.',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  if (!_emailPattern.hasMatch(email)) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please enter a valid email address.',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  if (!isEdit && password.isEmpty) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Password is required for new users.',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  try {
                                    if (!mounted) {
                                      return;
                                    }
                                    final staffCubit = this.context
                                        .read<StaffCubit>();

                                    if (isEdit) {
                                      await staffCubit.updateUser(
                                        id: user.id,
                                        name: name,
                                        email: email,
                                        role: selectedRole,
                                        password: password.isEmpty
                                            ? null
                                            : password,
                                      );
                                    } else {
                                      await staffCubit.addUser(
                                        name: name,
                                        email: email,
                                        role: selectedRole,
                                        password: password,
                                      );
                                    }
                                  } catch (_) {
                                    if (!mounted) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Unable to save user. Please try again.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!dialogContext.mounted) {
                                    return;
                                  }
                                  Navigator.pop(dialogContext);
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        isEdit
                                            ? 'User updated.'
                                            : 'User added.',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(38),
                                  backgroundColor: const Color(0xFF2E7D32),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                label: Text(isEdit ? 'Save' : 'Add'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.grey,
        fontWeight: FontWeight.w500,
        fontSize: 11,
      ),
    );
  }

  InputDecoration _dialogFieldDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      filled: true,
      fillColor: const Color(0xFFF5F1FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

/// Which bazaars one employee works.
///
/// The Staff table showed a count, which answers "how many" and leaves the
/// question anybody actually has -- "is Via free next weekend?" -- unanswered.
/// Grouped by whether the bazaar is still to come, since that is the split
/// that decides whether the answer matters.
class _EmployeeBazaarsDialog extends StatelessWidget {
  const _EmployeeBazaarsDialog({required this.employee, required this.bazaars});

  final AppUser employee;
  final List<BazaarEvent> bazaars;

  static const Map<BazaarStatus, Color> _statusColors = {
    BazaarStatus.ongoing: Color(0xFF2E7D32),
    BazaarStatus.upcoming: Color(0xFFB45309),
    BazaarStatus.ended: AppColors.error,
  };

  static String _date(DateTime value) => formatDate(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = bazaars
        .where((b) => b.status != BazaarStatus.ended)
        .toList();
    final past = bazaars.where((b) => b.status == BazaarStatus.ended).toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          employee.email,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDF1)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bazaars.isEmpty)
                      Text(
                        'Not assigned to any bazaar.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                        ),
                      ),
                    if (current.isNotEmpty) ...[
                      const _StaffSectionLabel('Working now and next'),
                      const SizedBox(height: 8),
                      for (final bazaar in current)
                        _BazaarLine(
                          bazaar: bazaar,
                          color:
                              _statusColors[bazaar.status] ?? AppColors.error,
                          formatDate: _date,
                        ),
                    ],
                    if (current.isNotEmpty && past.isNotEmpty)
                      const SizedBox(height: 20),
                    if (past.isNotEmpty) ...[
                      const _StaffSectionLabel('Finished'),
                      const SizedBox(height: 8),
                      for (final bazaar in past)
                        _BazaarLine(
                          bazaar: bazaar,
                          color:
                              _statusColors[bazaar.status] ?? AppColors.error,
                          formatDate: _date,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffSectionLabel extends StatelessWidget {
  const _StaffSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.black38,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

class _BazaarLine extends StatelessWidget {
  const _BazaarLine({
    required this.bazaar,
    required this.color,
    required this.formatDate,
  });

  final BazaarEvent bazaar;
  final Color color;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bazaar.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDate(bazaar.startDate)} – '
                  '${formatDate(bazaar.endDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              bazaar.status.name.toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _staffFieldDecoration({required String hint}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      prefixIcon: const Icon(Icons.search, size: 18, color: Colors.black38),
      filled: true,
      fillColor: AppColors.inputFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );

/// A person's initials, as a stand-in for a photo the app does not have.
///
/// Not decoration: a column of identically-weighted names is hard to scan, and
/// an anchor at a fixed x gives the eye somewhere to land per row.
class _StaffAvatar extends StatelessWidget {
  const _StaffAvatar({required this.name});

  final String name;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _initials,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The role as a badge rather than as a word in the same weight as everything
/// else. It labels rather than states, so it reads as a tag.
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final UserRole role;

  static const Map<UserRole, Color> _colors = {
    UserRole.admin: Color(0xFF6B21A8),
    UserRole.owner: Color(0xFF1D4ED8),
    UserRole.employee: Color(0xFF475569),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[role] ?? const Color(0xFF475569);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          role.name.toUpperCase(),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

/// Rests at black38, animates to its semantic colour on hover.
///
/// Keeps a list of rows from looking hazardous while still warning at the
/// moment of intent — the same treatment the category rows use.
class _StaffRowAction extends StatefulWidget {
  const _StaffRowAction({
    required this.icon,
    required this.tooltip,
    required this.hoverColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color hoverColor;
  final VoidCallback onPressed;

  @override
  State<_StaffRowAction> createState() => _StaffRowActionState();
}

class _StaffRowActionState extends State<_StaffRowAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        onPressed: widget.onPressed,
        tooltip: widget.tooltip,
        splashRadius: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        icon: Icon(
          widget.icon,
          size: 18,
          color: _hovered ? widget.hoverColor : Colors.black38,
        ),
      ),
    );
  }
}
