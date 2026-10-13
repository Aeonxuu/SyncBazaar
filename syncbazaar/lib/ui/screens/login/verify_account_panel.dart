import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/auth/auth_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/floating_label_text_field.dart';
import '../../widgets/otp_code_field.dart';

// Same shape as the one in login_screen.dart / staff_screen.dart's add/edit
// form -- duplicated rather than shared for the same reason those two are:
// there is nowhere all three already import from.
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

enum _VerifyStep { email, code, newPassword }

/// The self-service "confirm your account" flow: the email an account was
/// created with, the code emailed for it, and the password to sign in with
/// from now on -- the account has none until this runs.
///
/// Same shape as `login_screen.dart`'s forgot-password flow on purpose: one
/// step at a time, no pop-up dialog, and the same "a code-shaped failure
/// routes back to the code step" error handling. Both are "prove you own
/// this email, then set a password" under the hood, and someone who has
/// already used one of them should not have to learn a second shape for the
/// other.
///
/// One real difference: the email step here sends nothing. A code already
/// went out automatically when the account was created, so "Continue" just
/// moves on to entering it; "Resend code" on this same step is the escape
/// hatch for one that never arrived or already expired.
///
/// Talks to [AuthRepository] directly, and to [AuthCubit] only once, right
/// at the end, to sign in with the password just set -- there is no session
/// yet for anything before that.
class VerifyAccountPanel extends StatefulWidget {
  const VerifyAccountPanel({
    super.key,
    required this.initialEmail,
    required this.onDone,
  });

  final String initialEmail;

  /// Called with the email if the flow ends without a completed sign-in
  /// (e.g. a dropped connection right after verifying), so the ordinary
  /// sign-in form can pick up from there with the email already filled in
  /// rather than making them retype it.
  final ValueChanged<String> onDone;

  @override
  State<VerifyAccountPanel> createState() => _VerifyAccountPanelState();
}

