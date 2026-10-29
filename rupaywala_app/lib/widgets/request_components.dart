import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/service_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';

/// The status timeline shown on every request detail screen.
///
/// Reads top to bottom so a customer can answer "where is my request?" without
/// needing to understand the status enum.
class RequestTimeline extends StatelessWidget {
  const RequestTimeline({super.key, required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final events = _events(request);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < events.length; i++)
          _TimelineRow(
            event: events[i],
            isLast: i == events.length - 1,
            isPending: events[i].timestamp == null,
          ),
      ],
    );
  }

  static List<_TimelineEvent> _events(ServiceRequest request) {
    final current = request.stage;

    // Steps in the order they actually happen.
    final steps = <(RequestStage, IconData, String)>[
      (
        RequestStage.requested,
        Icons.receipt_long_outlined,
        'Request submitted'
      ),
      if (request.requiresPayment || !request.chargePaid)
        (
          RequestStage.paymentPending,
          Icons.payments_outlined,
          'Distance charge'
        ),
      (
        RequestStage.waitingForAssignment,
        Icons.hourglass_empty_outlined,
        'Finding a field member'
      ),
      (RequestStage.assigned, Icons.person_outline, 'Field member assigned'),
      (RequestStage.inProgress, Icons.sync_alt_outlined, 'Service in progress'),
      (RequestStage.completed, Icons.check_circle_outline, 'Service completed'),
    ];

    final cancelIndex = steps.indexWhere((s) => s.$1 == current);
    final isCancelled = current == RequestStage.cancelled;

    final result = <_TimelineEvent>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final DateTime? timestamp = switch (step.$1) {
        RequestStage.requested => request.createdAt,
        RequestStage.paymentPending =>
          request.requiresPayment ? null : request.createdAt,
        RequestStage.waitingForAssignment => request.createdAt,
        RequestStage.assigned => request.assignedAt,
        RequestStage.inProgress => request.startedAt,
        RequestStage.completed => request.completedAt,
        _ => null,
      };
      final reached = isCancelled
          ? i <= 0
          : (cancelIndex >= 0 ? i <= cancelIndex : step.$1 == current);
      result.add(_TimelineEvent(
        label: step.$3,
        icon: step.$2,
        timestamp: reached ? timestamp : null,
        note: step.$1 == current && isCancelled
            ? request.cancellationReason
            : null,
      ));
    }

    if (isCancelled) {
      result.add(_TimelineEvent(
        label: 'Cancelled',
        icon: Icons.cancel_outlined,
        timestamp: request.completedAt ?? request.createdAt,
        note: request.cancellationReason,
      ));
    }

    return result;
  }
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.label,
    required this.icon,
    this.timestamp,
    this.note,
  });

  final String label;
  final IconData icon;
  final DateTime? timestamp;
  final String? note;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.isLast,
    required this.isPending,
  });

  final _TimelineEvent event;
  final bool isLast;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final done = event.timestamp != null || !isPending;
    final active = done && (event.timestamp != null || isPending) && !isLast;

    final dotColor = done ? AppColors.secondary : AppColors.border;
    final textColor = done ? AppColors.textPrimary : AppColors.textHint;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: done ? AppColors.secondarySoft : AppColors.neutralSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: dotColor),
                ),
                child: Icon(
                  event.icon,
                  size: 14,
                  color: done ? AppColors.secondaryDark : AppColors.textHint,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: active ? AppColors.secondary : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.label,
                          style: AppText.title.copyWith(
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ),
                      if (event.timestamp != null)
                        Text(
                          Fmt.shortDate(event.timestamp),
                          style: AppText.caption.copyWith(fontSize: 11.5),
                        ),
                    ],
                  ),
                  if (event.note != null && event.note!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.note!,
                      style: AppText.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full request summary, shared by the customer, field member and admin detail
/// screens so the three never drift apart.
class RequestSummaryCard extends StatelessWidget {
  const RequestSummaryCard({
    super.key,
    required this.request,
    this.extraRows = const [],
  });

  final ServiceRequest request;
  final List<Widget> extraRows;

  @override
  Widget build(BuildContext context) {
    final status = StatusStyle.forStage(request.stage);

    return AppCard(
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
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.reference,
                      style: AppText.caption.copyWith(
                        color: AppColors.textHint,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                label: request.statusLabel,
                color: status.color,
                background: status.background,
                icon: status.icon,
              ),
            ],
          ),
          if (request.description != null &&
              request.description!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(request.description!.trim(), style: AppText.bodyMuted),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          if (request.policyLabel != null)
            InfoRow(
                label: 'Policy',
                value: request.policyLabel!,
                icon: Icons.shield_outlined),
          InfoRow(
            label: 'Branch',
            value: request.branchName ?? 'Not selected',
            icon: Icons.storefront_outlined,
          ),
          if (request.customerAddress != null)
            InfoRow(
              label: 'Visit address',
              value: request.customerAddress!,
              icon: Icons.location_on_outlined,
            ),
          if (request.distanceKm != null)
            InfoRow(
              label: 'Distance from branch',
              value: Fmt.km(request.distanceKm),
              icon: Icons.route_outlined,
            ),
          if (request.durationMinutes != null && request.durationMinutes! > 0)
            InfoRow(
              label: 'Estimated travel',
              value: Fmt.duration(request.durationMinutes),
              icon: Icons.schedule_outlined,
            ),
          InfoRow(
            label: 'Submitted',
            value: Fmt.dateTime(request.createdAt),
            icon: Icons.event_outlined,
          ),
          ...extraRows,
        ],
      ),
    );
  }
}

