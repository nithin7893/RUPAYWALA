import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/config/app_config.dart';
import '../../core/models/auth_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'email_input_screen.dart';
import 'otp_screen.dart';
import 'password_login_screen.dart';

/// Step 1 of the auth flow: the mobile number.
///
/// `/auth/check-user` decides where the user goes next, so this screen never
/// has to guess whether someone is registering or signing in.
class PhoneInputScreen extends StatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final TextEditingController _phone = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();

  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _phone.addListener(_onChanged);
  }

  @override
  void dispose() {
    _phone.removeListener(_onChanged);
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() => _error = null);
  }

  bool get _isValid => _phone.text.length == 10;

  Future<void> _submit() async {
    if (!_isValid) {
      setState(() => _error = 'Enter a 10-digit mobile number');
      return;
    }
    if (_loading) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final api = context.api;
    final messenger = ScaffoldMessenger.of(context);
    final number = _phone.text.trim();

    try {
      final check = await api.auth.checkUser(number);

      if (!mounted) return;

      if (!check.exists) {
        // Brand new number: verify ownership first, then register.
        final dispatch = await api.auth.sendOtp(number);
        if (!mounted) return;
        _goToOtp(number, check: check, dispatch: dispatch);
        return;
      }

      if (check.next == 'login') {
        _openLogin(number);
        return;
      }

      final dispatch = await api.auth.sendOtp(number);
      if (!mounted) return;
      _goToOtp(number, check: check, dispatch: dispatch);
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

  void _openLogin(String phone) {
    setState(() => _loading = false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PasswordLoginScreen(phoneNumber: phone),
      ),
    );
  }

  void _goToOtp(
    String phone, {
    required IdentityCheck check,
    required OtpDispatch dispatch,
  }) {
    setState(() => _loading = false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OtpScreen(
          phoneNumber: phone,
          expectedNext: check.next,
          delivered: dispatch.delivered,
        ),
      ),
    );
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
                            Text(
                              'Welcome to Rupaywala',
                              style: AppText.screenTitle,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Doorstep policy service, tracked from submission to completion.',
                              style: AppText.bodyMuted,
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                            PhoneNumberField(
                              controller: _phone,
                              focusNode: _phoneFocus,
                              errorText: _error,
                              onChanged: (_) {},
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'We will send a verification code to this number.',
                              style: AppText.caption,
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
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      isLoading: _loading,
                      onPressed: _isValid ? _submit : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Continue with email',
                      variant: AppButtonVariant.ghost,
                      icon: Icons.mail_outline_rounded,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const EmailInputScreen(),
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
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 15,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            'Connected to ${AppConfig.baseUrlHost}',
                            style: AppText.caption.copyWith(
                              fontSize: 11.5,
                              color: AppColors.textHint,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