class _VerifyAccountPanelState extends State<VerifyAccountPanel> {
  static const _resendCooldown = Duration(seconds: 30);

  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _VerifyStep _step = _VerifyStep.email;
  bool _busy = false;
  String? _error;
  String? _note;
  Timer? _cooldownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// A client-side cooldown on top of whatever the server enforces. It does
  /// not stop someone editing the request directly, but it stops an
  /// ordinary double-tap or an impatient retry from generating extra emails
  /// and extra load on the endpoint most exposed to abuse.
  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsLeft -= 1;
        if (_secondsLeft <= 0) {
          timer.cancel();
        }
      });
    });
  }

  /// Moves from the email step to the code step.
  ///
  /// No request here -- unlike the forgot-password flow, a code already
  /// exists: it went out the moment the account was created, before this
  /// screen ever opened. This only has to check the email is shaped like
  /// one; whether it is the *right* one is found out at the final submit,
  /// same as the code itself.
  void _continueFromEmail() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _step = _VerifyStep.code;
      _error = null;
      _note = null;
    });
  }

  /// Requests a fresh code for whatever email is currently typed. Lives on
  /// the email step, not the code step -- unlike a password reset, a code
  /// was already sent once automatically, so this is the "that one didn't
  /// arrive / expired" escape hatch, offered before asking for the code
  /// rather than after.
  Future<void> _resendCode() async {
    if (_busy || _secondsLeft > 0) {
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty || !_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final auth = context.read<AuthRepository>();
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });

    final failure = await auth.resendVerification(email: email);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = failure;
      _note = failure == null ? 'A new code is on its way.' : null;
    });
    if (failure == null) {
      _startCooldown();
    }
  }

  /// Moves from the code step to the new-password step.
  ///
  /// Same reasoning as the forgot-password flow's `_continueFromCode`:
  /// there is no endpoint that checks a verification code on its own, only
  /// one that checks it *and* sets the password together (`verifyAccount`),
  /// so this can only validate the one thing the server itself constrains
  /// client-side -- the code is always exactly 6 digits.
  void _continueFromCode() {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _step = _VerifyStep.newPassword;
      _error = null;
      _note = null;
    });
  }

  /// `VerifyAccountApiView`'s one error string for every code-shaped
  /// problem -- wrong code, expired, already verified, unknown email -- see
  /// `users/views.py` in the backend repo. Unlike the password-reset
  /// endpoint, it does not keep a wrong code and an expired one distinct,
  /// so this is the only string worth checking for.
  static bool _isCodeError(String message) =>
      message == 'Invalid email or code.';

  Future<void> _verify() async {
    if (_busy) {
      return;
    }
    final password = _passwordController.text;
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (password != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final auth = context.read<AuthRepository>();
    final authCubit = context.read<AuthCubit>();
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });

    final failure = await auth.verifyAccount(
      email: email,
      code: code,
      password: password,
    );
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _busy = false;
        // A rejected code is fixed on the code step, not this one -- sent
        // back there (rather than shown in place) so the error sits next to
        // the field that actually needs retyping.
        if (_isCodeError(failure)) {
          _step = _VerifyStep.code;
        }
        _error = failure;
      });
      return;
    }

    // Verified -- sign in with the password just set instead of making them
    // retype it into the ordinary form, since whatever was sitting in that
    // form's password field before this ran is not it. Succeeding here
    // flips `AuthCubit`'s state to authenticated, which is what swaps this
    // whole screen out from under this widget -- there is no "done" step to
    // build. Failing (a dropped connection right after verifying, say)
    // instead hands the email back to the ordinary sign-in form, which
    // already shows whatever error `login` just recorded for itself.
    await authCubit.login(email, password, true);
    if (!mounted || authCubit.state.isAuthenticated) {
      return;
    }
    setState(() => _busy = false);
    widget.onDone(email);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _VerifyStep.email => _buildEmailStep(context),
      _VerifyStep.code => _buildCodeStep(context),
      _VerifyStep.newPassword => _buildNewPasswordStep(context),
    };
  }

  Widget _buildEmailStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the email your account was created with. A code was '
          'already sent there when the account was created.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.35),
        ),
        const SizedBox(height: 16),
        FloatingLabelTextField(
          controller: _emailController,
          labelText: 'Email',
          prefixIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _continueFromEmail(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: (_busy || _secondsLeft > 0) ? null : _resendCode,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              _secondsLeft > 0
                  ? 'Resend code in ${_secondsLeft}s'
                  : 'Resend code',
            ),
          ),
        ),
        _buildMessage(),
        const SizedBox(height: 8),
        _buildPrimaryButton(
          label: 'CONTINUE',
          onPressed: () async => _continueFromEmail(),
        ),
      ],
    );
  }

  Widget _buildCodeStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the code sent to ${_emailController.text.trim()}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        OtpCodeField(
          length: 6,
          initialValue: _codeController.text,
          onChanged: (value) => _codeController.text = value,
          onSubmitted: (_) => _continueFromCode(),
        ),
        _buildMessage(),
        const SizedBox(height: 18),
        _buildPrimaryButton(
          label: 'CONTINUE',
          onPressed: () async => _continueFromCode(),
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose the password you\'ll sign in with from now on.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.35),
        ),
        const SizedBox(height: 16),
        FloatingLabelTextField(
          controller: _passwordController,
          labelText: 'Password',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        FloatingLabelTextField(
          controller: _confirmPasswordController,
          labelText: 'Confirm password',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verify(),
        ),
        _buildMessage(),
        const SizedBox(height: 18),
        _buildPrimaryButton(label: 'CONFIRM', onPressed: _verify),
      ],
    );
  }

  Widget _buildMessage() {
    if (_error == null && _note == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _error ?? _note!,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: _error != null ? AppColors.error : AppColors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required Future<void> Function() onPressed,
  }) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: _busy ? null : onPressed,
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
