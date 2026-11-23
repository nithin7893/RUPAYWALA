import 'package:flutter/material.dart';

import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import 'admin_assign_sheet.dart';
import 'admin_request_detail_screen.dart';

/// Admin request queue with the assignment control the backend supports.
class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen> {
  static const _filters = [
    'All',
    'Needs assignment',
    'Active',
    'Completed',
    'Cancelled',
  ];

  List<ServiceRequest> _requests = const [];
  String _filter = 'All';
  bool _loading = true;
  String? _error;
  int? _assigningId;
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
      final requests = await context.api.admin.requests(limit: 200);
      if (!mounted) return;
      setState(() {
        _requests = requests;
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
    switch (_filter) {
      case 'Needs assignment':
        return _requests
            .where((request) =>
                request.assignment == null &&
                !request.isCompleted &&
                !request.isCancelled &&
                !request.isAwaitingPayment)
            .toList(growable: false);
      case 'Active':
        return _requests
            .where((request) => request.isActive)
            .toList(growable: false);
      case 'Completed':
        return _requests
            .where((request) => request.isCompleted)
            .toList(growable: false);
      case 'Cancelled':
        return _requests
            .where((request) => request.isCancelled)
            .toList(growable: false);
      default:
        return _requests;
    }
  }

  bool _canAssign(ServiceRequest request) {
    if (request.requiresPayment) return false;
    return request.stage == RequestStage.paymentComplete ||
        request.stage == RequestStage.waitingForAssignment ||
        request.stage == RequestStage.assigned;
  }

  Future<void> _assign(ServiceRequest request) async {
    if (_assigningId != null) return;
    final member = await showAssignMemberSheet(
      context,
      currentMemberId: request.assignment?.fieldMemberId,
    );
    if (member == null || !mounted) return;

    setState(() => _assigningId = request.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.admin.assignFieldMember(
        requestId: request.id,
        fieldMemberId: member.id,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _assigningId = null);
      messenger.showSnackBar(
        SnackBar(content: Text('Assigned to ${member.displayName}.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _assigningId = null);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not assign: $error')),
      );
    }
  }

  Future<void> _open(ServiceRequest request) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminRequestDetailScreen(
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
        title: 'Requests',
        showBack: false,
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh requests',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 5)
          : _error != null
              ? ErrorStateView(
                  title: 'Requests could not load',
                  message: _error!,
                  onRetry: _load,
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: FilterChipRow(
                        options: _filters,
                        selected: _filter,
                        onSelected: (value) =>
                            setState(() => _filter = value),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: visible.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 60),
                                  EmptyState(
                                    icon: Icons.inbox_outlined,
                                    title: _filter == 'All'
                                        ? 'No requests yet'
                                        : 'Nothing in $_filter',
                                    message: _filter == 'All'
                                        ? 'Customer requests will appear here as soon as they are submitted.'
                                        : 'Try another filter to see more requests.',
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  AppSpacing.md,
                                  AppSpacing.lg,
                                  AppSpacing.xxxl,
                                ),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (context, index) {
                                  final request = visible[index];
                                  return _RequestCard(
                                    request: request,
                                    busy: _assigningId == request.id,
                                    canAssign: _canAssign(request),
                                    onTap: () => _open(request),
                                    onAssign: () => _assign(request),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.canAssign,
    required this.onTap,
    required this.onAssign,
  });

  final ServiceRequest request;
  final bool busy;
  final bool canAssign;
  final VoidCallback onTap;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.forStage(request.stage);
    final assignment = request.assignment;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: style.icon,
                color: style.color,
                background: style.background,
                size: 42,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.requestType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle,
                    ),
                    const SizedBox(height: 2),
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
                color: style.color,
                background: style.background,
                icon: style.icon,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (request.customerAddress?.isNotEmpty == true)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    request.customerAddress!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (request.branchName?.isNotEmpty == true)
                MetaPill(
                  label: request.branchName!,
                  icon: Icons.storefront_outlined,
                ),
              if (request.distanceKm != null)
                MetaPill(
                  label: Fmt.km(request.distanceKm),
                  icon: Icons.route_outlined,
                ),
              if (request.requiresPayment && !request.chargePaid)
                MetaPill(
                  label: 'Payment due',
                  icon: Icons.payments_outlined,
                  color: AppColors.warning,
                  background: AppColors.warningSoft,
                ),
              MetaPill(
                label: assignment == null
                    ? 'Unassigned'
                    : (assignment.displayName),
                icon: assignment == null
                    ? Icons.person_search_outlined
                    : Icons.person_outline,
                color: assignment == null
                    ? AppColors.warning
                    : AppColors.primary,
                background:
                    assignment == null ? AppColors.warningSoft : AppColors.primarySoft,
              ),
            ],
          ),
          if (canAssign) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    assignment == null
                        ? 'Waiting for a field member'
                        : 'Assigned to ${assignment.displayName}',
                    style: AppText.caption.copyWith(fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onAssign,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.person_add_alt_1_outlined,
                          size: 17,
                        ),
                  label: Text(assignment == null ? 'Assign' : 'Reassign'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
