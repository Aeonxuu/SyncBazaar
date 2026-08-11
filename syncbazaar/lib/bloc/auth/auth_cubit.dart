import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/remote/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository) : super(const AuthState());

  final AuthRepository _authRepository;

  Future<void> restoreSession() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    final user = await _authRepository.restoreSession();
    emit(state.copyWith(user: user, isLoading: false));
  }

  /// Signs in, distinguishing a rejected password from an unreachable server.
  ///
  /// A null user means the API said no; an [ApiException] means it never
  /// answered. Collapsing both into "Invalid credentials." would send a cashier
  /// hunting for a typo when the real problem is that the stall has no signal.
  Future<void> login(String email, String password, bool rememberMe) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final user = await _authRepository.login(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );
      if (user == null) {
        emit(state.copyWith(isLoading: false, error: 'Invalid credentials.'));
        return;
      }
      emit(state.copyWith(user: user, isLoading: false));
    } on ApiException catch (error) {
      emit(state.copyWith(isLoading: false, error: error.message));
    }
  }

  Future<void> logout() async {
    await _authRepository.logout();
    emit(const AuthState());
  }
}
