import 'package:flutter/material.dart';

import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// Lets an admin pick an approved, available field member.
///
/// The backend refuses assignments to members who are not operational, so the
/// sheet only lists `approved` members and disables the unavailable ones rather
/// than letting the request fail after the fact.
Future<ManagedFieldMember?> showAssignMemberSheet(
  BuildContext context, {
  int? currentMemberId,
}) {
  return showModalBottomSheet<ManagedFieldMember>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _AssignMemberSheet(currentMemberId: currentMemberId),
  );
}

class _AssignMemberSheet extends StatefulWidget {
  const _AssignMemberSheet({this.currentMemberId});

  final int? currentMemberId;

  @override
  State<_AssignMemberSheet> createState() => _AssignMemberSheetState();
}

class _AssignMemberSheetState extends State<_AssignMemberSheet> {
  List<ManagedFieldMember> _members = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await context.api.admin.fieldMembers(
        approvalStatus: 'approved',
      );
      if (!mounted) return;
      setState(() {
        _members = members
            .where((member) => member.isActive)
            .toList(growable: false);
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

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.74;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assign a field member', style: AppText.sectionTitle),
                        SizedBox(height: 2),
                        Text(
                          'Only approved members can receive a job.',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xxl),
                      child: AppLoading(label: 'Loading field members...'),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: ErrorStateView(
                            title: 'Team could not load',
                            message: _error!,
                            onRetry: _load,
                          ),
                        )
                      : _members.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.xl),
                              child: EmptyState(
                                icon: Icons.groups_outlined,
                                title: 'No approved members',
                                message:
                                    'Approve a field member in Team before assigning this request.',
                                compact: true,
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.md,
                                AppSpacing.lg,
                                AppSpacing.xxl,
                              ),
                              itemCount: _members.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (context, index) {
                                final member = _members[index];
                                final isCurrent =
                                    member.id == widget.currentMemberId;
                                final selectable =
                                    member.isAvailable && !isCurrent;
                                return _MemberOption(
                                  member: member,
                                  isCurrent: isCurrent,
                                  onTap: selectable
                                      ? () => Navigator.of(context).pop(member)
                                      : null,
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberOption extends StatelessWidget {
  const _MemberOption({
    required this.member,
    required this.isCurrent,
    required this.onTap,
  });

  final ManagedFieldMember member;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final available = member.isAvailable;
    final subtitle = [
      member.employeeCode,
      member.region,
      member.phoneNumber,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');

    return Opacity(
      opacity: onTap == null && !isCurrent ? 0.6 : 1,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isCurrent ? AppColors.primary : AppColors.border,
                width: isCurrent ? 1.6 : 1,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                AppAvatar(
                  initials: _initials(member.displayName),
                  size: 40,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName,
                        style: AppText.title.copyWith(fontSize: 14),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(fontSize: 12),
                        ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        children: [
                          StatusBadge(
                            label: available ? 'Available' : 'Unavailable',
                            color: available
                                ? AppColors.success
                                : AppColors.textSecondary,
                            background: available
                                ? AppColors.successSoft
                                : AppColors.neutralSoft,
                            icon: available
                                ? Icons.check_circle_outline
                                : Icons.pause_circle_outline,
                            dense: true,
                          ),
                          MetaPill(
                            label:
                                '${member.activeJobs} active · ${member.completedJobs} done',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (isCurrent)
                  const StatusBadge(
                    label: 'Assigned',
                    color: AppColors.primary,
                    background: AppColors.primarySoft,
                    dense: true,
                  )
                else
                  Icon(
                    onTap == null
                        ? Icons.block_outlined
                        : Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'FM';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
