import 'package:flutter/material.dart';

import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../auth/phone_input_screen.dart';
import '../profile/account_profile_screen.dart';

/// Field member profile: identity, availability, workload and account actions.
class FieldProfileScreen extends StatefulWidget {
  const FieldProfileScreen({super.key});

  @override
  State<FieldProfileScreen> createState() => _FieldProfileScreenState();
}

class _FieldProfileScreenState extends State<FieldProfileScreen> {
  FieldMemberProfile? _profile;
  bool _loading = true;
  bool _updatingAvailability = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await context.api.fieldMember.profile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _toggleAvailability(bool available) async {
    final profile = _profile;
    if (profile == null || _updatingAvailability) return;
    setState(() => _updatingAvailability = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.fieldMember.setAvailability(available);
      if (!mounted) return;
      setState(() {
        _profile = FieldMemberProfile(
          fieldMemberId: profile.fieldMemberId,
          employeeCode: profile.employeeCode,
          fullName: profile.fullName,
          region: profile.region,
          phoneNumber: profile.phoneNumber,
          username: profile.username,
          approvalStatus: profile.approvalStatus,
          isAvailable: available,
          stats: profile.stats,
        );
        _updatingAvailability = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            available
                ? 'You are available for new assignments.'
                : 'You are marked unavailable. New assignments will not be sent.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingAvailability = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update availability: $error')),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need your username and password to sign in again.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await context.session.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const PhoneInputScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Profile',
        showBack: false,
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh profile',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 3)
          : _error != null
              ? ErrorStateView(
                  title: 'Profile could not load',
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xxxl,
                    ),
                    children: [
                      _identityCard(),
                      const SizedBox(height: AppSpacing.lg),
                      _availabilityCard(),
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Workload'),
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              label: 'Assigned',
                              value: '${_profile?.stats.assigned ?? 0}',
                              icon: Icons.assignment_outlined,
                              color: AppColors.info,
                              background: AppColors.infoSoft,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: StatTile(
                              label: 'In progress',
                              value: '${_profile?.stats.inProgress ?? 0}',
                              icon: Icons.sync_alt_rounded,
                              color: AppColors.primary,
                              background: AppColors.primarySoft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              label: 'Completed',
                              value: '${_profile?.stats.completed ?? 0}',
                              icon: Icons.task_alt_rounded,
                              color: AppColors.success,
                              background: AppColors.successSoft,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: StatTile(
                              label: 'Completed today',
                              value: '${_profile?.stats.completedToday ?? 0}',
                              icon: Icons.today_rounded,
                              color: AppColors.secondaryDark,
                              background: AppColors.secondarySoft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Account'),
                      _detailsCard(),
                      const SizedBox(height: AppSpacing.md),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            ListTile(
                              leading: const IconTile(
                                icon: Icons.manage_accounts_outlined,
                                color: AppColors.primary,
                                background: AppColors.primarySoft,
                                size: 38,
                                iconSize: 19,
                              ),
                              title: const Text('Account and security'),
                              subtitle: const Text('Username and password'),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textHint,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const AccountProfileScreen(),
                                ),
                              ),
                            ),
                            const Divider(height: 1, indent: 66),
                            ListTile(
                              leading: const IconTile(
                                icon: Icons.logout_rounded,
                                color: AppColors.error,
                                background: AppColors.errorSoft,
                                size: 38,
                                iconSize: 19,
                              ),
                              title: const Text('Sign out'),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textHint,
                              ),
                              onTap: _logout,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _identityCard() {
    final profile = _profile;
    final approval = StatusStyle.forApproval(
      profile?.approvalStatus ?? 'pending',
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                initials: Fmt.initials(profile?.displayName ?? 'Field member'),
                size: 56,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.displayName ?? 'Field member',
                      style: AppText.sectionTitle,
                    ),
                    if (profile?.employeeCode?.isNotEmpty == true)
                      Text(
                        'Employee ${profile!.employeeCode}',
                        style: AppText.caption,
                      ),
                    if (profile?.region?.isNotEmpty == true)
                      Text(profile!.region!, style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          StatusBadge(
            label: approval.label,
            color: approval.color,
            background: approval.background,
            icon: approval.icon,
          ),
        ],
      ),
    );
  }

  Widget _availabilityCard() {
    final profile = _profile;
    final available = profile?.isAvailable ?? false;
    return AppCard(
      child: Row(
        children: [
          IconTile(
            icon: available
                ? Icons.check_circle_outline
                : Icons.pause_circle_outline,
            color: available ? AppColors.secondaryDark : AppColors.textSecondary,
            background:
                available ? AppColors.secondarySoft : AppColors.neutralSoft,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available ? 'Available for work' : 'Not available',
                  style: AppText.cardTitle,
                ),
                const SizedBox(height: 2),
                Text(
                  available
                      ? 'New assignments can be sent to you.'
                      : 'Admins can still assign you a request manually.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch.adaptive(
            value: available,
            onChanged: _updatingAvailability ? null : _toggleAvailability,
            activeTrackColor: AppColors.secondary,
          ),
        ],
      ),
    );
  }

  Widget _detailsCard() {
    final profile = _profile;
    return AppCard(
      child: Column(
        children: [
          InfoRow(
            label: 'Username',
            value: profile?.username ?? 'Not set',
            icon: Icons.alternate_email_rounded,
          ),
          InfoRow(
            label: 'Mobile',
            value: profile?.phoneNumber ?? 'Not set',
            icon: Icons.phone_outlined,
          ),
          InfoRow(
            label: 'Employee code',
            value: profile?.employeeCode ?? 'Not set',
            icon: Icons.badge_outlined,
          ),
          InfoRow(
            label: 'Region',
            value: profile?.region ?? 'Not set',
            icon: Icons.map_outlined,
            isLast: true,
          ),
        ],
      ),
    );
  }
}
