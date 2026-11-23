import 'package:flutter/material.dart';

import '../../core/models/ops_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';

/// Task row shared by the field member's Today and History tabs.
class FieldJobCard extends StatelessWidget {
  const FieldJobCard({
    super.key,
    required this.job,
    required this.onTap,
  });

  final FieldMemberJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.forStage(job.stage);
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
                icon: job.isDone
                    ? Icons.task_alt_rounded
                    : (job.canComplete
                        ? Icons.sync_alt_rounded
                        : Icons.assignment_outlined),
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
                      job.requestType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${job.reference} · ${Fmt.relative(job.createdAt)}',
                      style: AppText.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                label: job.statusLabel,
                color: style.color,
                background: style.background,
                icon: style.icon,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: AppColors.textHint,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  job.customerDisplayName,
                  style: AppText.title.copyWith(fontSize: 13.5),
                ),
              ),
              if (job.distanceKm != null)
                Text(
                  Fmt.km(job.distanceKm),
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
            ],
          ),
          if (job.customerAddress?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
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
                    job.customerAddress!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                job.canStart
                    ? Icons.play_circle_outline
                    : (job.canComplete
                        ? Icons.check_circle_outline
                        : Icons.history_rounded),
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  job.canStart
                      ? 'Ready to start'
                      : (job.canComplete
                          ? 'In progress — finish to close'
                          : (job.isDone
                              ? 'Completed ${Fmt.date(job.completedAt)}'
                              : job.statusLabel)),
                  style: AppText.caption.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textHint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
