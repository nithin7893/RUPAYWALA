import 'package:flutter/material.dart';

import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../notifications/notifications_screen.dart';
import '../shell/role_shell.dart';
import 'admin_branches_screen.dart';
import 'admin_distance_rate_screen.dart';
import 'admin_field_members_screen.dart';
import 'admin_payments_screen.dart';
import 'admin_requests_screen.dart';

/// Admin overview built from `GET /admin/dashboard`.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminDashboardStats? _stats;
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
    try {
      final stats = await context.api.admin.dashboard();
      if (!mounted) return;
      setState(() {
        _stats = stats;
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

  void _open(ShellTab tab, Widget fallback) {
    if (!context.openShellTab(tab)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => fallback),
      );
    }
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = context.session.session?.displayName ?? 'Admin';
    return Scaffold(
      body: _loading
          ? const _OverviewLoading()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header(name)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xxxl,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (_error != null)
                          ErrorStateView(
                            title: 'Overview could not load',
                            message: _error!,
                            onRetry: _load,
                          )
                        else if (_stats != null) ...[
                          _revenueCard(_stats!),
                          const SizedBox(height: AppSpacing.xl),
                          const SectionHeader(title: 'Operations'),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Open requests',
                                  value: '${_stats!.openRequests}',
                                  icon: Icons.inbox_outlined,
                                  color: AppColors.info,
                                  background: AppColors.infoSoft,
                                  caption: '${_stats!.inProgressRequests} in progress',
                                  onTap: () => _open(
                                    ShellTab.requests,
                                    const AdminRequestsScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: StatTile(
                                  label: 'Completed today',
                                  value: '${_stats!.completedToday}',
                                  icon: Icons.task_alt_rounded,
                                  color: AppColors.success,
                                  background: AppColors.successSoft,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Pending payments',
                                  value: '${_stats!.pendingPayments}',
                                  icon: Icons.manage_search_outlined,
                                  color: _stats!.pendingPayments > 0
                                      ? AppColors.warning
                                      : AppColors.success,
                                  background: _stats!.pendingPayments > 0
                                      ? AppColors.warningSoft
                                      : AppColors.successSoft,
                                  caption: 'Need verification',
                                  onTap: () => _open(
                                    ShellTab.payments,
                                    const AdminPaymentsScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: StatTile(
                                  label: 'Field approvals',
                                  value: '${_stats!.pendingFieldMembers}',
                                  icon: Icons.how_to_reg_outlined,
                                  color: _stats!.pendingFieldMembers > 0
                                      ? AppColors.warning
                                      : AppColors.success,
                                  background: _stats!.pendingFieldMembers > 0
                                      ? AppColors.warningSoft
                                      : AppColors.successSoft,
                                  caption: 'Waiting for review',
                                  onTap: () => _open(
                                    ShellTab.team,
                                    const AdminFieldMembersScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Active subscriptions',
                                  value: '${_stats!.activeSubscriptions}',
                                  icon: Icons.workspace_premium_outlined,
                                  color: AppColors.primary,
                                  background: AppColors.primarySoft,
                                  caption:
                                      '${_stats!.expiringSubscriptions} expiring soon',
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: StatTile(
                                  label: 'Customers',
                                  value: '${_stats!.totalCustomers}',
                                  icon: Icons.people_outline_rounded,
                                  color: AppColors.secondaryDark,
                                  background: AppColors.secondarySoft,
                                  caption:
                                      '${_stats!.totalFieldMembers} field members',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const SectionHeader(title: 'Manage'),
                          _managementCard(),
                          const SizedBox(height: AppSpacing.xl),
                          const SectionHeader(title: 'Summary'),
                          AppCard(
                            child: Column(
                              children: [
                                InfoRow(
                                  label: 'Total requests',
                                  value: '${_stats!.totalServiceRequests}',
                                  icon: Icons.receipt_long_outlined,
                                ),
                                InfoRow(
                                  label: 'Cancelled requests',
                                  value: '${_stats!.cancelledRequests}',
                                  icon: Icons.cancel_outlined,
                                ),
                                InfoRow(
                                  label: 'Successful payments',
                                  value: '${_stats!.successfulPayments}',
                                  icon: Icons.verified_outlined,
                                ),
                                InfoRow(
                                  label: 'Total collected',
                                  value: Fmt.money(
                                    _stats!.totalCollected,
                                    decimals: true,
                                  ),
                                  icon: Icons.account_balance_wallet_outlined,
                                  isLast: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(String name) {
    return ColoredBox(
      color: AppColors.primaryDark,
      child: SafeArea(
        bottom: false,
        child: GradientHeader(
          onNotificationTap: () => _openScreen(const NotificationsScreen()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Fmt.greeting(), style: HeaderText.greeting),
              const SizedBox(height: 2),
              Text(name, style: HeaderText.name),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _stats == null
                    ? 'Operations overview'
                    : '${_stats!.openRequests} open · ${_stats!.pendingPayments} payments to review',
                style: HeaderText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _revenueCard(AdminDashboardStats stats) {
    return AppCard(
      color: AppColors.surface,
      child: Row(
        children: [
          const IconTile(
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.success,
            background: AppColors.successSoft,
            size: 48,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Collected revenue', style: AppText.caption),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.money(stats.totalCollected, decimals: true),
                    style: AppText.metricLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${stats.successfulPayments} successful payments',
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _managementCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _ManageRow(
            icon: Icons.assignment_outlined,
            title: 'Request queue',
            subtitle: 'Assign and track service visits',
            onTap: () => _open(ShellTab.requests, const AdminRequestsScreen()),
          ),
          _ManageRow(
            icon: Icons.groups_outlined,
            title: 'Field team',
            subtitle: 'Approve members and manage availability',
            onTap: () => _open(ShellTab.team, const AdminFieldMembersScreen()),
          ),
          _ManageRow(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Payment verification',
            subtitle: 'Verify customer UPI references',
            onTap: () => _open(ShellTab.payments, const AdminPaymentsScreen()),
          ),
          _ManageRow(
            icon: Icons.storefront_outlined,
            title: 'Branches',
            subtitle: 'Add, edit or deactivate a branch',
            onTap: () => _openScreen(const AdminBranchesScreen()),
          ),
          _ManageRow(
            icon: Icons.speed_rounded,
            title: 'Distance rate',
            subtitle: 'Threshold, per-km rate and tax',
            onTap: () => _openScreen(const AdminDistanceRateScreen()),
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({
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
                  Text(
                    title,
                    style: AppText.title.copyWith(fontSize: 14),
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

class _OverviewLoading extends StatelessWidget {
  const _OverviewLoading();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 110, height: 13),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(width: 190, height: 24),
            SizedBox(height: AppSpacing.xxl),
            SkeletonBox(height: 96),
            SizedBox(height: AppSpacing.lg),
            SkeletonBox(height: 120),
            SizedBox(height: AppSpacing.lg),
            SkeletonBox(height: 120),
          ],
        ),
      ),
    );
  }
}
