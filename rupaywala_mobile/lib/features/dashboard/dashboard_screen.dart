import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../service/request_detail_screen.dart';
import '../shell/role_shell.dart';
import '../subscription/subscription_screen.dart';

/// Customer home.
///
/// Everything on this screen is real: the greeting comes from the restored
/// session, membership from `/subscriptions`, visit allowances from the balance
/// endpoint, and the request cards from `/service/my-requests`. Sections fail
/// independently so one slow endpoint never blanks the whole page.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  CustomerProfile? _profile;
  List<Policy> _policies = const [];
  CustomerSubscription? _subscription;
  VisitBalance? _balance;
  List<ServiceRequest> _requests = const [];
  int _unread = 0;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _fatalError;
  String? _requestsError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedOnce) return;
    _loadedOnce = true;
    _load();
  }

  Future<(T?, Object?)> _attempt<T>(Future<T> Function() action) async {
    try {
      return (await action(), null);
    } catch (error) {
      return (null, error);
    }
  }

  Future<void> _load() async {
    final api = context.api;
    if (mounted) {
      setState(() {
        _loading = true;
        _fatalError = null;
      });
    }

    final profileFuture = _attempt(api.customer.profile);
    final policiesFuture = _attempt(api.customer.policies);
    final subscriptionFuture = _attempt(api.subscriptions.currentSubscription);
    final balanceFuture = _attempt(api.subscriptions.visitBalance);
    final requestsFuture = _attempt(api.service.myRequests);
    final unreadFuture = _attempt(api.notifications.unreadCount);

    await Future.wait([
      profileFuture,
      policiesFuture,
      subscriptionFuture,
      balanceFuture,
      requestsFuture,
      unreadFuture,
    ]);

    if (!mounted) return;

    final profile = await profileFuture;
    final policies = await policiesFuture;
    final subscription = await subscriptionFuture;
    final balance = await balanceFuture;
    final requests = await requestsFuture;
    final unread = await unreadFuture;

    setState(() {
      _profile = profile.$1;
      _policies = policies.$1 ?? const [];
      _subscription = subscription.$1;
      _balance = balance.$1;
      _requests = requests.$1 ?? const [];
      _requestsError = requests.$1 == null ? _message(requests.$2) : null;
      _unread = unread.$1 ?? _unread;
      _loading = false;

      // Only a total failure is treated as fatal. A missing subscription is a
      // normal state, not an error.
      final everythingFailed = profile.$1 == null &&
          policies.$1 == null &&
          requests.$1 == null &&
          subscription.$1 == null;
      _fatalError = everythingFailed ? _message(requests.$2) : null;
    });
  }

  String _message(Object? error) {
    if (error == null) return 'This information is unavailable right now.';
    return '$error';
  }

  Future<void> _refresh() async {
    final session = context.session;
    await _load();
    await session.refresh();
  }

  void _open(ShellTab tab) => context.openShellTab(tab);

  Future<void> _openNotifications() async {
    final api = context.api;
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    try {
      final count = await api.notifications.unreadCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {}
  }

  ServiceRequest? get _activeRequest {
    for (final request in _requests) {
      if (request.isActive ||
          request.isAwaitingPayment ||
          (request.isOpen && !request.isCompleted && !request.isCancelled)) {
        return request;
      }
    }
    return null;
  }

  bool get _needsProfile =>
      context.session.session?.profileCompleted == false ||
      (_profile != null && !_profile!.profileCompleted);

  @override
  Widget build(BuildContext context) {
    final session = context.session.session;
    final name = session?.displayName ?? 'there';

    return Scaffold(
      body: _loading
          ? const _HomeLoading()
          : RefreshIndicator(
              onRefresh: _refresh,
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
                        if (_fatalError != null)
                          ErrorStateView(
                            title: 'Home could not load',
                            message: _fatalError!,
                            onRetry: _load,
                          )
                        else ...[
                          if (_needsProfile) ...[
                            InfoBanner(
                              tone: InfoTone.warning,
                              icon: Icons.badge_outlined,
                              title: 'Finish your profile',
                              message:
                                  'Add your personal and address details so we can serve you faster.',
                              action: TextButton(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ProfileScreen(
                                        existing: _profile,
                                      ),
                                    ),
                                  );
                                  if (mounted) _load();
                                },
                                child: const Text('Complete profile'),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          _membershipCard(),
                          const SizedBox(height: AppSpacing.xl),
                          _requestCta(),
                          const SizedBox(height: AppSpacing.lg),
                          _shortcutRow(),
                          const SizedBox(height: AppSpacing.xxl),
                          _activeRequestSection(),
                          _policiesSection(),
                          _recentRequestsSection(),
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
    final subscription = _subscription;
    final balance = _balance;
    final active = subscription?.isActive == true;

    return ColoredBox(
      color: AppColors.primaryDark,
      child: SafeArea(
        bottom: false,
        child: GradientHeader(
          onNotificationTap: _openNotifications,
          notificationCount: _unread,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Fmt.greeting(), style: HeaderText.greeting),
              const SizedBox(height: 2),
              Text(name, style: HeaderText.name),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          active
                              ? Icons.verified_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.onDarkAccent,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            active
                                ? '${balance?.remainingVisits ?? subscription!.remainingVisits} visits left'
                                : 'No active plan',
                            style: HeaderText.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SubscriptionScreen(),
                        ),
                      );
                      if (mounted) _load();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                    ),
                    child: Text(active ? 'Manage plan' : 'View plans'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _membershipCard() {
    final subscription = _subscription;
    final balance = _balance;
    if (subscription == null || !subscription.isActive) {
      return AppCard(
        child: Row(
          children: [
            _IconBadge(icon: Icons.card_membership_outlined),
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
              onPressed: _openSubscription,
              child: const Text('View plans'),
            ),
          ],
        ),
      );
    }

    final remaining = balance?.remainingVisits ?? subscription.remainingVisits;
    final total = balance?.totalVisits ?? subscription.totalVisits;
    final progress = total > 0 ? (total - remaining) / total : 0.0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: Icons.verified_user_outlined),
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
                      subscription.isExpiringSoon
                          ? 'Expiring soon · ${Fmt.date(subscription.endDate)}'
                          : 'Valid till ${Fmt.date(subscription.endDate)}',
                      style: AppText.caption.copyWith(
                        color: subscription.isExpiringSoon
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$remaining',
                style: AppText.metric.copyWith(color: AppColors.primary),
              ),
              const SizedBox(width: 2),
              Text(
                '/ $total',
                style: AppText.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.primary.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text('Visits remaining', style: AppText.caption),
              ),
              TextButton(
                onPressed: _openSubscription,
                child: const Text('Plan details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSubscription() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()),
    );
  }

  Widget _requestCta() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(ShellTab.request),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppElevation.raised,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request a service',
                        style: TextStyle(
                          fontFamily: AppText.fontFamily,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Book a doorstep visit in three guided steps',
                        style: TextStyle(
                          fontFamily: AppText.fontFamily,
                          fontSize: 12.5,
                          height: 1.35,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shortcutRow() {
    return Row(
      children: [
        Expanded(
          child: _Shortcut(
            icon: Icons.receipt_long_outlined,
            label: 'Requests',
            detail: '${_requests.length} total',
            onTap: () => _open(ShellTab.requests),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Shortcut(
            icon: Icons.shield_outlined,
            label: 'Policies',
            detail: '${_policies.length} saved',
            onTap: () => _open(ShellTab.policies),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Shortcut(
            icon: Icons.person_outline_rounded,
            label: 'Profile',
            detail: 'Account',
            onTap: () => _open(ShellTab.profile),
          ),
        ),
      ],
    );
  }

  Widget _activeRequestSection() {
    final active = _activeRequest;
    if (_requestsError != null && _requests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: InfoBanner(
          tone: InfoTone.error,
          title: 'Requests unavailable',
          message: _requestsError!,
          action: TextButton(onPressed: _load, child: const Text('Retry')),
        ),
      );
    }
    if (active == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'In progress'),
        AppCard(
          onTap: () => _openRequest(active),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBadge(
                    icon: Icons.local_shipping_outlined,
                    color: AppColors.secondary,
                    background: AppColors.secondarySoft,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(active.requestType, style: AppText.cardTitle),
                        Text(
                          active.reference,
                          style: AppText.caption.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: active.statusLabel,
                    color: AppColors.info,
                    background: AppColors.infoSoft,
                    icon: Icons.sync_rounded,
                  ),
                ],
              ),
              if (active.assignment?.displayName != null) ...[
                const SizedBox(height: AppSpacing.md),
                InfoRow(
                  label: 'Assigned to',
                  value: active.assignment!.displayName,
                  icon: Icons.support_agent_outlined,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Track every step of this request',
                      style: AppText.caption,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _policiesSection() {
    if (_policies.isEmpty) return const SizedBox.shrink();
    final latest = _policies.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Your policies',
          actionLabel: 'View all',
          onAction: () => _open(ShellTab.policies),
        ),
        AppCard(
          onTap: () => _open(ShellTab.policies),
          child: Row(
            children: [
              _IconBadge(icon: Icons.shield_outlined, tone: _Tone.info),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(latest.title, style: AppText.cardTitle),
                    Text(
                      '${latest.providerName} · ${latest.policyNumber}',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              Text(
                '${_policies.length}',
                style: AppText.sectionTitle.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _recentRequestsSection() {
    final completed = _requests
        .where((request) => request != _activeRequest)
        .take(3)
        .toList();
    if (completed.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent requests',
          actionLabel: 'See all',
          onAction: () => _open(ShellTab.requests),
        ),
        for (final request in completed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _RecentRequestTile(
              request: request,
              onTap: () => _openRequest(request),
            ),
          ),
      ],
    );
  }

  void _openRequest(ServiceRequest request) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => RequestDetailScreen(
          requestId: request.id,
          initialRequest: request,
        ),
      ),
    )
        .then((_) {
      if (mounted) _load();
    });
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 120, height: 14),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(width: 210, height: 26),
            SizedBox(height: AppSpacing.xxl),
            ListCardSkeleton(),
            SizedBox(height: AppSpacing.lg),
            ListCardSkeleton(),
            SizedBox(height: AppSpacing.lg),
            ListCardSkeleton(),
          ],
        ),
      ),
    );
  }
}

enum _Tone { primary, info }

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    this.tone = _Tone.primary,
    this.color,
    this.background,
  });

  final IconData icon;
  final _Tone tone;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ?? (tone == _Tone.info ? AppColors.info : AppColors.primary);
    final resolvedBackground = background ??
        (tone == _Tone.info ? AppColors.infoSoft : AppColors.primarySoft);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, size: 21, color: resolved),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title.copyWith(fontSize: 13),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRequestTile extends StatelessWidget {
  const _RecentRequestTile({required this.request, required this.onTap});

  final ServiceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.requestType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title.copyWith(fontSize: 14),
                ),
                Text(
                  '${request.reference} · ${Fmt.relative(request.createdAt)}',
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusBadge(
            label: request.statusLabel,
            dense: true,
          ),
        ],
      ),
    );
  }
}
