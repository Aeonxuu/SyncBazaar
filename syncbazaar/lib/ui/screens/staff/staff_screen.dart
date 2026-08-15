import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/staff/staff_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/user.dart';
import '../../widgets/confirmation_dialog.dart';
import '../dashboard/widgets/dashboard_section_card.dart';

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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Staff List',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_isAdmin)
                ElevatedButton.icon(
                  onPressed: () => _showUserDialog(context),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add user'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BlocBuilder<StaffCubit, List<AppUser>>(
              builder: (context, users) {
                final base = widget.currentUser.role == UserRole.owner
                    ? users.where((u) => u.role == UserRole.employee).toList()
                    : users;
                final visible = _selectedRole == 'ALL'
                    ? base
                    : base
                          .where(
                            (user) =>
                                user.role.name.toUpperCase() == _selectedRole,
                          )
                          .toList();

                return DashboardSectionCard(
                  title: 'Staff Directory',
                  trailing: SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('ALL')),
                        DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                        DropdownMenuItem(value: 'OWNER', child: Text('OWNER')),
                        DropdownMenuItem(
                          value: 'EMPLOYEE',
                          child: Text('EMPLOYEE'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedRole = value;
                        });
                      },
                    ),
                  ),
                  child: Column(
                    children: [
                      _headerRow(context),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      SizedBox(
                        height: 420,
                        child: ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final user = visible[index];
                            return _staffRow(context, user);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        Expanded(flex: 3, child: Text('Name', style: style)),
        Expanded(flex: 4, child: Text('Email', style: style)),
        Expanded(flex: 2, child: Text('Role', style: style)),
        Expanded(flex: 2, child: Text('Bazaars', style: style)),
        Expanded(flex: 3, child: Text('Actions', style: style)),
      ],
    );
  }

  Widget _staffRow(BuildContext context, AppUser user) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final assignedCount = user.role == UserRole.employee
        ? user.assignedEventIdsEffective.length
        : 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(user.name, style: textStyle)),
          Expanded(flex: 4, child: Text(user.email, style: textStyle)),
          Expanded(
            flex: 2,
            child: Text(user.role.name.toUpperCase(), style: textStyle),
          ),
          Expanded(
            flex: 2,
            // The count is the way in to the names. A bare number answers
            // "how many" and leaves "which" unanswered, and the ids behind it
            // were already loaded.
            child: assignedCount == 0
                ? Text('-', style: textStyle)
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
                              style: textStyle?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
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
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 4,
              children: [
                if (_isAdmin)
                  IconButton(
                    onPressed: () => _showUserDialog(context, user: user),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (_isAdmin)
                  IconButton(
                    onPressed: () => _deleteUser(context, user),
                    icon: const Icon(Icons.delete_outline_rounded),
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

  static String _date(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

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
