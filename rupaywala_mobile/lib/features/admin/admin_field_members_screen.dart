import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api.dart';
import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';

/// Admin team management: approvals, availability and access removal.
class AdminFieldMembersScreen extends StatefulWidget {
  const AdminFieldMembersScreen({super.key});

  @override
  State<AdminFieldMembersScreen> createState() =>
      _AdminFieldMembersScreenState();
}

class _AdminFieldMembersScreenState extends State<AdminFieldMembersScreen> {
  static const _filters = ['All', 'Available', 'Pending', 'Inactive'];

  List<ManagedFieldMember> members = [];
  final Set<int> _removingIds = {};
  final Set<int> _updatingIds = {};
  String _filter = 'All';
  bool isLoading = true;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    loadMembers();
  }

  Future<void> loadMembers() async {
    final api = context.api;
    setState(() {
      isLoading = true;
      _error = null;
    });
    try {
      final result = await api.admin.fieldMembers();
      if (!mounted) return;
      setState(() {
        members = result;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _error = '$error';
      });
    }
  }

  List<ManagedFieldMember> get _visible {
    switch (_filter) {
      case 'Available':
        return members
            .where((member) => member.isActive && member.isAvailable)
            .toList(growable: false);
      case 'Pending':
        return members
            .where((member) => member.isPending && member.isActive)
            .toList(growable: false);
      case 'Inactive':
        return members
            .where((member) => !member.isActive || !member.isApproved)
            .toList(growable: false);
      default:
        return members;
    }
  }

  Future<void> _addMember() async {
    final api = context.api;
    final messenger = ScaffoldMessenger.of(context);
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddFieldMemberDialog(api: api),
    );

    if (created == true && mounted) {
      await loadMembers();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Field member created and approved')),
        );
      }
    }
  }

  Future<void> _removeMember(ManagedFieldMember member) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove field member access?',
      message:
          'This will prevent ${member.displayName} from signing in. Past assignments and service history will be kept.',
      confirmLabel: 'Remove access',
      destructive: true,
      icon: Icons.person_remove_outlined,
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removingIds.add(member.id));
    try {
      await context.api.admin.deactivateFieldMember(member.id);
      if (!mounted) return;
      setState(() {
        members = members
            .map(
              (item) => item.id == member.id
                  ? ManagedFieldMember(
                      id: item.id,
                      userId: item.userId,
                      employeeCode: item.employeeCode,
                      fullName: item.fullName,
                      region: item.region,
                      phoneNumber: item.phoneNumber,
                      username: item.username,
                      approvalStatus: 'suspended',
                      isAvailable: false,
                      isActive: false,
                      activeJobs: item.activeJobs,
                      completedJobs: item.completedJobs,
                      rejectionReason: item.rejectionReason,
                      approvedAt: item.approvedAt,
                      createdAt: item.createdAt,
                    )
                  : item,
            )
            .toList();
        _removingIds.remove(member.id);
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Field member access removed')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _removingIds.remove(member.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove field member: $error')),
      );
    }
  }

  Future<void> _setAvailability(
    ManagedFieldMember member,
    bool available,
  ) async {
    if (_updatingIds.contains(member.id)) return;
    setState(() => _updatingIds.add(member.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.admin
          .setFieldMemberAvailability(member.id, available);
      if (!mounted) return;
      setState(() {
        members = [
          for (final item in members)
            if (item.id == member.id)
              ManagedFieldMember(
                id: item.id,
                userId: item.userId,
                employeeCode: item.employeeCode,
                fullName: item.fullName,
                region: item.region,
                phoneNumber: item.phoneNumber,
                username: item.username,
                approvalStatus: item.approvalStatus,
                isAvailable: available,
                isActive: item.isActive,
                activeJobs: item.activeJobs,
                completedJobs: item.completedJobs,
                rejectionReason: item.rejectionReason,
                approvedAt: item.approvedAt,
                createdAt: item.createdAt,
              )
            else
              item,
        ];
        _updatingIds.remove(member.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingIds.remove(member.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update availability: $error')),
      );
    }
  }

  Future<void> _review(ManagedFieldMember member, String action) async {
    if (_updatingIds.contains(member.id)) return;
    String? reason;
    if (action == 'reject') {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Reject ${member.displayName}?'),
          content: TextField(
            controller: controller,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason for rejection',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reject member'),
            ),
          ],
        ),
      );
      reason = controller.text.trim();
      controller.dispose();
      if (confirmed != true || !mounted) return;
    }

    setState(() => _updatingIds.add(member.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.admin.reviewFieldMember(
        fieldMemberId: member.id,
        action: action,
        reason: reason,
      );
      if (!mounted) return;
      await loadMembers();
      if (!mounted) return;
      setState(() => _updatingIds.remove(member.id));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            action == 'approve' ? 'Member approved.' : 'Member rejected.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingIds.remove(member.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Could not review member: $error')),
      );
    }
  }

  int get _availableCount =>
      members.where((member) => member.isActive && member.isAvailable).length;
  int get _pendingCount =>
      members.where((member) => member.isPending && member.isActive).length;

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Field Members',
        showBack: false,
        actions: [
          AppBarIconButton(
            icon: Icons.person_add_alt_1,
            tooltip: 'Add field member',
            onPressed: _addMember,
          ),
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh team',
            onPressed: isLoading ? () {} : loadMembers,
          ),
        ],
      ),
      body: isLoading
          ? const SkeletonList(itemCount: 4)
          : _error != null
              ? ErrorStateView(
                  title: 'Team could not load',
                  message: _error!,
                  onRetry: loadMembers,
                )
              : members.isEmpty
                  ? Center(
                      child: EmptyState(
                        icon: Icons.people_outline,
                        title: 'No Field Members',
                        subtitle: 'Add field members to your team',
                        actionLabel: 'Add field member',
                        onAction: _addMember,
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            0,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _TeamMetric(
                                  label: 'Team size',
                                  value: '${members.length}',
                                  icon: Icons.groups_outlined,
                                  color: AppColors.primary,
                                  background: AppColors.primarySoft,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _TeamMetric(
                                  label: 'Available',
                                  value: '$_availableCount',
                                  icon: Icons.check_circle_outline,
                                  color: AppColors.success,
                                  background: AppColors.successSoft,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _TeamMetric(
                                  label: 'Pending',
                                  value: '$_pendingCount',
                                  icon: Icons.hourglass_empty_rounded,
                                  color: AppColors.warning,
                                  background: AppColors.warningSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: FilterChipRow(
                            options: _filters,
                            selected: _filter,
                            onSelected: (value) =>
                                setState(() => _filter = value),
                          ),
                        ),
                        Expanded(
                          child: visible.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    const SizedBox(height: 40),
                                    EmptyState(
                                      icon: Icons.groups_outlined,
                                      title: 'Nothing in $_filter',
                                      message:
                                          'Try another filter or add a new field member.',
                                      actionLabel: 'Add field member',
                                      onAction: _addMember,
                                    ),
                                  ],
                                )
                              : RefreshIndicator(
                                  onRefresh: loadMembers,
                                  color: AppColors.primary,
                                  child: ListView.separated(
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
                                      final member = visible[index];
                                      return _MemberCard(
                                        member: member,
                                        removing:
                                            _removingIds.contains(member.id),
                                        busy:
                                            _updatingIds.contains(member.id),
                                        onAvailability: (value) =>
                                            _setAvailability(member, value),
                                        onApprove: () =>
                                            _review(member, 'approve'),
                                        onReject: () =>
                                            _review(member, 'reject'),
                                        onRemove: () => _removeMember(member),
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

class _TeamMetric extends StatelessWidget {
  const _TeamMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          IconTile(
            icon: icon,
            color: color,
            background: background,
            size: 32,
            iconSize: 16,
            radius: AppRadius.sm,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppText.metric.copyWith(fontSize: 18),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.removing,
    required this.busy,
    required this.onAvailability,
    required this.onApprove,
    required this.onReject,
    required this.onRemove,
  });

  final ManagedFieldMember member;
  final bool removing;
  final bool busy;
  final ValueChanged<bool> onAvailability;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final approval = StatusStyle.forApproval(member.approvalStatus);
    final active = member.isActive;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(
                initials: Fmt.initials(member.displayName),
                size: 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${member.username ?? "unknown"} · ${member.phoneNumber ?? "N/A"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(fontSize: 12),
                    ),
                    if (member.region?.isNotEmpty == true)
                      Text(
                        member.region!,
                        style: AppText.caption.copyWith(fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!active)
                const StatusBadge(
                  label: 'Access removed',
                  color: AppColors.error,
                  background: AppColors.errorSoft,
                  icon: Icons.block_outlined,
                  dense: true,
                )
              else
                StatusBadge(
                  label: approval.label,
                  color: approval.color,
                  background: approval.background,
                  icon: approval.icon,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              MetaPill(
                label: '${member.activeJobs} active',
                icon: Icons.assignment_outlined,
                color: AppColors.info,
                background: AppColors.infoSoft,
              ),
              MetaPill(
                label: '${member.completedJobs} completed',
                icon: Icons.task_alt_rounded,
                color: AppColors.success,
                background: AppColors.successSoft,
              ),
              if (member.employeeCode?.isNotEmpty == true)
                MetaPill(label: member.employeeCode!),
            ],
          ),
          if (active) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    member.isAvailable ? 'Available for work' : 'Not available',
                    style: AppText.caption.copyWith(fontSize: 12.5),
                  ),
                ),
                Switch.adaptive(
                  value: member.isAvailable,
                  onChanged: busy ? null : onAvailability,
                  activeTrackColor: AppColors.secondary,
                ),
                IconButton(
                  tooltip: 'Remove field member access',
                  onPressed: removing ? null : onRemove,
                  icon: removing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.person_remove_outlined,
                          color: AppColors.error,
                        ),
                ),
              ],
            ),
            if (member.isPending) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Reject',
                      icon: Icons.close_rounded,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.small,
                      onPressed: busy ? null : onReject,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      variant: AppButtonVariant.success,
                      size: AppButtonSize.small,
                      isLoading: busy,
                      onPressed: busy ? null : onApprove,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AddFieldMemberDialog extends StatefulWidget {
  const _AddFieldMemberDialog({required this.api});

  final Api api;

  @override
  State<_AddFieldMemberDialog> createState() => _AddFieldMemberDialogState();
}

class _AddFieldMemberDialogState extends State<_AddFieldMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _employeeCode = TextEditingController();
  final _region = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _fullName.dispose();
    _phone.dispose();
    _employeeCode.dispose();
    _region.dispose();
    super.dispose();
  }

  Future<void> _createMember() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.api.admin.createFieldMember(
        username: _username.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim(),
        phoneNumber: _phone.text.trim(),
        employeeCode: _employeeCode.text.trim(),
        region: _region.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add field member'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppInputField(
                  controller: _fullName,
                  label: 'Full name',
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Enter the member’s full name'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppInputField(
                  controller: _username,
                  label: 'Username',
                  validator: (value) => value == null || value.trim().length < 3
                      ? 'Username must be at least 3 characters'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppInputField(
                  controller: _password,
                  label: 'Initial password',
                  obscureText: true,
                  helper: 'At least 8 characters with letters and numbers',
                  validator: (value) => value == null || value.length < 8
                      ? 'Password must be at least 8 characters'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppInputField(
                  controller: _phone,
                  label: 'Mobile number',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (value) => value == null || value.length != 10
                      ? 'Enter a 10-digit mobile number'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppInputField(
                  controller: _employeeCode,
                  label: 'Employee code (optional)',
                ),
                const SizedBox(height: AppSpacing.sm),
                AppInputField(
                  controller: _region,
                  label: 'Region (optional)',
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  InfoBanner(
                    tone: InfoTone.error,
                    icon: Icons.error_outline_rounded,
                    message: _error!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        AppButton(
          label: 'Create member',
          size: AppButtonSize.medium,
          expand: false,
          isLoading: _saving,
          onPressed: _saving ? null : _createMember,
        ),
      ],
    );
  }
}
