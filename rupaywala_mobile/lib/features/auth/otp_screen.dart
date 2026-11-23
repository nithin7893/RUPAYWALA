import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/config/app_config.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'password_login_screen.dart';
import 'set_password_screen.dart';

enum OtpMethod { phone, email }

/// Step 2: six digit OTP entry with a resend cooldown.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    this.phoneNumber,
    this.email,
    this.expectedNext,
    this.delivered = true,
    this.method = OtpMethod.phone,
  });

  final String? phoneNumber;
  final String? email;

  /// Value of `next` from `/auth/check-user`, used only to decide whether the
  /// code should be sent on entry.
  final String? expectedNext;

  /// When SMS/email delivery failed the backend still issues a code.
  final bool delivered;
  final OtpMethod method;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otp = TextEditingController();

  bool _verifying = false;
  String? _error;
  int _secondsLeft = AppConfig.otpCooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = AppConfig.otpCooldownSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsLeft -= 1;
        if (_secondsLeft <= 0) {
          _secondsLeft = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _verifying = true;
    });

    try {
      if (widget.method == OtpMethod.email && widget.email != null) {
        final dispatch = await context.api.auth.sendEmailOtp(widget.email!);
        if (!mounted) return;
        _otp.clear();
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dispatch.delivered
                  ? 'A new code has been sent.'
                  : 'We could not send the code by email. Try again shortly.',
            ),
          ),
        );
      } else if (widget.phoneNumber != null) {
        final dispatch = await context.api.auth.sendOtp(widget.phoneNumber!);
        if (!mounted) return;
        _otp.clear();
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dispatch.delivered
                  ? 'A new code has been sent.'
                  : 'We could not send the code by SMS. Try again shortly.',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _verify(String code) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      if (widget.method == OtpMethod.email && widget.email != null) {
        final result =
            await context.api.auth.verifyEmailOtp(widget.email!, code);
        if (!mounted) return;

        if (result.next == 'login' && result.userExists) {
          try {
            final auth = await context.api.auth
                .emailLogin(email: widget.email!, otp: code);
            if (!mounted) return;
            await context.session.loginWithResult(auth);
            if (!mounted) return;
            setState(() => _verifying = false);
            Navigator.of(context).popUntil((route) => route.isFirst);
            return;
          } on ApiException {
            if (!mounted) return;
            setState(() => _verifying = false);
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const PasswordLoginScreen(),
              ),
            );
            return;
          }
        }

        setState(() => _verifying = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SetPasswordScreen(
              email: widget.email,
              isNewUser: result.next == 'register',
              method: OtpMethod.email,
            ),
          ),
        );
        return;
      }

      final result =
          await context.api.auth.verifyOtp(widget.phoneNumber!, code);
      if (!mounted) return;

      switch (result.next) {
        case 'login':
          _openPasswordLogin();
        case 'register':
        case 'set_password':
          _openRegistration();
        default:
          setState(() {
            _verifying = false;
            _error = result.message.isEmpty
                ? 'That code was not accepted. Try again.'
                : result.message;
          });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = e.message;
        _otp.clear();
      });
    }
  }

  void _openPasswordLogin() {
    setState(() => _verifying = false);
    // Replace rather than stack: OTP has done its job and the back button
    // should not return to a verified code.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PasswordLoginScreen(
          phoneNumber: widget.phoneNumber,
          verifiedByOtp: true,
        ),
      ),
    );
  }

  void _openRegistration() {
    setState(() => _verifying = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SetPasswordScreen(phoneNumber: widget.phoneNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft == 0 && !_verifying;
    final isEmail = widget.method == OtpMethod.email && widget.email != null;
    final title = isEmail ? 'Verify your email' : 'Verify your number';
    final subtitle = isEmail
        ? 'Enter the 6-digit code sent to ${widget.email}.'
        : 'Enter the 6-digit code sent to +91 ${widget.phoneNumber}.';
    final warningTitle =
        isEmail ? 'Email could not be sent' : 'SMS could not be sent';
    final warningMsg = isEmail
        ? 'We could not deliver the code by email just now. Wait a moment and request a new one.'
        : 'We could not deliver the code by SMS just now. Wait a moment and request a new one.';

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
              Text(title, style: AppText.screenTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: AppText.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (!widget.delivered) ...[
                InfoBanner(
                  tone: InfoTone.warning,
                  icon:
                      isEmail ? Icons.mail_outline_rounded : Icons.sms_outlined,
                  title: warningTitle,
                  message: warningMsg,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              OtpInput(
                controller: _otp,
                hasError: _error != null,
                onCompleted: _verify,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: AppText.caption.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              AppButton(
                label: 'Verify and continue',
                isLoading: _verifying,
                onPressed: () {
                  if (_otp.text.length == 6) {
                    _verify(_otp.text);
                  } else {
                    setState(() => _error = 'Enter all six digits');
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: canResend
                    ? TextButton(
                        onPressed: _resend,
                        child: const Text('Resend code'),
                      )
                    : Text(
                        'Resend available in ${_secondsLeft}s',
                        style:
                            AppText.caption.copyWith(color: AppColors.textHint),
                      ),
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
