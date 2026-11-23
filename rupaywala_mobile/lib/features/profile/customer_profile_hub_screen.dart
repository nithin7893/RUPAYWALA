import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../auth/phone_input_screen.dart';
import '../notifications/notifications_screen.dart';
import '../payment/payment_history_screen.dart';
import '../policy/policy_list_screen.dart';
import '../profile/account_profile_screen.dart';
import '../profile/profile_screen.dart';
import '../service/my_requests_screen.dart';
import '../shell/role_shell.dart';
import '../subscription/subscription_screen.dart';

/// Customer account hub.
///
/// The bottom bar has room for five destinations, so everything that belongs to
/// the account — personal details, membership, payments, security — is grouped
/// here instead of being hidden behind an unreachable profile form.
class CustomerProfileHubScreen extends StatefulWidget {
  const CustomerProfileHubScreen({super.key});

  @override
  State<CustomerProfileHubScreen> createState() =>
      _CustomerProfileHubScreenState();
}

class _CustomerProfileHubScreenState extends State<CustomerProfileHubScreen> {
  CustomerProfile? _profile;
  CustomerSubscription? _subscription;
  VisitBalance? _balance;
  bool _loading = true;
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
    final api = context.api;
    try {
      final results = await Future.wait<Object?>([
        api.customer.profile(),
        api.subscriptions.currentSubscription(),
        api.subscriptions.visitBalance(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as CustomerProfile;
        _subscription = results[1] as CustomerSubscription?;
        _balance = results[2] as VisitBalance;
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

  Future<void> _editProfile() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileScreen(existing: _profile),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await context.session.refresh();
      await _load();
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) _load();
  }

  void _openTab(ShellTab tab, Widget fallback) {
    if (!context.openShellTab(tab)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => fallback),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need your mobile number and password to sign in again.',
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
    final session = context.session.session;
    final profile = _profile;
    final name = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName
        : (session?.displayName ?? 'Customer');
    final needsProfile =
        session?.profileCompleted == false || profile?.profileCompleted == false;

    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Profile',
        showBack: false,
        actions: [
          AppBarIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            onPressed: () => _open(const NotificationsScreen()),
          ),
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh profile',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 4)
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
                      _identityCard(
                        name: name,
                        phone: profile?.phoneNumber ?? session?.phoneNumber,
                        email: profile?.email ?? session?.email,
                        needsProfile: needsProfile,
                      ),
                      if (needsProfile) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoBanner(
                          tone: InfoTone.warning,
                          icon: Icons.badge_outlined,
                          title: 'Your profile is incomplete',
                          message:
                              'Add your date of birth and visit address so a field member can reach you.',
                          action: TextButton(
                            onPressed: _editProfile,
                            child: const Text('Complete now'),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(
                        title: 'Membership',
                        subtitle: 'Visits, validity and plan benefits.',
                      ),
                      _membershipCard(),
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Personal details'),
                      _detailsCard(profile),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: needsProfile ? 'Complete profile' : 'Edit profile',
                        icon: Icons.edit_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: _editProfile,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Account'),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            _LinkRow(
                              icon: Icons.workspace_premium_outlined,
                              title: 'Plans and visits',
                              subtitle: 'Renew or change your membership',
                              onTap: () => _open(const SubscriptionScreen()),
                            ),
                            _LinkRow(
                              icon: Icons.receipt_long_outlined,
                              title: 'Payment history',
                              subtitle: 'Every plan purchase and distance charge',
                              onTap: () => _open(const PaymentHistoryScreen()),
                            ),
                            _LinkRow(
                              icon: Icons.shield_outlined,
                              title: 'My policies',
                              subtitle: 'Insurance policies saved to your account',
                              onTap: () => _openTab(
                                ShellTab.policies,
                                const PolicyListScreen(),
                              ),
                            ),
                            _LinkRow(
                              icon: Icons.track_changes_outlined,
                              title: 'My requests',
                              subtitle: 'Track or review a service visit',
                              onTap: () => _openTab(
                                ShellTab.requests,
                                const MyRequestsScreen(),
                              ),
                            ),
                            _LinkRow(
                              icon: Icons.notifications_none_rounded,
                              title: 'Notifications',
                              subtitle: 'Updates about requests and payments',
                              onTap: () => _open(const NotificationsScreen()),
                            ),
                            _LinkRow(
                              icon: Icons.manage_accounts_outlined,
                              title: 'Account and security',
                              subtitle: 'Username, password and sign-in details',
                              onTap: () => _open(const AccountProfileScreen()),
                              isLast: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: 'Sign out',
                        icon: Icons.logout_rounded,
                        variant: AppButtonVariant.secondary,
                        onPressed: _logout,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _identityCard({
    required String name,
    required String? phone,
    required String? email,
    required bool needsProfile,
  }) {
    return AppCard(
      child: Row(
        children: [
          AppAvatar(initials: Fmt.initials(name), size: 56),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.sectionTitle),
                const SizedBox(height: 2),
                Text(
                  phone == null || phone.isEmpty ? 'No mobile number' : phone,
                  style: AppText.caption,
                ),
                if (email != null && email.isNotEmpty)
                  Text(email, style: AppText.caption),
                const SizedBox(height: AppSpacing.sm),
                StatusBadge(
                  label: needsProfile ? 'Profile incomplete' : 'Verified customer',
                  color: needsProfile ? AppColors.warning : AppColors.success,
                  background:
                      needsProfile ? AppColors.warningSoft : AppColors.successSoft,
                  icon: needsProfile
                      ? Icons.error_outline_rounded
                      : Icons.verified_outlined,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _membershipCard() {
    final subscription = _subscription;
    final balance = _balance;
    if (subscription == null || !subscription.isActive) {
      return AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconTile(
              icon: Icons.card_membership_outlined,
              color: AppColors.textSecondary,
              background: AppColors.neutralSoft,
            ),
            const SizedBox(width: AppSpacing.md),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No active membership', style: AppText.cardTitle),
                  SizedBox(height: 2),
                  Text(
                    'Choose a plan to cover doorstep visits and priority support.',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: () => _open(const SubscriptionScreen()),
              child: const Text('View plans'),
            ),
          ],
        ),
      );
    }

    final remaining = balance?.remainingVisits ?? subscription.remainingVisits;
    final total = balance?.totalVisits ?? subscription.totalVisits;
    return AppCard(
      onTap: () => _open(const SubscriptionScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(
                icon: Icons.workspace_premium_outlined,
                color: AppColors.secondaryDark,
                background: AppColors.secondarySoft,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.planName ?? 'Active membership',
                      style: AppText.cardTitle,
                    ),
                    Text(
                      'Valid till ${Fmt.date(subscription.endDate)}',
                      style: AppText.caption.copyWith(
                        color: subscription.isExpiringSoon
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ProgressMeter(
            label: 'Visits used',
            value: total - remaining,
            total: total,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                '$remaining remaining',
                style: AppText.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (subscription.numberOfPersons > 0)
                MetaPill(
                  label: '${subscription.numberOfPersons} members',
                  icon: Icons.groups_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(CustomerProfile? profile) {
    final address = [
      profile?.address,
      profile?.city,
      profile?.state,
      profile?.pincode,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(', ');

    return AppCard(
      child: Column(
        children: [
          InfoRow(
            label: 'Mobile',
            value: profile?.phoneNumber ?? 'Not added',
            icon: Icons.phone_outlined,
          ),
          InfoRow(
            label: 'Email',
            value: profile?.email ?? 'Not added',
            icon: Icons.email_outlined,
          ),
          InfoRow(
            label: 'Date of birth',
            value: profile?.dateOfBirth == null
                ? 'Not added'
                : Fmt.date(profile!.dateOfBirth),
            icon: Icons.cake_outlined,
          ),
          InfoRow(
            label: 'Gender',
            value: _titleCase(profile?.gender) ?? 'Not added',
            icon: Icons.wc_outlined,
          ),
          InfoRow(
            label: 'Visit address',
            value: address.isEmpty ? 'Not added' : address,
            icon: Icons.location_on_outlined,
            isLast: true,
          ),
        ],
      ),
    );
  }

  String? _titleCase(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            IconTile(
              icon: icon,
              size: 38,
              iconSize: 19,
              color: AppColors.primary,
              background: AppColors.primarySoft,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.title.copyWith(fontSize: 14)),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );

    if (isLast) return row;
    return Column(
      children: [
        row,
        const Divider(height: 1, indent: 66),
      ],
    );
  }
}
