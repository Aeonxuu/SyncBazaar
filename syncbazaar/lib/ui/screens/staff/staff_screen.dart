import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/staff/staff_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';
import '../../../core/utils/formatters.dart';
import '../../widgets/app_dropdown.dart';
import '../../../data/remote/api_client.dart' show ApiException;
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

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class _StaffScreenState extends State<StaffScreen> {
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
                  // Owner or admin, not `_isAdmin` alone: the dialog this
                  // opens already handles an owner correctly (it restricts
                  // them to creating an Employee), but the button that
                  // reaches it was admin-only, so an owner could never get
                  // there at all.
                  if (widget.currentUser.isAdminOrOwner)
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
    // Cubit and messenger are captured from this outer, long-lived context
    // rather than read inside the dialog's own tree — the dialog's context
    // stops being safe to use the instant `Navigator.pop` runs, which is
    // before its exit animation actually finishes.
    final staffCubit = context.read<StaffCubit>();
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(
        user: user,
        currentUserRole: widget.currentUser.role,
        staffCubit: staffCubit,
        messenger: messenger,
      ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.user,
    required this.currentUserRole,
    required this.staffCubit,
    required this.messenger,
  });

  final AppUser? user;
  final UserRole currentUserRole;
  final StaffCubit staffCubit;
  final ScaffoldMessengerState messenger;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late UserRole _selectedRole;
  late final List<UserRole> _allowedRoles;

  bool _obscurePassword = true;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _saving = false;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?.name ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _passwordController = TextEditingController();
    _selectedRole = widget.user?.role ?? UserRole.employee;
    // An owner may only ever create/edit an employee — the backend itself
    // doesn't block a request setting role to owner, so this is the one
    // thing standing in the way. Only an admin sees the picker at all: with
    // a single allowed role there is nothing to choose, and showing a
    // one-item dropdown just to state it back is its own anti-pattern.
    _allowedRoles = widget.currentUserRole == UserRole.owner
        ? const [UserRole.employee]
        : UserRole.values;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? 'Name is required.' : null;
      _emailError = email.isEmpty
          ? 'Email is required.'
          : !_emailPattern.hasMatch(email)
          ? 'Enter a valid email address.'
          : null;
      _passwordError = (!_isEdit && password.isEmpty)
          ? 'Password is required.'
          : null;
      _formError = null;
    });
    if (_nameError != null || _emailError != null || _passwordError != null) {
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.staffCubit.updateUser(
          id: widget.user!.id,
          name: name,
          email: email,
          role: _selectedRole,
          password: password.isEmpty ? null : password,
        );
      } else {
        await widget.staffCubit.addUser(
          name: name,
          email: email,
          role: _selectedRole,
          password: password,
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = error.isOffline ? 'Cannot reach the server.' : error.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'Unable to save. Please try again.';
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    widget.messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Text(
          _isEdit
              ? 'User updated.'
              // The one thing this dialog cannot promise: the account
              // exists now, but the server refuses login until the new
              // hire enters the code it emails them. The staff list has no
              // way to read back whether that has happened yet — the
              // API's own employee-list response doesn't include a
              // verified flag — so naming the step here is the honest
              // substitute for a progress indicator.
              : '$name\'s account was created. They\'ll need to '
                    'verify their email before they can log in.',
        ),
        duration: const Duration(milliseconds: 4200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = _isEdit;
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.97, end: 1),
        duration: AppMotion.entrance,
        curve: AppMotion.easeOut,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 10, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'Edit user' : 'Add user',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context),
                      splashRadius: 18,
                      tooltip: 'Close',
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StaffFormField(
                      label: 'Name',
                      error: _nameError,
                      child: TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: _staffDialogFieldDecoration(
                          hint: 'Enter full name',
                          hasError: _nameError != null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _StaffFormField(
                      label: 'Email',
                      error: _emailError,
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: _staffDialogFieldDecoration(
                          hint: 'Enter email address',
                          hasError: _emailError != null,
                        ),
                      ),
                    ),
                    if (_allowedRoles.length > 1) ...[
                      const SizedBox(height: 14),
                      _StaffFormField(
                        label: 'Role',
                        child: AppDropdown<UserRole>(
                          options: _allowedRoles,
                          selected: _selectedRole,
                          labelOf: (role) => role.name.toUpperCase(),
                          hint: 'Select role',
                          onSelected: (role) =>
                              setState(() => _selectedRole = role),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _StaffFormField(
                      label: isEdit ? 'New password (optional)' : 'Password',
                      error: _passwordError,
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration:
                            _staffDialogFieldDecoration(
                              hint: isEdit
                                  ? 'Enter new password'
                                  : 'Enter password',
                              hasError: _passwordError != null,
                            ).copyWith(
                              suffixIcon: IconButton(
                                splashRadius: 16,
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: Colors.black45,
                                ),
                              ),
                            ),
                      ),
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Leave blank to keep the current password.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Colors.black45),
                      ),
                    ],
                    if (_formError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _formError!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.error),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primary.withValues(
                          alpha: 0.45,
                        ),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEdit ? 'Save' : 'Add'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    BazaarStatus.ongoing: AppColors.statusOngoing,
    BazaarStatus.upcoming: AppColors.statusUpcoming,
    BazaarStatus.ended: AppColors.statusEnded,
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

/// Label above input, error below — the Add/Edit user dialog's field
/// recipe, matching `_FormField` in the product form.
class _StaffFormField extends StatelessWidget {
  const _StaffFormField({required this.label, required this.child, this.error});

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 6),
        child,
        AnimatedSize(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          alignment: Alignment.topLeft,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      fontSize: 11.5,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Flat gray fill, radius 8, purple focus border, red on error — this
/// dialog's own field recipe (see `_fieldDecoration` in
/// `inventory_screen.dart` for the same shape elsewhere in the app).
InputDecoration _staffDialogFieldDecoration({
  required String hint,
  bool hasError = false,
}) {
  const radius = BorderRadius.all(Radius.circular(8));
  OutlineInputBorder border(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: radius,
      borderSide: color == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black38),
    isDense: true,
    filled: true,
    fillColor: AppColors.inputFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(hasError ? AppColors.error : Colors.transparent, 1),
    enabledBorder: border(hasError ? AppColors.error : Colors.transparent, 1),
    focusedBorder: border(hasError ? AppColors.error : AppColors.primary, 1.5),
  );
}

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
