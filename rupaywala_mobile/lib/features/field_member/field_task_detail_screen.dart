import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';

/// A single assigned job for a field member.
///
/// Start is only offered while the request is `assigned`, complete only while
/// it is `in_progress`, mirroring the backend transitions. Completion notes are
/// mandatory because completing is the step that consumes a customer visit.
class FieldTaskDetailScreen extends StatefulWidget {
  const FieldTaskDetailScreen({
    super.key,
    required this.requestId,
    this.initialJob,
  });

  final int requestId;
  final FieldMemberJob? initialJob;

  @override
  State<FieldTaskDetailScreen> createState() => _FieldTaskDetailScreenState();
}

class _FieldTaskDetailScreenState extends State<FieldTaskDetailScreen> {
  FieldMemberJob? _job;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(initial: widget.initialJob != null);
  }

  Future<void> _load({bool initial = false}) async {
    if (!initial) setState(() => _loading = true);
    try {
      final job = await context.api.fieldMember.job(widget.requestId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _start() async {
    final job = _job;
    if (job == null || !job.canStart || _busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Start this visit?',
      message:
          'The customer will see that you are on the way. Start only when you have the assignment details.',
      confirmLabel: 'Start visit',
      icon: Icons.play_arrow_rounded,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => context.api.fieldMember.start(job.requestId),
      success: 'Visit started.',
    );
  }

  Future<void> _complete() async {
    final job = _job;
    if (job == null || !job.canComplete || _busy) return;

    final notes = TextEditingController(
      text: job.completionNotes ?? '',
    );
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete this visit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Describe what was completed. The customer sees these notes and a visit is consumed.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: notes,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Completion notes',
                  hintText: 'What was done at the visit?',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () {
              if (notes.text.trim().length < 5) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Complete visit'),
          ),
        ],
      ),
    );
    final text = notes.text.trim();
    notes.dispose();
    if (submitted != true || !mounted) return;
    if (text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least five characters of notes.')),
      );
      return;
    }

    await _run(
      () => context.api.fieldMember.complete(
        requestId: job.requestId,
        completionNotes: text,
      ),
      success: 'Visit completed.',
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

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the dialer. $phone copied.')),
        );
      }
    }
  }

  Future<void> _openMaps() async {
    final job = _job;
    if (job == null) return;
    final hasPoint =
        job.customerLatitude != null && job.customerLongitude != null;
    final uri = hasPoint
        ? Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query':
                '${job.customerLatitude},${job.customerLongitude}',
          })
        : Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query': job.customerAddress ?? job.reference,
          });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No maps application is available.')),
      );
    }
  }

  Future<void> _copyAddress() async {
    final address = _job?.customerAddress;
    if (address == null || address.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: address));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visit address copied.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Task details',
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh task',
            onPressed: _loading ? () {} : () => _load(),
          ),
        ],
      ),
      body: _loading && job == null
          ? const SkeletonList(itemCount: 3)
          : job == null
              ? ErrorStateView(
                  title: 'Task unavailable',
                  message: _error ?? 'This task could not be loaded.',
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
                      _headline(job),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoBanner(
                          tone: InfoTone.warning,
                          message: 'Showing saved details: $_error',
                          action: TextButton(
                            onPressed: () => _load(),
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _customerCard(job),
                      const SizedBox(height: AppSpacing.md),
                      _visitCard(job),
                      if (job.description?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Request notes', style: AppText.cardTitle),
                              const SizedBox(height: AppSpacing.sm),
                              Text(job.description!, style: AppText.bodyMuted),
                            ],
                          ),
                        ),
                      ],
                      if (job.completionNotes?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoBanner(
                          tone: InfoTone.success,
                          icon: Icons.task_alt_rounded,
                          title: 'Completion notes',
                          message: job.completionNotes!,
                        ),
                      ],
                      if (job.proofImageUrl?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Proof document', style: AppText.cardTitle),
                              const SizedBox(height: AppSpacing.sm),
                              SecureDocumentImage(documentPath: job.proofImageUrl),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Progress'),
                      AppCard(child: _timeline(job)),
                      const SizedBox(height: AppSpacing.xl),
                      if (job.canStart)
                        AppButton(
                          label: _busy ? 'Starting...' : 'Start visit',
                          icon: Icons.play_arrow_rounded,
                          isLoading: _busy,
                          onPressed: _busy ? null : _start,
                        )
                      else if (job.canComplete)
                        AppButton(
                          label: _busy ? 'Completing...' : 'Complete visit',
                          icon: Icons.check_rounded,
                          variant: AppButtonVariant.success,
                          isLoading: _busy,
                          onPressed: _busy ? null : _complete,
                        )
                      else if (job.isDone)
                        const InfoBanner(
                          tone: InfoTone.success,
                          icon: Icons.check_circle_outline,
                          message: 'This visit is completed. No further action is needed.',
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _headline(FieldMemberJob job) {
    final style = StatusStyle.forStage(job.stage);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.requestType, style: AppText.sectionTitle),
              const SizedBox(height: 2),
              Text(
                '${job.reference} · ${Fmt.dateTime(job.createdAt)}',
                style: AppText.caption,
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
        ),
      ],
    );
  }

  Widget _customerCard(FieldMemberJob job) {
    final phone = job.customerPhone;
    final address = job.customerAddress;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(initials: Fmt.initials(job.customerDisplayName), size: 46),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.customerDisplayName, style: AppText.cardTitle),
                    if (phone != null && phone.isNotEmpty)
                      Text(phone, style: AppText.caption),
                  ],
                ),
              ),
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  tooltip: 'Call customer',
                  onPressed: () => _call(phone),
                  icon: const Icon(Icons.call_outlined),
                  color: AppColors.primary,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primarySoft,
                  ),
                ),
            ],
          ),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(address, style: AppText.bodyMuted)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Open in maps',
                    icon: Icons.map_outlined,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    onPressed: _openMaps,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Copy address',
                    icon: Icons.copy_rounded,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    onPressed: _copyAddress,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _visitCard(FieldMemberJob job) {
    return AppCard(
      child: Column(
        children: [
          InfoRow(
            label: 'Branch',
            value: job.branchName ?? 'Not recorded',
            icon: Icons.storefront_outlined,
          ),
          if (job.branchAddress?.isNotEmpty == true)
            InfoRow(
              label: 'Branch address',
              value: job.branchAddress!,
              icon: Icons.place_outlined,
            ),
          InfoRow(
            label: 'Distance',
            value: Fmt.km(job.distanceKm),
            icon: Icons.route_outlined,
          ),
          if (job.policyLabel?.isNotEmpty == true)
            InfoRow(
              label: 'Policy',
              value: job.policyLabel!,
              icon: Icons.shield_outlined,
            ),
          InfoRow(
            label: 'Assigned',
            value: Fmt.dateTime(job.assignedAt),
            icon: Icons.assignment_outlined,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _timeline(FieldMemberJob job) {
    final steps = <(String, DateTime?, IconData)>[
      ('Assigned', job.assignedAt, Icons.assignment_outlined),
      ('Visit started', job.startedAt, Icons.play_circle_outline),
      ('Completed', job.completedAt, Icons.check_circle_outline),
    ];
    return Column(
      children: [
        for (var index = 0; index < steps.length; index++)
          Builder(
            builder: (context) {
              final step = steps[index];
              final done = step.$2 != null;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == steps.length - 1 ? 0 : AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? AppColors.secondarySoft
                            : AppColors.neutralSoft,
                      ),
                      child: Icon(
                        step.$3,
                        size: 16,
                        color: done
                            ? AppColors.secondaryDark
                            : AppColors.textHint,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        step.$1,
                        style: AppText.title.copyWith(
                          color: done
                              ? AppColors.textPrimary
                              : AppColors.textHint,
                        ),
                      ),
                    ),
                    Text(
                      done ? Fmt.dateTime(step.$2) : 'Pending',
                      style: AppText.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
