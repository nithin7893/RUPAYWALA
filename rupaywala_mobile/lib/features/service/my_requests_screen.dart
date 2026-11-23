import 'package:flutter/material.dart';

import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../shell/role_shell.dart';
import 'request_detail_screen.dart';

/// Customer request list with filters and a detail route on every row.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key, this.embedded = true});

  final bool embedded;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<ServiceRequest> _requests = const [];
  bool _loading = true;
  String? _error;
  _RequestFilter _filter = _RequestFilter.all;
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
      final result = await context.api.service.myRequests();
      if (!mounted) return;
      setState(() {
        _requests = result;
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

  List<ServiceRequest> get _visible {
    return _requests.where((request) {
      switch (_filter) {
        case _RequestFilter.all:
          return true;
        case _RequestFilter.active:
          return request.isActive;
        case _RequestFilter.payment:
          return request.isAwaitingPayment ||
              (request.requiresPayment && !request.chargePaid);
        case _RequestFilter.completed:
          return request.isCompleted;
        case _RequestFilter.cancelled:
          return request.isCancelled;
      }
    }).toList();
  }

  int _count(_RequestFilter filter) {
    return switch (filter) {
      _RequestFilter.all => _requests.length,
      _RequestFilter.active => _requests.where((r) => r.isActive).length,
      _RequestFilter.payment => _requests
          .where((r) => r.isAwaitingPayment || (r.requiresPayment && !r.chargePaid))
          .length,
      _RequestFilter.completed =>
        _requests.where((r) => r.isCompleted).length,
      _RequestFilter.cancelled =>
        _requests.where((r) => r.isCancelled).length,
    };
  }

  Future<void> _open(ServiceRequest request) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RequestDetailScreen(
          requestId: request.id,
          initialRequest: request,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'My Requests',
        showBack: !widget.embedded,
        actions: [
          AppBarIconButton(
            icon: Icons.add_rounded,
            tooltip: 'New request',
            onPressed: () => context.openShellTab(ShellTab.request),
          ),
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh requests',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 4)
          : _error != null
              ? ErrorStateView(
                  title: 'Requests could not load',
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _filters()),
                      if (_requests.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No requests yet',
                            subtitle:
                                'When you book a doorstep service it will appear here with live tracking.',
                            actionLabel: 'Request a service',
                            onAction: () => context.openShellTab(ShellTab.request),
                          ),
                        )
                      else if (visible.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: 'Nothing in this filter',
                            subtitle:
                                'Try another status to see your other requests.',
                            actionLabel: 'Show all',
                            onAction: () =>
                                setState(() => _filter = _RequestFilter.all),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.xxxl,
                          ),
                          sliver: SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final request = visible[index];
                              return _RequestTile(
                                request: request,
                                onTap: () => _open(request),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          for (final filter in _RequestFilter.values) ...[
            _FilterChip(
              label: filter.label,
              count: _count(filter),
              selected: _filter == filter,
              onTap: () => setState(() => _filter = filter),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

enum _RequestFilter {
  all('All'),
  active('Active'),
  payment('Payment'),
  completed('Completed'),
  cancelled('Cancelled');

  const _RequestFilter(this.label);

  final String label;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppText.label.copyWith(
                  fontSize: 13,
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : AppColors.neutralSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onTap});

  final ServiceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final due = request.requiresPayment && !request.chargePaid;
    final statusColor = request.isCancelled
        ? AppColors.error
        : (request.isCompleted
            ? AppColors.success
            : (due ? AppColors.warning : AppColors.info));
    final statusBackground = request.isCancelled
        ? AppColors.errorSoft
        : (request.isCompleted
            ? AppColors.successSoft
            : (due ? AppColors.warningSoft : AppColors.infoSoft));

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.requestType,
                      style: AppText.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(request.reference, style: AppText.caption),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                label: request.statusLabel,
                color: statusColor,
                background: statusBackground,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              if (request.branchName != null)
                _Meta(icon: Icons.storefront_outlined, text: request.branchName!),
              if (request.createdAt != null)
                _Meta(
                  icon: Icons.event_outlined,
                  text: Fmt.shortDate(request.createdAt),
                ),
              if (request.distanceKm != null)
                _Meta(
                  icon: Icons.route_outlined,
                  text: Fmt.km(request.distanceKm),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (due)
                Expanded(
                  child: Text(
                    'Payment due ${Fmt.money(request.totalAmount)}',
                    style: AppText.caption.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const Spacer(),
              Text(
                'Track',
                style: AppText.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textHint),
        const SizedBox(width: 3),
        Text(
          text,
          style: AppText.caption.copyWith(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
