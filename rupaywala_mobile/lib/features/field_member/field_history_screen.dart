import 'package:flutter/material.dart';

import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import 'field_job_card.dart';
import 'field_task_detail_screen.dart';

/// Completed visits for the signed-in field member.
class FieldHistoryScreen extends StatefulWidget {
  const FieldHistoryScreen({super.key});

  @override
  State<FieldHistoryScreen> createState() => _FieldHistoryScreenState();
}

class _FieldHistoryScreenState extends State<FieldHistoryScreen> {
  List<FieldMemberJob> _jobs = const [];
  FieldMemberStats? _stats;
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
        api.fieldMember.assignments(statuses: const ['completed']),
        api.fieldMember.stats(),
      ]);
      if (!mounted) return;
      final jobs = (results[0] as List<FieldMemberJob>).toList()
        ..sort((a, b) {
          final left = a.completedAt ?? a.createdAt;
          final right = b.completedAt ?? b.createdAt;
          if (left == null && right == null) return b.requestId - a.requestId;
          if (left == null) return 1;
          if (right == null) return -1;
          return right.compareTo(left);
        });
      setState(() {
        _jobs = jobs;
        _stats = results[1] as FieldMemberStats;
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

  Future<void> _open(FieldMemberJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FieldTaskDetailScreen(
          requestId: job.requestId,
          initialJob: job,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'History',
        showBack: false,
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh history',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 4)
          : _error != null
              ? ErrorStateView(
                  title: 'History could not load',
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: _jobs.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 70),
                            EmptyState(
                              icon: Icons.history_rounded,
                              title: 'No completed visits yet',
                              message:
                                  'Visits you complete will be listed here for your records.',
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.xxxl,
                          ),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: StatTile(
                                    label: 'Completed visits',
                                    value: '${_stats?.completed ?? _jobs.length}',
                                    icon: Icons.task_alt_rounded,
                                    color: AppColors.success,
                                    background: AppColors.successSoft,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: StatTile(
                                    label: 'Completed today',
                                    value: '${_stats?.completedToday ?? 0}',
                                    icon: Icons.today_rounded,
                                    color: AppColors.primary,
                                    background: AppColors.primarySoft,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SectionHeader(
                              title: 'Recent visits',
                              subtitle: _stats == null
                                  ? null
                                  : 'Last completed ${Fmt.dateTime(_jobs.first.completedAt)}',
                            ),
                            for (final job in _jobs)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: AppSpacing.sm),
                                child: FieldJobCard(
                                  job: job,
                                  onTap: () => _open(job),
                                ),
                              ),
                          ],
                        ),
                ),
    );
  }
}
