import 'package:flutter/material.dart';

import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({super.key});

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  final _usernameController = TextEditingController();
  final _usernamePasswordController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _updatingUsername = false;
  bool _updatingPassword = false;
  bool _usernameInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_usernameInitialized) return;
    _usernameInitialized = true;
    _usernameController.text = context.session.session?.username ?? '';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _usernamePasswordController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changeUsername() async {
    final username = _usernameController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_.]{3,50}$').hasMatch(username)) {
      _showMessage(
        'Username must be 3–50 characters and use only letters, numbers, dots or underscores.',
        isError: true,
      );
      return;
    }
    final hasPassword = context.session.session?.hasPassword ?? false;
    if (hasPassword && _usernamePasswordController.text.isEmpty) {
      _showMessage('Enter your current password to change your username.',
          isError: true);
      return;
    }

    setState(() => _updatingUsername = true);
    try {
      final updated = await context.session.changeUsername(
        username: username,
        currentPassword: hasPassword ? _usernamePasswordController.text : null,
      );
      if (!mounted) return;
      _usernameController.text = updated;
      _usernamePasswordController.clear();
      _showMessage('Username updated successfully.');
    } catch (e) {
      if (mounted) _showMessage('Could not update username: $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingUsername = false);
    }
  }

  Future<void> _changePassword() async {
    final hasPassword = context.session.session?.hasPassword ?? false;
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    if (hasPassword && currentPassword.isEmpty) {
      _showMessage('Enter your current password.', isError: true);
      return;
    }
    if (newPassword.length < 8) {
      _showMessage('Your new password must be at least 8 characters.',
          isError: true);
      return;
    }
    if (newPassword != _confirmPasswordController.text) {
      _showMessage('The new passwords do not match.', isError: true);
      return;
    }

    setState(() => _updatingPassword = true);
    try {
      await context.api.auth.changePassword(
        currentPassword: hasPassword ? currentPassword : null,
        newPassword: newPassword,
      );
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showMessage('Password updated successfully.');
    } catch (e) {
      if (mounted) _showMessage('Could not update password: $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingPassword = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session.session;
    if (session == null) {
      return const Scaffold(
        body: Center(child: AppLoading(message: 'Loading profile...')),
      );
    }

    final member = session.fieldMember;
    final displayName = member?.fullName?.trim().isNotEmpty == true
        ? member!.fullName!
        : session.displayName;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: AppDimensions.pagePadding,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: AppTypography.sectionTitle),
                const SizedBox(height: AppDimensions.spacingMd),
                _ProfileValue(label: 'Account type', value: session.role.label),
                _ProfileValue(
                  label: 'Username',
                  value: session.username ?? 'Not set',
                ),
                if (session.phoneNumber?.isNotEmpty == true)
                  _ProfileValue(
                    label: 'Mobile number',
                    value: session.phoneNumber!,
                  ),
                if (session.email?.isNotEmpty == true)
                  _ProfileValue(label: 'Email', value: session.email!),
                if (member?.employeeCode?.isNotEmpty == true)
                  _ProfileValue(
                    label: 'Employee code',
                    value: member!.employeeCode!,
                  ),
                if (member?.region?.isNotEmpty == true)
                  _ProfileValue(label: 'Region', value: member!.region!),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Change username', style: AppTypography.cardTitle),
                const SizedBox(height: AppDimensions.spacingXs),
                Text(
                  session.hasPassword
                      ? 'Your username is used when signing in. You will need your current password to change it.'
                      : 'Your username is used when signing in.',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppDimensions.spacingMd),
                AppInputField(
                  controller: _usernameController,
                  label: 'New username',
                  textCapitalization: TextCapitalization.none,
                  autofillHints: const [AutofillHints.username],
                ),
                if (session.hasPassword) ...[
                  const SizedBox(height: AppDimensions.spacingSm),
                  AppInputField(
                    controller: _usernamePasswordController,
                    label: 'Current password',
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                  ),
                ],
                const SizedBox(height: AppDimensions.spacingMd),
                AppButton(
                  label: 'Update username',
                  isLoading: _updatingUsername,
                  onPressed: _updatingUsername ? null : _changeUsername,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Change password', style: AppTypography.cardTitle),
                const SizedBox(height: AppDimensions.spacingXs),
                Text(
                  session.hasPassword
                      ? 'Choose a password with at least 8 characters, including letters and numbers.'
                      : 'Set a password with at least 8 characters, including letters and numbers.',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppDimensions.spacingMd),
                if (session.hasPassword) ...[
                  AppInputField(
                    controller: _currentPasswordController,
                    label: 'Current password',
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                ],
                AppInputField(
                  controller: _newPasswordController,
                  label: 'New password',
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: AppDimensions.spacingSm),
                AppInputField(
                  controller: _confirmPasswordController,
                  label: 'Confirm new password',
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: AppDimensions.spacingMd),
                AppButton(
                  label: 'Update password',
                  isLoading: _updatingPassword,
                  onPressed: _updatingPassword ? null : _changePassword,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileValue extends StatelessWidget {
  const _ProfileValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: AppTypography.caption),
          ),
          Expanded(child: Text(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}