/// The charge breakdown, shown once the distance is known.
class ChargeBreakdownCard extends StatelessWidget {
  const ChargeBreakdownCard({
    super.key,
    required this.baseAmount,
    required this.extraCharge,
    required this.taxAmount,
    required this.totalAmount,
    this.chargePaid = true,
    this.requiresPayment = false,
    this.trailingAction,
    this.note,
  });

  final double baseAmount;
  final double extraCharge;
  final double taxAmount;
  final double totalAmount;
  final bool chargePaid;
  final bool requiresPayment;
  final Widget? trailingAction;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final payable = requiresPayment && !chargePaid;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Charge summary', style: AppText.cardTitle),
              ),
              if (requiresPayment)
                StatusBadge(
                  label: chargePaid ? 'Charge paid' : 'Payment due',
                  color: chargePaid ? AppColors.success : AppColors.warning,
                  background: chargePaid
                      ? AppColors.successSoft
                      : AppColors.warningSoft,
                  icon: chargePaid
                      ? Icons.check_circle_outline
                      : Icons.payments_outlined,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (note != null) ...[
            Text(note!, style: AppText.caption),
            const SizedBox(height: AppSpacing.sm),
          ],
          InfoRow(label: 'Included visit charge', value: Fmt.money(baseAmount)),
          if (extraCharge > 0)
            InfoRow(
              label: 'Extra distance charge',
              value: Fmt.money(extraCharge),
            ),
          if (taxAmount > 0)
            InfoRow(label: 'Tax', value: Fmt.money(taxAmount, decimals: true)),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text('Total payable', style: AppText.cardTitle),
                ),
                Text(
                  Fmt.money(totalAmount, decimals: true),
                  style: payable
                      ? AppText.metric.copyWith(color: AppColors.warning)
                      : AppText.metric.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          if (trailingAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            trailingAction!,
          ],
        ],
      ),
    );
  }
}

/// The assigned field member card shown to the customer.
class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final assignment = request.assignment;
    if (assignment == null) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(
                icon: Icons.support_agent_outlined,
                color: AppColors.primary,
                background: AppColors.primarySoft,
                size: 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(assignment.displayName, style: AppText.cardTitle),
                    if (assignment.employeeCode != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Executive ${assignment.employeeCode}',
                        style: AppText.caption,
                      ),
                    ],
                  ],
                ),
              ),
              if (assignment.fieldMemberPhone != null &&
                  assignment.fieldMemberPhone!.isNotEmpty)
                IconButton(
                  onPressed: () => _call(context, assignment.fieldMemberPhone!),
                  icon: const Icon(Icons.call_outlined),
                  color: AppColors.primary,
                  tooltip: 'Call field member',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primarySoft,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          InfoRow(
            label: 'Assigned',
            value: Fmt.dateTime(request.assignedAt),
            isLast: true,
          ),
        ],
      ),
    );
  }

  void _call(BuildContext context, String phone) {
    // Clipboard fallback: the app has no url_launcher dependency, so a tap
    // copies the number rather than doing nothing.
    final messenger = ScaffoldMessenger.of(context);
    Clipboard.setData(ClipboardData(text: phone));
    messenger.showSnackBar(
      SnackBar(content: Text('Field member number $phone copied')),
    );
  }
}
