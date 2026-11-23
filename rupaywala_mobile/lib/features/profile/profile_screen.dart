import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// Personal and address details.
///
/// Reached from the profile hub and from the "finish your profile" banner. The
/// same form creates and edits: the backend upsert accepts a partial payload,
/// and fields this screen does not own (policy and emergency contact details)
/// are passed straight back so editing never wipes them.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.existing});

  final CustomerProfile? existing;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _dob = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyNumber = TextEditingController();

  String _gender = 'male';
  DateTime? _dateOfBirth;
  bool _saving = false;
  String? _error;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    _applyExisting(widget.existing);
  }

  void _applyExisting(CustomerProfile? profile) {
    if (profile == null) return;
    _name.text = profile.fullName;
    _email.text = profile.email ?? '';
    _address.text = profile.address ?? '';
    _city.text = profile.city ?? '';
    _state.text = profile.state ?? '';
    _pincode.text = profile.pincode ?? '';
    _emergencyName.text = profile.emergencyContactName ?? '';
    _emergencyNumber.text = profile.emergencyContactNumber ?? '';
    _gender = profile.gender?.toLowerCase() ?? 'male';
    if (!const ['male', 'female', 'other'].contains(_gender)) _gender = 'male';
    final dob = profile.dateOfBirth;
    if (dob != null) {
      _dateOfBirth = dob;
      _dob.text = _formatDate(dob);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    _dob.dispose();
    _emergencyName.dispose();
    _emergencyNumber.dispose();
    super.dispose();
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateOfBirth = picked;
      _dob.text = _formatDate(picked);
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    if (_dateOfBirth == null) {
      setState(() => _error = 'Select your date of birth.');
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final pincode = _pincode.text.trim();
    if (pincode.isNotEmpty && pincode.length != 6) {
      setState(() => _error = 'A pincode has six digits.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final existing = widget.existing;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await context.api.customer.saveProfile(
        fullName: name,
        dateOfBirth: _formatDate(_dateOfBirth!),
        gender: _gender,
        email: email,
        address: _address.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        pincode: pincode,
        policyNumber: existing?.policyNumber,
        insuranceProvider: existing?.insuranceProvider,
        policyType: existing?.policyType,
        policyDetails: existing?.policyDetails,
        policyValidFrom: existing?.policyValidFrom == null
            ? null
            : _formatDate(existing!.policyValidFrom!),
        policyValidTill: existing?.policyValidTill == null
            ? null
            : _formatDate(existing!.policyValidTill!),
        emergencyContactName: _emergencyName.text.trim(),
        emergencyContactNumber: _emergencyNumber.text.trim(),
      );

      if (!mounted) return;
      await context.session.refresh();
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            existing == null || !existing.profileCompleted
                ? 'Profile complete. You can book a service now.'
                : 'Profile updated.',
          ),
        ),
      );
      navigator.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing?.exists == true;
    return AppScaffold(
      appBar: AppPageHeader(
        title: isEditing ? 'Edit profile' : 'Complete profile',
        actions: [
          if (isEditing)
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          InfoBanner(
            tone: InfoTone.info,
            icon: Icons.lock_outline_rounded,
            title: 'Only used to serve your visits',
            message:
                'Your address is shared with the assigned field member when you book a service.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Personal details'),
          AppCard(
            child: Column(
              children: [
                AppTextField(
                  controller: _name,
                  label: 'Full name',
                  isRequired: true,
                  hint: 'As printed on your policy',
                  prefixIcon: Icons.badge_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: AppSpacing.lg),
                GestureDetector(
                  onTap: _saving ? null : _pickDate,
                  child: AbsorbPointer(
                    child: AppTextField(
                      controller: _dob,
                      label: 'Date of birth',
                      isRequired: true,
                      hint: 'Select your date of birth',
                      prefixIcon: Icons.cake_outlined,
                      suffixIcon: const Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    prefixIcon: Icon(
                      Icons.wc_outlined,
                      color: AppColors.textHint,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _gender = value;
                              _error = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _email,
                  label: 'Email',
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Visit address'),
          AppCard(
            child: Column(
              children: [
                AppTextField(
                  controller: _address,
                  label: 'Address',
                  hint: 'House number, street and area',
                  prefixIcon: Icons.home_outlined,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _city,
                  label: 'City',
                  hint: 'City',
                  prefixIcon: Icons.location_city_outlined,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 360;
                    final state = AppTextField(
                      controller: _state,
                      label: 'State',
                      hint: 'State',
                      prefixIcon: Icons.map_outlined,
                      textInputAction: TextInputAction.next,
                    );
                    final pincode = AppTextField(
                      controller: _pincode,
                      label: 'Pincode',
                      hint: '6 digits',
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      prefixIcon: Icons.pin_outlined,
                      textInputAction: TextInputAction.next,
                    );
                    if (narrow) {
                      return Column(
                        children: [
                          state,
                          const SizedBox(height: AppSpacing.lg),
                          pincode,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: state),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: pincode),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
            title: 'Emergency contact',
            subtitle: 'Optional, but helpful for a doorstep visit.',
          ),
          AppCard(
            child: Column(
              children: [
                AppTextField(
                  controller: _emergencyName,
                  label: 'Contact name',
                  prefixIcon: Icons.contact_emergency_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _emergencyNumber,
                  label: 'Contact number',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            InfoBanner(
              tone: InfoTone.error,
              icon: Icons.error_outline_rounded,
              message: _error!,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: isEditing ? 'Save changes' : 'Save profile',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
