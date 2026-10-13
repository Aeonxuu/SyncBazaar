import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/auth_repository.dart';
import '../../models/user.dart';

class StaffCubit extends Cubit<List<AppUser>> {
  StaffCubit(this._authRepository) : super(const []);

  final AuthRepository _authRepository;

  /// True from the moment a load starts until it finishes, successfully or not.
  ///
  /// Separate from the list because an empty list cannot say whether nobody has
  /// been hired or the answer has not arrived yet, and the screen greeted
  /// everyone with "No staff yet" for as long as the request took.
  final ValueNotifier<bool> isLoading = ValueNotifier(false);

  Future<void> load() async {
    isLoading.value = true;
    try {
      emit(await _authRepository.listUsers());
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Future<void> close() {
    isLoading.dispose();
    return super.close();
  }

  Future<void> addUser({
    required String name,
    required String email,
    required UserRole role,
    DateTime? dateHired,
  }) async {
    await _authRepository.addUser(
      name: name,
      email: email,
      role: role,
      dateHired: dateHired,
    );
    await load();
  }

  Future<void> updateUser({
    required int id,
    required String name,
    required String email,
    DateTime? dateHired,
  }) async {
    await _authRepository.updateUser(
      id: id,
      name: name,
      email: email,
      dateHired: dateHired,
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
