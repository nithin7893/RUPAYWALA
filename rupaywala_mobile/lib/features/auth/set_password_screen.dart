import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'otp_screen.dart';

/// Password creation / reset. Shared by the signup step and the
/// forgot-password flow, which is why it takes a title and a submit label.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({
    super.key,
    this.phoneNumber,
    this.email,
    this.method = OtpMethod.phone,
    this.title = 'Create your password',
    this.subtitle,
    this.submitLabel = 'Create account',
    this.isNewUser = true,
  });

  final String? phoneNumber;
  final String? email;
  final OtpMethod method;
  final String title;
  final String? subtitle;
  final String submitLabel;
  final bool isNewUser;

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _username = TextEditingController();

  bool _obscure = true;
  final bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(_validate);
    _confirm.addListener(_validate);
  }

  @override
  void dispose() {
    _password.removeListener(_validate);
    _confirm.removeListener(_validate);
    _password.dispose();
    _confirm.dispose();
    _username.dispose();
    super.dispose();
  }

  void _validate() {
    setState(() => _error = null);
  }

  /// Mirrors the backend rule: at least 8 characters with both letters and
  /// digits. Checking it here means the user is not told after a round trip.
  String? get _localProblem {
    if (_password.text.isEmpty) return null;
    final value = _password.text;
    if (value.length < 8) return 'Use at least 8 characters';
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasDigit = RegExp(r'[0-9]').hasMatch(value);
    if (!hasLetter || !hasDigit) {
      return 'Include both letters and numbers';
    }
    return null;
  }

  bool get _canSubmit {
    final password = _password.text;
    final confirm = _confirm.text;
    if (password.length < 8) return false;
    if (password != confirm) return false;
    if (_username.text.trim().length < 3) return false;
    return _localProblem == null;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _loading) return;

    if (_password.text != _confirm.text) {
      setState(() => _error = 'The two passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    final api = context.api;
    final session = context.session;

    try {
      if (widget.method == OtpMethod.email && widget.email != null) {
        final result = await api.auth.registerEmail(
          email: widget.email!,
          username: _username.text.trim(),
          password: _password.text,
          phoneNumber: widget.phoneNumber,
        );
        if (!mounted) return;
        await session.loginWithResult(result);
        if (!mounted) return;
        if (!session.isSignedIn) {
          setState(() {
            _loading = false;
            _error = session.error ?? 'Account creation could not be completed.';
          });
          return;
        }
        navigator.popUntil((route) => route.isFirst);
        return;
      }
      if (!mounted) return;
      await session.register(
        phoneNumber: widget.phoneNumber!,
        username: _username.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      if (!session.isSignedIn) {
        setState(() {
          _loading = false;
          _error = session.error ?? 'Account creation could not be completed.';
        });
        return;
      }
      // On success the session controller flips to signedIn and the app gate
      // swaps the whole tree, so this route is simply discarded.
      navigator.popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _localProblem;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: ConstrainedBody(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),
                Text(
                  widget.title,
                  style: AppText.screenTitle,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.subtitle ??
                      ((widget.method == OtpMethod.email &&
                              widget.email != null)
                          ? 'Your email is verified for ${widget.email}. Choose a username and password.'
                          : 'Your number is verified for +91 ${widget.phoneNumber}. Choose a username and password.'),
                  style: AppText.bodyMuted,
                ),
                const SizedBox(height: AppSpacing.xxl),
                AppTextField(
                  controller: _username,
                  label: 'Username',
                  isRequired: true,
                  hint: 'Letters and numbers',
                  prefixIcon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newUsername],
                  onChanged: (_) => _validate(),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _password,
                  label: 'Password',
                  isRequired: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  helper: 'At least 8 characters with both letters and numbers',
                  errorText: problem,
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
                  onChanged: (_) => _validate(),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _confirm,
                  label: 'Confirm password',
                  isRequired: true,
                  prefixIcon: Icons.lock_reset_outlined,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _validate(),
                  onSubmitted: (_) => _submit(),
                  errorText: _confirm.text.isNotEmpty &&
                          _confirm.text != _password.text
                      ? 'Passwords do not match'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  InfoBanner(
                    tone: InfoTone.error,
                    message: _error!,
                    icon: Icons.error_outline_rounded,
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                AppButton(
                  label: widget.submitLabel,
                  isLoading: _loading,
                  onPressed: _canSubmit ? _submit : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(
                    widget.method == OtpMethod.email
                        ? 'Your account will be linked to ${widget.email}'
                        : 'Your account will be linked to +91 ${widget.phoneNumber}',
                    style: AppText.caption.copyWith(fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
