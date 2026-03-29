import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/staff/staff_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/user.dart';
import '../dashboard/widgets/dashboard_section_card.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  String _selectedRole = 'ALL';

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
              ElevatedButton.icon(
                onPressed: () {},
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
        Expanded(flex: 2, child: Text('Bazaar', style: style)),
        Expanded(flex: 3, child: Text('Actions', style: style)),
      ],
    );
  }

  Widget _staffRow(BuildContext context, AppUser user) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
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
            child: Text(user.assignedEventId?.toString() ?? '-', style: textStyle),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.block_outlined),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.lock_reset_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
