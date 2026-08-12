import '../../models/user.dart';

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.isRestoring = false,
    this.error,
  });

  final AppUser? user;

  /// A sign-in is in flight. The login screen shows this on its own button and
  /// stays mounted; nothing above it should swap the screen out.
  final bool isLoading;

  /// The saved session is being read at startup, before anything is on screen.
  ///
  /// Separate from [isLoading] because only this one justifies replacing the
  /// whole screen with a spinner. Sharing one flag meant a failed sign-in tore
  /// the login form down mid-attempt: the typed email and password went with
  /// it, and the rebuilt screen subscribed too late to ever see the error it
  /// was meant to report.
  final bool isRestoring;

  final String? error;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    AppUser? user,
    bool? isLoading,
    bool? isRestoring,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      isRestoring: isRestoring ?? this.isRestoring,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
