import 'package:flutter/material.dart';

import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import 'field_job_card.dart';
import 'field_task_detail_screen.dart';

/// Field member "Today" tab: availability, workload and open visits.
class FieldMemberDashboard extends StatefulWidget {
  const FieldMemberDashboard({super.key});

  @override
  State<FieldMemberDashboard> createState() => _FieldMemberDashboardState();
}

class _FieldMemberDashboardState extends State<FieldMemberDashboard> {
  FieldMemberProfile? _profile;
  FieldMemberStats _stats = const FieldMemberStats();
  List<FieldMemberJob> _jobs = const [];
  bool _loading = true;
  bool _updatingAvailability = false;
  String? _fatalError;
  String? _jobsError;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
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
    setState(() {
      _loading = true;
      _fatalError = null;
    });
    final api = context.api;
    final profile = _attempt(api.fieldMember.profile);
    final stats = _attempt(api.fieldMember.stats);
    final jobs = _attempt(
      () => api.fieldMember.assignments(
        statuses: const ['assigned', 'in_progress'],
      ),
    );
    await Future.wait([profile, stats, jobs]);
    if (!mounted) return;

    final profileResult = await profile;
    final statsResult = await stats;
    final jobsResult = await jobs;

    setState(() {
      _profile = profileResult.$1;
      _stats = statsResult.$1 ?? const FieldMemberStats();
      _jobs = jobsResult.$1 ?? const [];
      _jobsError = jobsResult.$1 == null ? '${jobsResult.$2}' : null;
      _loading = false;
      if (profileResult.$1 == null && statsResult.$1 == null &&
          jobsResult.$1 == null) {
        _fatalError = '${jobsResult.$2}';
      }
    });
  }

  Future<void> _toggleAvailability(bool available) async {
    final profile = _profile;
    if (profile == null || _updatingAvailability) return;
    setState(() => _updatingAvailability = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.fieldMember.setAvailability(available);
      if (!mounted) return;
      setState(() {
        _profile = FieldMemberProfile(
          fieldMemberId: profile.fieldMemberId,
          employeeCode: profile.employeeCode,
          fullName: profile.fullName,
          region: profile.region,
          phoneNumber: profile.phoneNumber,
          username: profile.username,
          approvalStatus: profile.approvalStatus,
          isAvailable: available,
          stats: profile.stats,
        );
        _updatingAvailability = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            available ? 'You are available for work.' : 'You are unavailable.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingAvailability = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update availability: $error')),
      );
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
    final name = _profile?.displayName ??
        context.session.session?.displayName ??
        'there';
    return Scaffold(
      body: _loading
          ? const _TodayLoading()
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
                        if (_fatalError != null)
                          ErrorStateView(
                            title: 'Today could not load',
                            message: _fatalError!,
                            onRetry: _load,
                          )
                        else ...[
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Open visits',
                                  value: '${_stats.openTotal}',
                                  icon: Icons.assignment_outlined,
                                  color: AppColors.primary,
                                  background: AppColors.primarySoft,
                                  caption: '${_stats.assigned} to start',
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: StatTile(
                                  label: 'In progress',
                                  value: '${_stats.inProgress}',
                                  icon: Icons.sync_alt_rounded,
                                  color: AppColors.info,
                                  background: AppColors.infoSoft,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: StatTile(
                                  label: 'Done today',
                                  value: '${_stats.completedToday}',
                                  icon: Icons.task_alt_rounded,
                                  color: AppColors.success,
                                  background: AppColors.successSoft,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          SectionHeader(
                            title: "Today's visits",
                            subtitle: _jobs.isEmpty
                                ? null
                                : '${_jobs.length} assignment${_jobs.length == 1 ? '' : 's'} waiting',
                          ),
                          if (_jobsError != null)
                            InfoBanner(
                              tone: InfoTone.error,
                              title: 'Assignments unavailable',
                              message: _jobsError!,
                              action: TextButton(
                                onPressed: _load,
                                child: const Text('Retry'),
                              ),
                            )
                          else if (_jobs.isEmpty)
                            const AppCard(
                              elevated: false,
                              child: EmptyState(
                                icon: Icons.task_alt_rounded,
                                title: 'No visits assigned',
                                message:
                                    'New assignments from the branch will appear here. Keep your availability on.',
                                compact: true,
                              ),
                            )
                          else
                            for (final job in _jobs)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: FieldJobCard(
                                  job: job,
                                  onTap: () => _open(job),
                                ),
                              ),
                          const SizedBox(height: AppSpacing.lg),
                          _availabilityNote(),
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
    final profile = _profile;
    final available = profile?.isAvailable ?? false;
    return ColoredBox(
      color: AppColors.primaryDark,
      child: SafeArea(
        bottom: false,
        child: GradientHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Fmt.greeting(), style: HeaderText.greeting),
              const SizedBox(height: 2),
              Text(name, style: HeaderText.name),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                          available
                              ? Icons.check_circle_rounded
                              : Icons.pause_circle_outline_rounded,
                          size: 16,
                          color: available
                              ? AppColors.onDarkAccent
                              : Colors.white.withValues(alpha: 0.72),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          available ? 'Available' : 'Unavailable',
                          style: HeaderText.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (profile?.region?.isNotEmpty == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        profile!.region!,
                        style: HeaderText.caption.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _availabilityNote() {
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    final available = profile.isAvailable;
    return AppCard(
      child: Row(
        children: [
          IconTile(
            icon: available
                ? Icons.wifi_tethering_rounded
                : Icons.wifi_tethering_off_rounded,
            color: available ? AppColors.secondaryDark : AppColors.textSecondary,
            background:
                available ? AppColors.secondarySoft : AppColors.neutralSoft,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accepting new work',
                  style: AppText.cardTitle,
                ),
                const SizedBox(height: 2),
                Text(
                  available
                      ? 'Turn this off when you are on a break.'
                      : 'Turn this on to receive new assignments.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch.adaptive(
            value: available,
            onChanged: _updatingAvailability ? null : _toggleAvailability,
            activeTrackColor: AppColors.secondary,
          ),
        ],
      ),
    );
  }
}

class _TodayLoading extends StatelessWidget {
  const _TodayLoading();

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
