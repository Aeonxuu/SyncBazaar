import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/auth/auth_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/floating_label_text_field.dart';
import '../../widgets/otp_code_field.dart';
import 'verify_account_panel.dart';

// Same shape as the one in staff_screen.dart's add/edit form -- duplicated
// rather than shared because there is nowhere both screens already import
// from, and one more regex constant is cheaper than inventing that seam.
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Upload the app icon here: assets/icons/syncbazaar_icon.png
  static const _logoAsset = 'assets/icons/syncbazaar_icon.png';
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showForgotPassword = false;
  bool _showVerifyAccount = false;

  // Held rather than built inline in `TextSpan.recognizer`, which would
  // create a fresh one on every rebuild without ever disposing the last one.
  final _verifyCodeRecognizer = TapGestureRecognizer();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _verifyCodeRecognizer.dispose();
    super.dispose();
  }

  /// Shared by the SIGN IN button and Enter in the password field. Checks
  /// the cubit's own state rather than the button's, since Enter bypasses
  /// the button's disabled state.
  void _signIn() {
    final cubit = context.read<AuthCubit>();
    if (cubit.state.isLoading) {
      return;
    }
    cubit.login(_emailController.text.trim(), _passwordController.text, true);
  }

  @override
  Widget build(BuildContext context) {
    final lightPurple = Color.lerp(AppColors.primary, Colors.white, 0.92)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [lightPurple, Colors.white],
          ),
        ),
        child: CustomPaint(
          painter: _DottedNotebookPainter(
            dotColor: AppColors.primary.withValues(alpha: 0.15),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 28,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
                      // The error is drawn into the form below rather than
                      // announced in a snackbar, so there is one message
                      // instead of two and it stays put while it is fixed.
                      child: BlocBuilder<AuthCubit, dynamic>(
                        builder: (context, state) {
                          if (_showForgotPassword) {
                            return _buildForgotPasswordContent(context);
                          }
                          if (_showVerifyAccount) {
                            return _buildVerifyAccountContent(context);
                          }
                          return _buildLoginContent(context, state);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginContent(BuildContext context, dynamic state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Image.asset(
              _logoAsset,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.storefront_outlined,
                color: AppColors.primary,
                size: 42,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'SyncBazaar',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 28),
        FloatingLabelTextField(
          controller: _emailController,
          labelText: 'Email',
          prefixIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        FloatingLabelTextField(
          controller: _passwordController,
          labelText: 'Password',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _signIn(),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              setState(() {
                _showForgotPassword = true;
              });
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Forgot Password?',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Rendered from state rather than shown as a snackbar, so it is still
        // on screen while the cashier retypes. A snackbar for the one message
        // that says why the button did nothing is gone before they look up.
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 18,
                  color: AppColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.error as String,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        // Not gated on the error's wording: a brand-new account has no
        // password at all until this runs, so its very first sign-in attempt
        // fails with the same generic "Invalid credentials" as a typo would —
        // there is no server message left to detect "unverified" from. Always
        // offering the link is what actually gets a new hire unstuck.
        //
        // Sat as its own icon-button paragraph before this, competing with
        // "Forgot Password?" for attention above the fold. It is really a
        // second door into the same action below it, not a distinct action of
        // its own — so it reads as a quiet, centered sentence right against
        // Sign In instead, matching the "already have an account?" pattern
        // any returning user already knows (Jakob's Law).
        Center(
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              children: [
                const TextSpan(text: 'New here? '),
                TextSpan(
                  text: 'Enter your verification code',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  recognizer: _verifyCodeRecognizer
                    ..onTap = state.isLoading
                        ? null
                        : () => setState(() => _showVerifyAccount = true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
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
            onPressed: state.isLoading ? null : _signIn,
            child: Text(state.isLoading ? 'SIGNING IN...' : 'SIGN IN'),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOverlayHeader(
          onBack: () => setState(() => _showForgotPassword = false),
        ),
        const SizedBox(height: 22),
        _ResetPasswordPanel(
          initialEmail: _emailController.text.trim(),
          onDone: (email) {
            setState(() {
              _emailController.text = email;
              _showForgotPassword = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildVerifyAccountContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOverlayHeader(
          onBack: () => setState(() => _showVerifyAccount = false),
        ),
        const SizedBox(height: 22),
        VerifyAccountPanel(
          initialEmail: _emailController.text.trim(),
          onDone: (email) {
            setState(() {
              _emailController.text = email;
              _showVerifyAccount = false;
            });
          },
        ),
      ],
    );
  }

  /// The back arrow / logo / title shared by every overlay this screen
  /// swaps in over the sign-in form (forgot password, verify account) —
  /// same recipe as the sign-in form's own logo block, just with a way out.
  Widget _buildOverlayHeader({required VoidCallback onBack}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 96,
                  height: 96,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Image.asset(
                    _logoAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.storefront_outlined,
                      color: AppColors.primary,
                      size: 42,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'SyncBazaar',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ],
    );
  }
}

enum _ResetStep { email, code, newPassword, done }

/// The self-service "forgot password" flow: request a code by email, then use
/// it to set a new password. Works the same for every role — there is no
/// admin above an owner to do this for them, so building one path for
/// everyone is simpler than building the admin-assisted reset twice.
///
/// Talks to [AuthRepository] directly rather than through `AuthCubit`, same
/// as `VerifyAccountPanel`: there is no session yet, so this has nothing to
/// do with `AuthState`.
class _ResetPasswordPanel extends StatefulWidget {
  const _ResetPasswordPanel({required this.initialEmail, required this.onDone});

  final String initialEmail;

  /// Called with the email once the password is changed, so the sign-in form
  /// can be prefilled with it rather than making them retype it.
  final ValueChanged<String> onDone;

  @override
  State<_ResetPasswordPanel> createState() => _ResetPasswordPanelState();
}

class _ResetPasswordPanelState extends State<_ResetPasswordPanel> {
  static const _resendCooldown = Duration(seconds: 30);

  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ResetStep _step = _ResetStep.email;
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
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// A client-side cooldown on top of whatever the server enforces. It does
  /// not stop someone editing the request directly, but it stops an ordinary
  /// double-tap or an impatient retry from generating extra emails and extra
  /// load on the endpoint most exposed to abuse — see the TODO on
  /// `AuthRepository.requestPasswordReset`.
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

  Future<void> _sendCode() async {
    if (_busy) {
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

    final failure = await auth.requestPasswordReset(email: email);
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }
    setState(() {
      _busy = false;
      _step = _ResetStep.code;
      _note = 'If that email has an account, a code is on its way.';
    });
    _startCooldown();
  }

  /// Moves from the code step to the new-password step.
  ///
  /// There is no server endpoint that checks a reset code on its own — only
  /// one that checks it *and* sets the password together
  /// (`confirmPasswordReset`) — so this can only validate the one thing the
  /// server itself constrains client-side: the code is always exactly 6
  /// digits. Whether this particular code is the right one is only found out
  /// when [_resetPassword] submits it, which is why that method routes back
  /// here on a code-shaped failure rather than staying on the password step.
  void _continueFromCode() {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _step = _ResetStep.newPassword;
      _error = null;
      _note = null;
    });
  }

  /// The two error strings `ConfirmPasswordResetApiView` returns for a bad
  /// code, verbatim -- see `users/views.py` in the backend repo. Everything
  /// else it can fail with (weak password, mismatched confirmation) is a
  /// password-step problem, not a code-step one.
  static bool _isCodeError(String message) =>
      message == 'Invalid email or code.' ||
      message.startsWith('Reset code expired');

  Future<void> _resetPassword() async {
    if (_busy) {
      return;
    }
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    if (newPassword.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (newPassword != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    final auth = context.read<AuthRepository>();
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });

    final failure = await auth.confirmPasswordReset(
      email: _emailController.text.trim(),
      code: code,
      newPassword: newPassword,
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
          _step = _ResetStep.code;
        }
        _error = failure;
      });
      return;
    }
    setState(() {
      _busy = false;
      _step = _ResetStep.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _ResetStep.email => _buildEmailStep(context),
      _ResetStep.code => _buildCodeStep(context),
      _ResetStep.newPassword => _buildNewPasswordStep(context),
      _ResetStep.done => _buildDoneStep(context),
    };
  }

  Widget _buildEmailStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your account email and we will send you a code to reset '
          'your password.',
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
          onSubmitted: (_) => _sendCode(),
        ),
        _buildMessage(),
        const SizedBox(height: 18),
        _buildPrimaryButton(label: 'SEND CODE', onPressed: _sendCode),
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
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: (_busy || _secondsLeft > 0) ? null : _sendCode,
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
          'Choose a new password for ${_emailController.text.trim()}.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.35),
        ),
        const SizedBox(height: 16),
        FloatingLabelTextField(
          controller: _newPasswordController,
          labelText: 'New password',
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
          onSubmitted: (_) => _resetPassword(),
        ),
        _buildMessage(),
        const SizedBox(height: 18),
        _buildPrimaryButton(label: 'RESET PASSWORD', onPressed: _resetPassword),
      ],
    );
  }

  Widget _buildDoneStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Password updated. Sign in with your new password.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildPrimaryButton(
          label: 'BACK TO SIGN IN',
          onPressed: () async => widget.onDone(_emailController.text.trim()),
        ),
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

class _DottedNotebookPainter extends CustomPainter {
  _DottedNotebookPainter({required this.dotColor});

  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    const spacing = 14.0;
    const radius = 1.1;

    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedNotebookPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor;
  }
}
