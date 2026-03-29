import 'package:flutter_bloc/flutter_bloc.dart';

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

  Future<void> login(String email, String password, bool rememberMe) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    final user = await _authRepository.login(
      email: email,
      password: password,
      rememberMe: rememberMe,
    );
    if (user == null) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Invalid credentials. Use password 123456.',
        ),
      );
      return;
    }
    emit(state.copyWith(user: user, isLoading: false));
  }

  Future<void> logout() async {
    await _authRepository.logout();
    emit(const AuthState());
  }
}
