import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/auth/auth_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../widgets/floating_label_text_field.dart';
import 'verify_account_dialog.dart';

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
  final _forgotEmailController = TextEditingController();
  bool _showForgotPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _forgotEmailController.dispose();
    super.dispose();
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
        ),
        const SizedBox(height: 14),
        FloatingLabelTextField(
          controller: _passwordController,
          labelText: 'Password',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              setState(() {
                _forgotEmailController.text = _emailController.text.trim();
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
          // Offered only when the server says the account is unverified, which
          // is the one refusal a person can actually resolve from here. It used
          // to be a dead end: the message named the problem and the app gave
          // them nothing to do about it.
          if (_looksUnverified(state.error as String)) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: state.isLoading
                    ? null
                    : () => _verifyThenSignIn(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.mark_email_read_outlined, size: 16),
                label: const Text('Enter the code from your email'),
              ),
            ),
          ],
        ],
        const SizedBox(height: 18),
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
            onPressed: state.isLoading
                ? null
                : () {
                    context.read<AuthCubit>().login(
                      _emailController.text.trim(),
                      _passwordController.text,
                      true,
                    );
                  },
            child: Text(state.isLoading ? 'SIGNING IN...' : 'SIGN IN'),
          ),
        ),
      ],
    );
  }

  /// Whether the server refused because the account has not been confirmed.
  ///
  /// Matched on the wording because the message is the server's, and a fixed
  /// string here would silently stop matching if it were reworded. Deliberately
  /// loose: showing the button when it is not needed costs a tap, hiding it
  /// when it is needed leaves someone stuck.
  static bool _looksUnverified(String error) =>
      error.toLowerCase().contains('not verified') ||
      error.toLowerCase().contains('verify');

  /// Confirms the account, then signs in with what is already typed.
  ///
  /// Signing in for them rather than returning to a filled form they have to
  /// submit again: they have just proved the account is theirs, and the
  /// password is still in the field.
  Future<void> _verifyThenSignIn(BuildContext context) async {
    final cubit = context.read<AuthCubit>();
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      return;
    }

    final verified = await showVerifyAccountDialog(context: context, email: email);
    if (!verified) {
      return;
    }
    await cubit.login(email, _passwordController.text, true);
  }

  Widget _buildForgotPasswordContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _showForgotPassword = false;
                    });
                  },
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
        const SizedBox(height: 22),
        FloatingLabelTextField(
          controller: _forgotEmailController,
          labelText: 'Enter your email address',
          prefixIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 10),
        Text(
          'So the app can inform the admin and send them a key to reset their password.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.35),
        ),
        const SizedBox(height: 24),
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('We will be with you shortly.')),
              );
            },
            child: const Text('CONFIRM'),
          ),
        ),
      ],
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
