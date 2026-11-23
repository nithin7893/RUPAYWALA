import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import 'add_policy_screen.dart';

/// The customer's policy wallet.
///
/// Rendered both as a shell tab and as a pushed route, so the back arrow is
/// conditional. Failures are shown in place with a retry instead of a
/// transient snackbar that leaves the screen blank.
class PolicyListScreen extends StatefulWidget {
  const PolicyListScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PolicyListScreen> createState() => _PolicyListScreenState();
}

class _PolicyListScreenState extends State<PolicyListScreen> {
  List<Policy> _policies = const [];
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
    try {
      final result = await context.api.customer.policies();
      if (!mounted) return;
      setState(() {
        _policies = result;
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

  Future<void> _addPolicy() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddPolicyScreen()),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'My Policies',
        showBack: !widget.embedded,
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh policies',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 3)
          : _error != null
              ? ErrorStateView(
                  message: _error!,
                  title: 'Policies could not load',
                  onRetry: _load,
                )
              : _policies.isEmpty
                  ? EmptyState(
                      icon: Icons.shield_outlined,
                      title: 'No policies yet',
                      subtitle:
                          'Add your insurance details so service requests can be linked to the right policy.',
                      actionLabel: 'Add policy',
                      onAction: _addPolicy,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.xxxl,
                        ),
                        children: [
                          _summary(),
                          const SizedBox(height: AppSpacing.lg),
                          for (final policy in _policies) ...[
                            _PolicyCard(policy: policy),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            label: 'Add another policy',
                            icon: Icons.add_rounded,
                            variant: AppButtonVariant.secondary,
                            onPressed: _addPolicy,
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _summary() {
    final active = _policies.where((p) => p.isActive && p.isValid).length;
    final expiring = _policies
        .where((p) =>
            p.daysToExpiry != null &&
            p.daysToExpiry! >= 0 &&
            p.daysToExpiry! <= 30)
        .length;

    return AppCard(
      color: AppColors.primarySoft,
      borderColor: AppColors.primarySoft,
      child: Row(
        children: [
          Expanded(child: _Stat(value: '${_policies.length}', label: 'Policies')),
          Container(width: 1, height: 34, color: AppColors.border),
          Expanded(child: _Stat(value: '$active', label: 'Active')),
          Container(width: 1, height: 34, color: AppColors.border),
          Expanded(child: _Stat(value: '$expiring', label: 'Expiring')),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppText.metric.copyWith(fontSize: 22)),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.policy});

  final Policy policy;

  @override
  Widget build(BuildContext context) {
    final floater = policy.policyCategory == 'floater';
    final days = policy.daysToExpiry;
    final expiringSoon = days != null && days >= 0 && days <= 30;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  floater ? Icons.groups_outlined : Icons.person_outline,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(policy.title, style: AppText.cardTitle),
                    const SizedBox(height: 2),
                    Text(policy.providerName, style: AppText.caption),
                  ],
                ),
              ),
              StatusBadge(
                label: policy.isValid ? (floater ? 'Floater' : 'Individual') : 'Expired',
                color: policy.isValid ? AppColors.success : AppColors.error,
                background:
                    policy.isValid ? AppColors.successSoft : AppColors.errorSoft,
                icon: policy.isValid
                    ? Icons.verified_outlined
                    : Icons.error_outline,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(),
          InfoRow(
            label: 'Policy number',
            value: policy.policyNumber,
            icon: Icons.numbers_rounded,
          ),
          if (policy.coverageAmount != null)
            InfoRow(
              label: 'Coverage',
              value: Fmt.money(policy.coverageAmount),
              icon: Icons.currency_rupee_rounded,
            ),
          if (policy.expiryDate != null)
            InfoRow(
              label: 'Expires',
              value: Fmt.date(policy.expiryDate),
              valueColor: expiringSoon ? AppColors.warning : null,
              icon: Icons.event_outlined,
            ),
          if (policy.numberOfMembers != null)
            InfoRow(
              label: 'Members',
              value: '${policy.numberOfMembers}',
              icon: Icons.groups_2_outlined,
            ),
          if (floater && policy.members.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Covered members',
              style: AppText.overline.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final member in policy.members)
                  _MemberChip(
                    name: '${member['member_name'] ?? 'Member'}',
                    relationship: '${member['relationship'] ?? ''}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.name, required this.relationship});

  final String name;
  final String relationship;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        relationship.isEmpty ? name : '$name · $relationship',
        style: AppText.caption.copyWith(fontSize: 12),
      ),
    );
  }
}
