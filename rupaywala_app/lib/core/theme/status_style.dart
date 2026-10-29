import 'package:flutter/material.dart';

import '../models/service_models.dart';
import 'app_tokens.dart';

/// Resolves a backend status string into a colour, an icon and a label.
///
/// Status is never communicated by colour alone — every badge also carries an
/// icon and the status text, which is both an accessibility requirement and
/// what the design brief asks for.
class StatusStyle {
  const StatusStyle({
    required this.label,
    required this.color,
    required this.background,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData icon;

  /// Request lifecycle statuses, mirroring `RequestStage`.
  static StatusStyle forStage(RequestStage stage) {
    switch (stage) {
      case RequestStage.requested:
        return const StatusStyle(
          label: 'Submitted',
          color: AppColors.info,
          background: AppColors.infoSoft,
          icon: Icons.receipt_long_outlined,
        );
      case RequestStage.paymentPending:
        return const StatusStyle(
          label: 'Payment pending',
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.payments_outlined,
        );
      case RequestStage.paymentComplete:
        return const StatusStyle(
          label: 'Payment done',
          color: AppColors.secondaryDark,
          background: AppColors.secondarySoft,
          icon: Icons.task_alt_outlined,
        );
      case RequestStage.waitingForAssignment:
        return const StatusStyle(
          label: 'Finding an agent',
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.hourglass_empty_outlined,
        );
      case RequestStage.assigned:
        return const StatusStyle(
          label: 'Assigned',
          color: AppColors.info,
          background: AppColors.infoSoft,
          icon: Icons.person_outline,
        );
      case RequestStage.inProgress:
        return const StatusStyle(
          label: 'In progress',
          color: AppColors.primary,
          background: AppColors.primarySoft,
          icon: Icons.sync_alt_outlined,
        );
      case RequestStage.completed:
        return const StatusStyle(
          label: 'Completed',
          color: AppColors.success,
          background: AppColors.successSoft,
          icon: Icons.check_circle_outline,
        );
      case RequestStage.cancelled:
        return const StatusStyle(
          label: 'Cancelled',
          color: AppColors.error,
          background: AppColors.errorSoft,
          icon: Icons.cancel_outlined,
        );
    }
  }

  /// Payment statuses, mirroring `PaymentStatus`.
  static StatusStyle forPayment(String status) {
    switch (status) {
      case 'pending':
        return const StatusStyle(
          label: 'Awaiting payment',
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.schedule_outlined,
        );
      case 'pending_verification':
        return const StatusStyle(
          label: 'Under review',
          color: AppColors.info,
          background: AppColors.infoSoft,
          icon: Icons.manage_search_outlined,
        );
      case 'success':
        return const StatusStyle(
          label: 'Paid',
          color: AppColors.success,
          background: AppColors.successSoft,
          icon: Icons.verified_outlined,
        );
      case 'failed':
        return const StatusStyle(
          label: 'Failed',
          color: AppColors.error,
          background: AppColors.errorSoft,
          icon: Icons.error_outline,
        );
      case 'expired':
        return const StatusStyle(
          label: 'Expired',
          color: AppColors.textSecondary,
          background: AppColors.neutralSoft,
          icon: Icons.timer_off_outlined,
        );
      case 'cancelled':
        return const StatusStyle(
          label: 'Cancelled',
          color: AppColors.error,
          background: AppColors.errorSoft,
          icon: Icons.cancel_outlined,
        );
      default:
        return _unknown(status);
    }
  }

  /// Field member approval statuses.
  static StatusStyle forApproval(String status) {
    switch (status) {
      case 'approved':
        return const StatusStyle(
          label: 'Approved',
          color: AppColors.success,
          background: AppColors.successSoft,
          icon: Icons.verified_outlined,
        );
      case 'rejected':
        return const StatusStyle(
          label: 'Rejected',
          color: AppColors.error,
          background: AppColors.errorSoft,
          icon: Icons.block_outlined,
        );
      case 'suspended':
        return const StatusStyle(
          label: 'Suspended',
          color: AppColors.error,
          background: AppColors.errorSoft,
          icon: Icons.pause_circle_outline,
        );
      default:
        return const StatusStyle(
          label: 'Awaiting approval',
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.hourglass_empty_outlined,
        );
    }
  }

  /// Subscription statuses.
  static StatusStyle forSubscription(String status) {
    switch (status) {
      case 'active':
        return const StatusStyle(
          label: 'Active',
          color: AppColors.success,
          background: AppColors.successSoft,
          icon: Icons.check_circle_outline,
        );
      case 'expired':
        return const StatusStyle(
          label: 'Expired',
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.event_busy_outlined,
        );
      case 'cancelled':
        return const StatusStyle(
          label: 'Cancelled',
          color: AppColors.error,
          background: AppColors.errorSoft,
          icon: Icons.cancel_outlined,
        );
      default:
        return const StatusStyle(
          label: 'Pending activation',
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.schedule_outlined,
        );
    }
  }

  /// Generic resolution used by policy validity and account status.
  static StatusStyle forGeneric(String status) {
    switch (status) {
      case 'active':
      case 'approved':
      case 'completed':
      case 'success':
      case 'paid':
        return forStage(RequestStage.completed);
      case 'pending':
      case 'waiting':
      case 'expired':
        return forStage(RequestStage.waitingForAssignment);
      case 'cancelled':
      case 'rejected':
      case 'failed':
      case 'suspended':
        return forStage(RequestStage.cancelled);
      case 'in_progress':
        return forStage(RequestStage.inProgress);
      case 'assigned':
        return forStage(RequestStage.assigned);
      default:
        return _unknown(status);
    }
  }

  static StatusStyle _unknown(String status) {
    return StatusStyle(
      label: _titleCase(status),
      color: AppColors.textSecondary,
      background: AppColors.neutralSoft,
      icon: Icons.circle_outlined,
    );
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value
        .split(RegExp(r'[_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

/// Maps the backend's service-type icon slug onto a Material icon so the app
/// keeps one consistent icon family.
IconData serviceTypeIcon(String? slug) {
  switch (slug) {
    case 'assignment':
      return Icons.assignment_outlined;
    case 'description':
      return Icons.description_outlined;
    case 'search':
      return Icons.search_outlined;
    case 'support_agent':
      return Icons.support_agent_outlined;
    default:
      return Icons.handyman_outlined;
  }
}
