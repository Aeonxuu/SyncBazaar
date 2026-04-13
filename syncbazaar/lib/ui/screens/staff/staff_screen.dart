import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/staff/staff_cubit.dart';
import '../../../core/constants/colors.dart';
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
                        .where((user) => user.role.name.toUpperCase() == _selectedRole)
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
                        DropdownMenuItem(value: 'EMPLOYEE', child: Text('EMPLOYEE')),
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
            child: Text(
              assignedCount == 0 ? '-' : '$assignedCount',
              style: textStyle,
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
    );
    if (approved != true || !context.mounted) {
      return;
    }
    await context.read<StaffCubit>().deleteUser(user.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User deleted.')),
    );
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
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
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
                        decoration: _dialogFieldDecoration('Enter email address'),
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
                        decoration: _dialogFieldDecoration(
                          isEdit ? 'Enter new password' : 'Enter password',
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                                side: const BorderSide(color: Color(0xFFC62828)),
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
                                final password = passwordController.text.trim();
                                if (name.isEmpty || email.isEmpty) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Name and email are required.'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                if (!_emailPattern.hasMatch(email)) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please enter a valid email address.'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                if (!isEdit && password.isEmpty) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Password is required for new users.'),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                try {
                                  if (!mounted) {
                                    return;
                                  }
                                  final staffCubit = this.context.read<StaffCubit>();

                                  if (isEdit) {
                                    await staffCubit.updateUser(
                                      id: user.id,
                                      name: name,
                                      email: email,
                                      role: selectedRole,
                                      password: password.isEmpty ? null : password,
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
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Unable to save user. Please try again.'),
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
                                    content: Text(isEdit ? 'User updated.' : 'User added.'),
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
