import 'package:flutter/material.dart';

import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import 'admin_assign_sheet.dart';

/// Admin view of one request with the assignment and cancellation controls the
/// backend actually exposes.
class AdminRequestDetailScreen extends StatefulWidget {
  const AdminRequestDetailScreen({
    super.key,
    required this.requestId,
    this.initialRequest,
  });

  final int requestId;
  final ServiceRequest? initialRequest;

  @override
  State<AdminRequestDetailScreen> createState() =>
      _AdminRequestDetailScreenState();
}

class _AdminRequestDetailScreenState extends State<AdminRequestDetailScreen> {
  ServiceRequest? _request;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _request = widget.initialRequest;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(initial: widget.initialRequest != null);
  }

  Future<void> _load({bool initial = false}) async {
    if (!initial) setState(() => _loading = true);
    try {
      final requests = await context.api.admin.requests(limit: 500);
      ServiceRequest? match;
      for (final request in requests) {
        if (request.id == widget.requestId) {
          match = request;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _request = match ?? _request;
        _loading = false;
        _error = match == null
            ? 'This request is no longer in the admin queue.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  bool get _canAssign {
    final request = _request;
    if (request == null) return false;
    if (request.requiresPayment) return false;
    return request.stage == RequestStage.paymentComplete ||
        request.stage == RequestStage.waitingForAssignment ||
        request.stage == RequestStage.assigned;
  }

  bool get _canUnassign {
    final request = _request;
    return request != null &&
        request.assignment != null &&
        !request.isCompleted &&
        !request.isCancelled;
  }

  Future<void> _assign() async {
    final request = _request;
    if (request == null || _busy) return;
    final member = await showAssignMemberSheet(
      context,
      currentMemberId: request.assignment?.fieldMemberId,
    );
    if (member == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.admin.assignFieldMember(
        requestId: request.id,
        fieldMemberId: member.id,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Assigned to ${member.displayName}.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not assign: $error')),
      );
    }
  }

  Future<void> _unassign() async {
    final request = _request;
    if (request == null || _busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Release this assignment?',
      message:
          'The field member will be removed from the request and it returns to the assignment queue.',
      confirmLabel: 'Release',
      icon: Icons.person_remove_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => context.api.admin.unassignFieldMember(request.id),
      success: 'Assignment released.',
    );
  }

  Future<void> _cancel() async {
    final request = _request;
    if (request == null || _busy) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.isCompleted
                    ? 'The request is completed. Cancelling refunds the consumed visit to the customer.'
                    : 'The customer is notified and the visit is not scheduled.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: reason,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    await _run(
      () => context.api.admin.cancelRequest(
        request.id,
        reason: text.isEmpty ? null : text,
      ),
      success: 'Request cancelled.',
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Action failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Request ${request?.reference ?? ''}',
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh request',
            onPressed: _loading ? () {} : () => _load(),
          ),
        ],
      ),
      body: _loading && request == null
          ? const SkeletonList(itemCount: 3)
          : request == null
              ? ErrorStateView(
                  title: 'Request unavailable',
                  message: _error ?? 'This request could not be loaded.',
                  onRetry: () => _load(),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(),
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
                      if (_error != null) ...[
                        InfoBanner(
                          tone: InfoTone.warning,
                          title: 'Showing saved details',
                          message: _error!,
                          action: TextButton(
                            onPressed: () => _load(),
                            child: const Text('Retry'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      RequestSummaryCard(request: request),
                      if (request.chargePaid == false ||
                          request.requiresPayment ||
                          request.extraCharge > 0) ...[
                        const SizedBox(height: AppSpacing.md),
                        ChargeBreakdownCard(
                          baseAmount: 0,
                          extraCharge: request.extraCharge,
                          taxAmount: request.taxAmount,
                          totalAmount: request.totalAmount,
                          chargePaid: request.chargePaid,
                          requiresPayment: request.requiresPayment,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Assignment'),
                      if (request.assignment != null)
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  AppAvatar(
                                    initials: Fmt.initials(
                                      request.assignment!.displayName,
                                    ),
                                    size: 44,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          request.assignment!.displayName,
                                          style: AppText.cardTitle,
                                        ),
                                        if (request.assignment!.employeeCode
                                                ?.isNotEmpty ==
                                            true)
                                          Text(
                                            'Executive ${request.assignment!.employeeCode}',
                                            style: AppText.caption,
                                          ),
                                      ],
                                    ),
                                  ),
                                  StatusBadge(
                                    label: 'Assigned',
                                    color: AppColors.primary,
                                    background: AppColors.primarySoft,
                                    icon: Icons.person_outline,
                                    dense: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              InfoRow(
                                label: 'Assigned on',
                                value: Fmt.dateTime(request.assignedAt),
                                icon: Icons.event_outlined,
                                isLast: true,
                              ),
                            ],
                          ),
                        )
                      else
                        AppCard(
                          color: AppColors.surfaceMuted,
                          elevated: false,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.person_search_outlined,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  request.requiresPayment && !request.chargePaid
                                      ? 'Assignment is blocked until the customer pays the distance charge.'
                                      : 'No field member is assigned yet.',
                                  style: AppText.bodyMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Progress'),
                      AppCard(child: RequestTimeline(request: request)),
                      if (request.completionNotes?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoBanner(
                          tone: InfoTone.success,
                          icon: Icons.task_alt_rounded,
                          title: 'Completion notes',
                          message: request.completionNotes!,
                        ),
                      ],
                      if (request.proofImageUrl?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Proof document', style: AppText.cardTitle),
                              const SizedBox(height: AppSpacing.sm),
                              SecureDocumentImage(documentPath: request.proofImageUrl),
                            ],
                          ),
                        ),
                      ],
                      if (request.cancellationReason?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoBanner(
                          tone: InfoTone.warning,
                          icon: Icons.cancel_outlined,
                          title: 'Cancellation reason',
                          message: request.cancellationReason!,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Actions'),
                      if (_canAssign) ...[
                        AppButton(
                          label: request.assignment == null
                              ? 'Assign field member'
                              : 'Reassign field member',
                          icon: Icons.person_add_alt_1_outlined,
                          isLoading: _busy,
                          onPressed: _busy ? null : _assign,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (_canUnassign) ...[
                        AppButton(
                          label: 'Release assignment',
                          icon: Icons.person_remove_outlined,
                          variant: AppButtonVariant.secondary,
                          onPressed: _busy ? null : _unassign,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (!request.isCancelled)
                        AppButton(
                          label: 'Cancel request',
                          icon: Icons.close_rounded,
                          variant: AppButtonVariant.danger,
                          onPressed: _busy ? null : _cancel,
                        ),
                      if (!_canAssign && !_canUnassign && request.isCancelled)
                        const InfoBanner(
                          tone: InfoTone.info,
                          message: 'This request is cancelled. No further action is available.',
                        ),
                    ],
                  ),
                ),
    );
  }
}
