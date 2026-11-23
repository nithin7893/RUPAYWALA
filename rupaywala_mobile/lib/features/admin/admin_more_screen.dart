import 'package:flutter/material.dart';

import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../auth/phone_input_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/account_profile_screen.dart';
import '../shell/role_shell.dart';
import 'admin_branches_screen.dart';
import 'admin_distance_rate_screen.dart';
import 'admin_field_members_screen.dart';
import 'admin_payments_screen.dart';

/// Secondary admin tools that do not fit on the five-tab bar.
class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  void _openTab(BuildContext context, ShellTab tab, Widget fallback) {
    if (!context.openShellTab(tab)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => fallback),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need your admin credentials to sign in again.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await context.session.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const PhoneInputScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session.session;
    return AppScaffold(
      appBar: const AppPageHeader(title: 'More', showBack: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          AppCard(
            child: Row(
              children: [
                AppAvatar(
                  initials: _initials(session?.displayName ?? 'Admin'),
                  size: 50,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session?.displayName ?? 'Administrator',
                        style: AppText.cardTitle,
                      ),
                      Text(
                        session?.username == null
                            ? 'Administrator'
                            : '@${session!.username}',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const StatusBadge(
                  label: 'Admin',
                  color: AppColors.primary,
                  background: AppColors.primarySoft,
                  icon: Icons.admin_panel_settings_outlined,
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Configuration'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MoreRow(
                  icon: Icons.storefront_outlined,
                  title: 'Branches',
                  subtitle: 'Add, edit or deactivate a branch',
                  onTap: () => _open(context, const AdminBranchesScreen()),
                ),
                _MoreRow(
                  icon: Icons.speed_rounded,
                  title: 'Distance rate',
                  subtitle: 'Threshold, per-km rate, tax and round trip',
                  onTap: () =>
                      _open(context, const AdminDistanceRateScreen()),
                ),
                _MoreRow(
                  icon: Icons.groups_outlined,
                  title: 'Field team',
                  subtitle: 'Approve members and manage availability',
                  onTap: () => _openTab(
                    context,
                    ShellTab.team,
                    const AdminFieldMembersScreen(),
                  ),
                ),
                _MoreRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Payments',
                  subtitle: 'Verify customer UPI references',
                  onTap: () => _openTab(
                    context,
                    ShellTab.payments,
                    const AdminPaymentsScreen(),
                  ),
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Account'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MoreRow(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Request and payment updates',
                  onTap: () => _open(context, const NotificationsScreen()),
                ),
                _MoreRow(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Account and security',
                  subtitle: 'Username and password',
                  onTap: () => _open(context, const AccountProfileScreen()),
                ),
                _MoreRow(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  subtitle: 'End this session',
                  destructive: true,
                  onTap: () => _logout(context),
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppCard(
            color: AppColors.surfaceMuted,
            elevated: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 19,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Service catalogue activation is managed by the Rupaywala team. The admin catalogue endpoint does not expose the active flag, so it is not shown here.',
                    style: AppText.caption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'AD';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.primary;
    final background = destructive ? AppColors.errorSoft : AppColors.primarySoft;
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
              color: color,
              background: background,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.title.copyWith(
                      fontSize: 14,
                      color: destructive ? AppColors.error : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!destructive)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
              ),
          ],
        ),
      ),
    );
    if (isLast) return row;
    return Column(children: [row, const Divider(height: 1, indent: 66)]);
  }
}
