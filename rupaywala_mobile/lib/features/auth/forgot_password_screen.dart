import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/config/app_config.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// Password reset: verify the code, then set the new password.
///
/// Kept as one screen because the two steps share a single backend pairing —
/// the code must still be unused when the reset is submitted.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _otp = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  bool _sendingCode = false;
  String? _error;
  int _secondsLeft = 0;
  bool _initialRequestStarted = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialRequestStarted) return;
    _initialRequestStarted = true;
    _requestCode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otp.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_sendingCode) return;
    setState(() {
      _sendingCode = true;
      _error = null;
    });
    try {
      await context.api.auth.sendForgotPasswordOtp(widget.phoneNumber);
      if (!mounted) return;
      _startCooldown();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = AppConfig.otpCooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft <= 1) {
          _secondsLeft = 0;
          timer.cancel();
        } else {
          _secondsLeft--;
        }
      });
    });
  }

  bool get _canSubmit => _otp.text.length >= 4 && _password.text.length >= 8;

  Future<void> _submit() async {
    if (!_canSubmit || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await context.api.auth.resetPassword(
        phoneNumber: widget.phoneNumber,
        otp: _otp.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated. You can sign in now.')),
      );
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppPageHeader(title: 'Reset password'),
      body: SafeArea(
        child: ConstrainedBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Verify and set a new password',
                style: AppText.screenTitle,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Enter the code sent to +91 ${widget.phoneNumber} and choose a new password.',
                style: AppText.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                controller: _otp,
                label: 'Verification code',
                isRequired: true,
                prefixIcon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textInputAction: TextInputAction.next,
                textAlign: TextAlign.center,
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _password,
                label: 'New password',
                isRequired: true,
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                helper: 'At least 8 characters with both letters and numbers',
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
                onChanged: (_) {
                  setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed:
                    _secondsLeft == 0 && !_sendingCode ? _requestCode : null,
                child: Text(
                  _sendingCode
                      ? 'Sending code…'
                      : _secondsLeft == 0
                          ? 'Send a new code'
                          : 'Send a new code in ${_secondsLeft}s',
                ),
              ),
              const Spacer(),
              AppButton(
                label: 'Update password',
                isLoading: _loading,
                onPressed: _canSubmit ? _submit : null,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
