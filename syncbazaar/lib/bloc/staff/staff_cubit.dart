import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/user.dart';

class StaffCubit extends Cubit<List<AppUser>> {
  StaffCubit()
    : super(const [
        AppUser(
          id: 1,
          name: 'Admin Demo',
          email: 'admin@syncbazaar.com',
          role: UserRole.admin,
        ),
        AppUser(
          id: 2,
          name: 'Owner Demo',
          email: 'owner@syncbazaar.com',
          role: UserRole.owner,
        ),
        AppUser(
          id: 3,
          name: 'Employee Demo',
          email: 'employee@syncbazaar.com',
          role: UserRole.employee,
          assignedEventId: 1,
        ),
      ]);
}
