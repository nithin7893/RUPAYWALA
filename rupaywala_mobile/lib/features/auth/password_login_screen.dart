import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'forgot_password_screen.dart';

/// Password sign-in. Reached either from `/auth/check-user` or after an OTP
/// has already proved ownership of the number.
class PasswordLoginScreen extends StatefulWidget {
  const PasswordLoginScreen({
    super.key,
    this.phoneNumber,
    this.verifiedByOtp = false,
  });

  /// Pre-fills the identifier when the flow started from a phone number.
  final String? phoneNumber;

  final bool verifiedByOtp;

  @override
  State<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<PasswordLoginScreen> {
  late final TextEditingController _identifier =
      TextEditingController(text: widget.phoneNumber ?? '');
  final TextEditingController _password = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _identifier.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = context.session;
      await session.login(
        identifier: _identifier.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      if (!session.isSignedIn) {
        setState(() {
          _loading = false;
          _error = session.error ?? 'Sign in could not be completed.';
        });
        return;
      }
      // The app gate swaps in the role shell; drop this route so Back cannot
      // return to the login form.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _forgotPassword() async {
    final phone = widget.phoneNumber ?? _identifier.text.trim();
    if (phone.length != 10) {
      setState(() =>
          _error = 'Enter your 10-digit mobile number to reset your password');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForgotPasswordScreen(phoneNumber: phone),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: AuthScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text('Welcome back', style: AppText.screenTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.verifiedByOtp
                  ? 'Your number is verified. Enter your password to continue.'
                  : 'Sign in with your username or mobile number. Field members can use the credentials provided by their admin.',
              style: AppText.bodyMuted,
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppTextField(
              controller: _identifier,
              label: 'Username or mobile number',
              isRequired: true,
              prefixIcon: Icons.badge_outlined,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              onChanged: (_) {
                setState(() => _error = null);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _password,
              label: 'Password',
              isRequired: true,
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) {
                setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                tooltip: _obscure ? 'Show password' : 'Hide password',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(
                tone: InfoTone.error,
                message: _error!,
                icon: Icons.error_outline_rounded,
              ),
            ],
            const Spacer(),
            AppButton(
              label: 'Sign in',
              isLoading: _loading,
              onPressed: _canSubmit ? _submit : null,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
