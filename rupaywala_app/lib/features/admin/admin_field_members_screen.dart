import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api.dart';
import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class AdminFieldMembersScreen extends StatefulWidget {
  const AdminFieldMembersScreen({super.key});

  @override
  State<AdminFieldMembersScreen> createState() =>
      _AdminFieldMembersScreenState();
}

class _AdminFieldMembersScreenState extends State<AdminFieldMembersScreen> {
  List<ManagedFieldMember> members = [];
  final Set<int> _removingIds = {};
  bool isLoading = true;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    loadMembers();
  }

  Future<void> loadMembers() async {
    final api = context.api;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => isLoading = true);
    try {
      final result = await api.admin.fieldMembers();
      if (!mounted) return;
      setState(() {
        members = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      messenger
          .showSnackBar(SnackBar(content: Text("Failed to load members: $e")));
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove field member access?'),
        content: Text(
          'This will prevent ${member.displayName} from signing in. '
          'Past assignments and service history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove access'),
          ),
        ],
      ),
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingIds.remove(member.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove field member: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Field Members"),
        actions: [
          IconButton(
            tooltip: 'Add field member',
            onPressed: _addMember,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: isLoading
          ? const AppLoading(message: "Loading members...")
          : members.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  title: "No Field Members",
                  subtitle: "Add field members to your team",
                  actionLabel: "Add field member",
                  onAction: _addMember,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDimensions.spacingSm,
                  ),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacingMd,
                        vertical: AppDimensions.spacingXs,
                      ),
                      child: AppCard(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(
                                AppDimensions.spacingSm,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withValues(
                                  alpha: 0.1,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person_outline,
                                color: AppColors.secondary,
                                size: AppDimensions.iconSizeMd,
                              ),
                            ),
                            const SizedBox(width: AppDimensions.spacingMd),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.displayName,
                                    style: AppTypography.cardTitle,
                                  ),
                                  const SizedBox(
                                    height: AppDimensions.spacingXs,
                                  ),
                                  Text(
                                    '@${member.username ?? "unknown"} · ${member.phoneNumber ?? "N/A"}',
                                    style: AppTypography.body,
                                  ),
                                  if (member.region?.isNotEmpty == true)
                                    Text(
                                      member.region!,
                                      style: AppTypography.caption,
                                    ),
                                  Text(
                                    member.isActive
                                        ? member.approvalStatus
                                        : 'Access removed',
                                    style: AppTypography.caption.copyWith(
                                      color: member.isActive
                                          ? AppColors.textSecondary
                                          : AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (member.isActive)
                              IconButton(
                                tooltip: 'Remove field member access',
                                onPressed: _removingIds.contains(member.id)
                                    ? null
                                    : () => _removeMember(member),
                                icon: _removingIds.contains(member.id)
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person_remove_outlined,
                                        color: AppColors.error,
                                      ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
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
                const SizedBox(height: AppDimensions.spacingSm),
                AppInputField(
                  controller: _username,
                  label: 'Username',
                  validator: (value) => value == null || value.trim().length < 3
                      ? 'Username must be at least 3 characters'
                      : null,
                ),
                const SizedBox(height: AppDimensions.spacingSm),
                AppInputField(
                  controller: _password,
                  label: 'Initial password',
                  obscureText: true,
                  helper: 'At least 8 characters with letters and numbers',
                  validator: (value) => value == null || value.length < 8
                      ? 'Password must be at least 8 characters'
                      : null,
                ),
                const SizedBox(height: AppDimensions.spacingSm),
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
                const SizedBox(height: AppDimensions.spacingSm),
                AppInputField(
                  controller: _employeeCode,
                  label: 'Employee code (optional)',
                ),
                const SizedBox(height: AppDimensions.spacingSm),
                AppInputField(
                  controller: _region,
                  label: 'Region (optional)',
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppDimensions.spacingSm),
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
