import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/auth_repository.dart';
import '../../models/user.dart';

class StaffCubit extends Cubit<List<AppUser>> {
  StaffCubit(this._authRepository) : super(const []);

  final AuthRepository _authRepository;

  Future<void> load() async {
    emit(await _authRepository.listUsers());
  }

  Future<void> addUser({
    required String name,
    required String email,
    required UserRole role,
    String? password,
  }) async {
    await _authRepository.addUser(
      name: name,
      email: email,
      role: role,
      password: password,
    );
    await load();
  }

  Future<void> updateUser({
    required int id,
    required String name,
    required String email,
    required UserRole role,
    String? password,
  }) async {
    await _authRepository.updateUser(
      id: id,
      name: name,
      email: email,
      role: role,
      password: password,
    );
    await load();
  }

  Future<void> deleteUser(int id) async {
    await _authRepository.deleteUser(id);
    await load();
  }

  Future<void> assignEmployeesToBazaar({
    required int eventId,
    required List<int> employeeIds,
  }) async {
    await _authRepository.assignEmployeesToBazaar(
      eventId: eventId,
      employeeIds: employeeIds,
    );
    await load();
  }
}
