import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'otp_screen.dart';
import 'password_login_screen.dart';
import 'phone_input_screen.dart';

class EmailInputScreen extends StatefulWidget {
  const EmailInputScreen({super.key});

  @override
  State<EmailInputScreen> createState() => _EmailInputScreenState();
}

class _EmailInputScreenState extends State<EmailInputScreen> {
  final TextEditingController _email = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _email.addListener(_onChanged);
  }

  @override
  void dispose() {
    _email.removeListener(_onChanged);
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() => _error = null);
  }

  bool get _isValid {
    final value = _email.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  Future<void> _submit() async {
    if (!_isValid) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (_loading) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final api = context.api;
    final messenger = ScaffoldMessenger.of(context);
    final email = _email.text.trim().toLowerCase();

    try {
      final dispatch = await api.auth.sendEmailOtp(email);
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OtpScreen(
            email: email,
            method: OtpMethod.email,
            delivered: dispatch.delivered,
            expectedNext: 'register',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      if (e.isNetworkError) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ConstrainedBody(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.xxxl),
                      const Center(child: BrandMark(size: 64)),
                      const SizedBox(height: AppSpacing.xxl),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sign in with email',
                                style: AppText.screenTitle),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'We will send a verification code to your email.',
                              style: AppText.bodyMuted,
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                            AppTextField(
                              controller: _email,
                              focusNode: _emailFocus,
                              label: 'Email address',
                              hint: 'you@example.com',
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              errorText: _error,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                              ],
                              onSubmitted: (_) => _submit(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Column(
                  children: [
                    AppButton(
                      label: 'Continue with email',
                      icon: Icons.mail_outline_rounded,
                      isLoading: _loading,
                      onPressed: _isValid ? _submit : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Continue with phone',
                      variant: AppButtonVariant.ghost,
                      icon: Icons.phone_outlined,
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const PhoneInputScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Sign in with password',
                      variant: AppButtonVariant.ghost,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PasswordLoginScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
