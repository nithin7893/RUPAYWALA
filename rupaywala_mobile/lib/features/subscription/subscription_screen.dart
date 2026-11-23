import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../payment/payment_history_screen.dart';
import '../payment/payment_screen.dart';

/// Membership management: the current plan, visit balance, family members,
/// visit ledger, prior memberships and the plans on offer.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<SubscriptionPlan> _plans = const [];
  List<SubscriptionFamilyMember> _familyMembers = const [];
  List<CustomerSubscription> _history = const [];
  List<VisitLedgerEntry> _visits = const [];
  CustomerSubscription? _subscription;
  VisitBalance? _balance;
  bool _loading = true;
  bool _addingMember = false;
  String? _error;
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
      _error = null;
    });
    final api = context.api;
    final plans = _attempt(api.subscriptions.plans);
    final current = _attempt(api.subscriptions.currentSubscription);
    final balance = _attempt(api.subscriptions.visitBalance);
    final history = _attempt(api.subscriptions.allSubscriptions);
    final visits = _attempt(api.subscriptions.visitHistory);

    await Future.wait([plans, current, balance, history, visits]);

    if (!mounted) return;

    final currentSubscription = (await current).$1;
    final maxMembers =
        currentSubscription?.entitlements['max_family_members'];
    final familyResult = currentSubscription?.isActive == true &&
            maxMembers is num &&
            maxMembers > 1
        ? await _attempt(api.subscriptions.familyMembers)
        : (const <SubscriptionFamilyMember>[], null);

    if (!mounted) return;

    final plansResult = await plans;
    final balanceResult = await balance;
    final historyResult = await history;
    final visitsResult = await visits;
    setState(() {
      _plans = plansResult.$1 ?? const [];
      _subscription = currentSubscription;
      _balance = balanceResult.$1;
      _history = historyResult.$1 ?? const [];
      _visits = visitsResult.$1 ?? const [];
      _familyMembers = familyResult.$1 ?? const <SubscriptionFamilyMember>[];
      _loading = false;
      if (plansResult.$1 == null && currentSubscription == null) {
        _error = _message(plansResult.$2);
      }
    });
  }

  String _message(Object? error) => error == null
      ? 'Membership information is unavailable right now.'
      : '$error';

  List<CustomerSubscription> get _pastSubscriptions {
    final currentId = _subscription?.id;
    return _history
        .where((item) => item.id != currentId)
        .toList(growable: false);
  }

  Future<void> _subscribe(SubscriptionPlan plan) async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaymentScreen(
          planId: plan.id,
          planName: plan.name,
          amount: plan.price,
        ),
      ),
    );
    if (!mounted || paid != true) return;
    await context.session.refresh();
    if (mounted) await _load();
  }

  Future<void> _addFamilyMember() async {
    if (_addingMember) return;
    final name = TextEditingController();
    final relationship = TextEditingController();
    var memberType = 'child';
    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add family member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: relationship,
                  decoration: const InputDecoration(labelText: 'Relationship'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: memberType,
                  decoration: const InputDecoration(labelText: 'Member type'),
                  items: const [
                    DropdownMenuItem(value: 'adult', child: Text('Adult')),
                    DropdownMenuItem(value: 'child', child: Text('Child')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => memberType = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                name.text.trim().length >= 2 &&
                    relationship.text.trim().length >= 2,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    final memberName = name.text.trim();
    final memberRelationship = relationship.text.trim();
    name.dispose();
    relationship.dispose();
    if (shouldCreate != true || !mounted) return;

    setState(() => _addingMember = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final member = await context.api.subscriptions.addFamilyMember(
        memberName: memberName,
        relationship: memberRelationship,
        memberType: memberType,
      );
      if (!mounted) return;
      setState(() {
        _familyMembers = [..._familyMembers, member];
        _addingMember = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _addingMember = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add family member: $error')),
      );
    }
  }

  Future<void> _removeFamilyMember(SubscriptionFamilyMember member) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove ${member.memberName}?',
      message: 'They will no longer be covered by this membership.',
      confirmLabel: 'Remove',
      destructive: true,
      icon: Icons.person_remove_outlined,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.subscriptions.removeFamilyMember(member.id);
      if (!mounted) return;
      setState(() {
        _familyMembers = _familyMembers
            .where((item) => item.id != member.id)
            .toList(growable: false);
      });
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove family member: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _subscription;
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Membership',
        actions: [
          AppBarIconButton(
            icon: Icons.receipt_long_outlined,
            tooltip: 'Payment history',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PaymentHistoryScreen(),
              ),
            ),
          ),
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh membership',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 4)
          : _error != null
              ? ErrorStateView(
                  title: 'Membership could not load',
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
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
                      if (current != null && current.isActive)
                        _currentPlanCard(current)
                      else
                        _noPlanCard(),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                        title: current != null && current.isActive
                            ? 'Other plans'
                            : 'Available plans',
                        subtitle:
                            'All prices include the visit allowance shown.',
                      ),
                      if (_plans.isEmpty)
                        const AppCard(
                          elevated: false,
                          child: EmptyState(
                            title: 'No plans available',
                            message:
                                'Plans are added by the Rupaywala team. Check back shortly.',
                            icon: Icons.playlist_add_check_circle_outlined,
                            compact: true,
                          ),
                        )
                      else
                        for (final plan in _plans)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _PlanCard(
                              plan: plan,
                              isCurrent: current != null &&
                                  current.isActive &&
                                  current.planId == plan.id,
                              onSubscribe: () => _subscribe(plan),
                            ),
                          ),
                      if (_pastSubscriptions.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        const SectionHeader(title: 'Membership history'),
                        for (final item in _pastSubscriptions)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _HistoryTile(subscription: item),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _noPlanCard() {
    return const InfoBanner(
      tone: InfoTone.info,
      icon: Icons.card_membership_outlined,
      title: 'No active membership',
      message:
          'A membership covers your doorstep visits. You can still request a service and pay any distance charge.',
    );
  }

  Widget _currentPlanCard(CustomerSubscription current) {
    final balance = _balance;
    final total = balance?.totalVisits ?? current.totalVisits;
    final remaining = balance?.remainingVisits ?? current.remainingVisits;
    final familyLimit = current.entitlements['max_family_members'];
    final allowsFamily = familyLimit is num && familyLimit > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          color: AppColors.primary,
          borderColor: AppColors.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: AppColors.onDarkAccent,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'CURRENT MEMBERSHIP',
                      style: AppText.overline.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  StatusBadge(
                    label: 'Active',
                    color: AppColors.primaryDark,
                    background: AppColors.onDarkAccent,
                    icon: Icons.check_circle_outline,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                current.planName ?? 'Active membership',
                style: AppText.sectionTitle.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                balance?.canRequestService == false
                    ? (balance?.reason ?? 'This membership cannot cover a visit')
                    : 'Valid till ${Fmt.date(current.endDate)}',
                style: AppText.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$remaining',
                    style: HeaderText.metric.copyWith(fontSize: 34),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      'of $total visits left',
                      style: AppText.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: total <= 0
                      ? 0
                      : ((total - remaining) / total).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.onDarkAccent,
                  ),
                ),
              ),
              if (current.daysRemaining != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  current.isExpiringSoon
                      ? 'Expires in ${current.daysRemaining} days'
                      : '${current.daysRemaining} days remaining',
                  style: AppText.caption.copyWith(
                    color: current.isExpiringSoon
                        ? const Color(0xFFFFD8A8)
                        : Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Visit balance', style: AppText.cardTitle),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PaymentHistoryScreen(),
                      ),
                    ),
                    child: const Text('Payments'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              InfoRow(
                label: 'Visits used',
                value: '${balance?.usedVisits ?? current.usedVisits}',
                icon: Icons.check_circle_outline,
              ),
              InfoRow(
                label: 'Started on',
                value: Fmt.date(balance?.startDate ?? current.startDate),
                icon: Icons.event_outlined,
              ),
              InfoRow(
                label: 'Valid until',
                value: Fmt.date(balance?.endDate ?? current.endDate),
                icon: Icons.event_available_outlined,
                isLast: true,
              ),
              if (_visits.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(
                  title: 'Visit activity',
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                ),
                for (var i = 0; i < _visits.length && i < 8; i++)
                  _VisitRow(entry: _visits[i], isLast: i == _visits.length - 1),
              ],
            ],
          ),
        ),
        if (allowsFamily) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Family members',
                        style: AppText.cardTitle,
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          _addingMember || _familyMembers.length + 1 >= familyLimit
                              ? null
                              : _addFamilyMember,
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_familyMembers.length + 1} of $familyLimit people covered',
                  style: AppText.caption,
                ),
                if (_familyMembers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.md),
                    child: Text(
                      'Only you are covered. Add a family member to share this membership.',
                      style: AppText.caption,
                    ),
                  )
                else
                  for (final member in _familyMembers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconTile(
                        icon: Icons.person_outline_rounded,
                        size: 36,
                        iconSize: 18,
                        color: AppColors.primary,
                        background: AppColors.primarySoft,
                      ),
                      title: Text(member.memberName, style: AppText.title),
                      subtitle: Text(
                        '${_titleCase(member.relationship)} · ${_titleCase(member.memberType)}',
                        style: AppText.caption,
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove ${member.memberName}',
                        onPressed: () => _removeFamilyMember(member),
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          color: AppColors.error,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ] else if (current.planName?.toLowerCase().contains('family') == true)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: InfoBanner(
              tone: InfoTone.warning,
              message:
                  'Family coverage is unavailable until an administrator configures the member limit.',
            ),
          ),
      ],
    );
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.entry, required this.isLast});

  final VisitLedgerEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final added = entry.isAllocation;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(
            added ? Icons.add_circle_outline : Icons.remove_circle_outline,
            size: 17,
            color: added ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label, style: AppText.title.copyWith(fontSize: 13.5)),
                if (entry.note?.isNotEmpty == true)
                  Text(entry.note!, style: AppText.caption.copyWith(fontSize: 12)),
              ],
            ),
          ),
          Text(
            '${added ? '+' : ''}${entry.quantity}',
            style: AppText.title.copyWith(
              fontSize: 13.5,
              color: added ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            Fmt.shortDate(entry.createdAt),
            style: AppText.caption.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
    if (isLast) return row;
    return Column(children: [row, const Divider(height: 1)]);
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.subscription});

  final CustomerSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.forSubscription(subscription.status);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          IconTile(
            icon: Icons.history_rounded,
            color: style.color,
            background: style.background,
            size: 38,
            iconSize: 19,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscription.planName ?? 'Membership',
                  style: AppText.title.copyWith(fontSize: 14),
                ),
                Text(
                  '${Fmt.date(subscription.startDate)} – ${Fmt.date(subscription.endDate)}',
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          StatusBadge(
            label: style.label,
            color: style.color,
            background: style.background,
            icon: style.icon,
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.onSubscribe,
  });

  final SubscriptionPlan plan;
  final bool isCurrent;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
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
                    Text(plan.name, style: AppText.cardTitle),
                    if (plan.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(plan.description!, style: AppText.caption),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.money(plan.price),
                    style: AppText.metric.copyWith(
                      fontSize: 22,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'per ${plan.validityLabel}',
                    style: AppText.caption.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (plan.visitsIncluded > 0)
                MetaPill(
                  label: '${plan.visitsIncluded} visits',
                  icon: Icons.home_outlined,
                  color: AppColors.primary,
                  background: AppColors.primarySoft,
                ),
              if (plan.maxFamilyMembers != null && plan.maxFamilyMembers! > 1)
                MetaPill(
                  label: '${plan.maxFamilyMembers} people',
                  icon: Icons.groups_outlined,
                  color: AppColors.secondaryDark,
                  background: AppColors.secondarySoft,
                ),
              if (plan.includedVisitDistanceKm != null)
                MetaPill(
                  label: '${plan.includedVisitDistanceKm!.toStringAsFixed(0)} km included',
                  icon: Icons.route_outlined,
                ),
            ],
          ),
          if (plan.benefits.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final benefit in plan.benefits)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(benefit, style: AppText.caption),
                    ),
                  ],
                ),
              ),
          ],
          if (plan.documentStorage && plan.storageDurationDays != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Documents stored for ${plan.storageDurationDays} days',
                style: AppText.caption,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: isCurrent ? 'Current plan' : 'Get this plan',
            icon: isCurrent
                ? Icons.check_rounded
                : Icons.arrow_forward_rounded,
            variant: isCurrent
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            onPressed: isCurrent ? null : onSubscribe,
          ),
        ],
      ),
    );
  }
}
