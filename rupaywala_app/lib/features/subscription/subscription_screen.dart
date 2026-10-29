import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../payment/payment_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<SubscriptionPlan> plans = [];
  List<SubscriptionFamilyMember> familyMembers = [];
  CustomerSubscription? subscription;
  VisitBalance? visitBalance;
  String? loadError;
  bool isLoading = true;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    loadPlans();
  }

  Future<void> loadPlans() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    try {
      final api = context.api;
      final loadedPlans = await api.subscriptions.plans();
      final current = await api.subscriptions.currentSubscription();
      final balance = await api.subscriptions.visitBalance();
      final maxMembers = current?.entitlements['max_family_members'];
      final loadedFamilyMembers =
          current?.isActive == true && maxMembers is num && maxMembers > 1
              ? await api.subscriptions.familyMembers()
              : <SubscriptionFamilyMember>[];
      if (!mounted) return;
      setState(() {
        plans = loadedPlans;
        subscription = current;
        visitBalance = balance;
        familyMembers = loadedFamilyMembers;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadError = 'Failed to load subscription plans: $e';
        isLoading = false;
      });
    }
  }

  void subscribe(SubscriptionPlan plan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentScreen(
          planId: plan.id,
          planName: plan.name,
          amount: plan.price,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Plan'),
        actions: [
          IconButton(
            tooltip: 'Refresh plans',
            onPressed: isLoading ? null : loadPlans,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const AppLoading(message: 'Loading plans...')
          : loadError != null
              ? _errorState()
              : plans.isEmpty
                  ? const EmptyState(
                      icon: Icons.playlist_add_check_circle_outlined,
                      title: 'No Plans Available',
                      subtitle: 'Check back later for subscription plans',
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimensions.spacingMd,
                      ),
                      children: [
                        if (subscription?.isActive == true)
                          _currentPlanCard(
                            subscription!,
                            visitBalance,
                            familyMembers,
                          ),
                        for (final plan in plans)
                          _planCard(
                            plan,
                            isCurrent: subscription?.isActive == true &&
                                subscription!.planId == plan.id,
                          ),
                      ],
                    ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(loadError!, textAlign: TextAlign.center),
            const SizedBox(height: AppDimensions.spacingMd),
            AppButton(
              label: 'Retry',
              onPressed: isLoading ? null : loadPlans,
            ),
          ],
        ),
      ),
    );
  }

  Widget _currentPlanCard(
    CustomerSubscription current,
    VisitBalance? balance,
    List<SubscriptionFamilyMember> members,
  ) {
    final endDate = current.endDate?.toString().split(' ').first;
    final familyLimit = current.entitlements['max_family_members'];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingXs,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your current plan', style: AppTypography.cardTitle),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(current.planName ?? 'Active membership',
                style: AppTypography.body),
            if (balance != null && balance.totalVisits > 0) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                '${balance.remainingVisits} of ${balance.totalVisits} visits remaining',
                style: AppTypography.body,
              ),
              const SizedBox(height: AppDimensions.spacingXs),
              LinearProgressIndicator(
                value: current.usedFraction,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              ),
            ],
            if (endDate != null) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              Text('Renews/expires: $endDate', style: AppTypography.caption),
            ],
            if (familyLimit is num && familyLimit > 1) ...[
              const SizedBox(height: AppDimensions.spacingMd),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Family members (${members.length + 1}/$familyLimit)',
                      style: AppTypography.cardTitle,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: members.length + 1 >= familyLimit
                        ? null
                        : _addFamilyMember,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add'),
                  ),
                ],
              ),
              for (final member in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.memberName),
                  subtitle:
                      Text('${member.relationship} · ${member.memberType}'),
                  trailing: IconButton(
                    tooltip: 'Remove family member',
                    onPressed: () => _removeFamilyMember(member),
                    icon: const Icon(
                      Icons.person_remove_outlined,
                      color: AppColors.error,
                    ),
                  ),
                ),
            ] else if (current.planName?.toLowerCase() == 'premium family') ...[
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                'Family membership is unavailable until an administrator configures the member limit.',
                style: AppTypography.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addFamilyMember() async {
    final api = context.api;
    final name = TextEditingController();
    final relationship = TextEditingController();
    var memberType = 'child';
    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add family member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name'),
                textCapitalization: TextCapitalization.words,
              ),
              TextField(
                controller: relationship,
                decoration: const InputDecoration(labelText: 'Relationship'),
                textCapitalization: TextCapitalization.words,
              ),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
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
    if (shouldCreate != true) return;

    try {
      final member = await api.subscriptions.addFamilyMember(
        memberName: memberName,
        relationship: memberRelationship,
        memberType: memberType,
      );
      if (!mounted) return;
      setState(() => familyMembers = [...familyMembers, member]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add family member: $e')),
      );
    }
  }

  Future<void> _removeFamilyMember(SubscriptionFamilyMember member) async {
    try {
      await context.api.subscriptions.removeFamilyMember(member.id);
      if (!mounted) return;
      setState(() {
        familyMembers.removeWhere((item) => item.id == member.id);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove family member: $e')),
      );
    }
  }

  Widget _planCard(SubscriptionPlan plan, {required bool isCurrent}) {
    final familyCoverage = plan.maxFamilyMembers == null
        ? (plan.code == 'premium_family' ? 'Configured by admin' : null)
        : plan.maxFamilyMembers! > 1
            ? '${plan.maxFamilyMembers} people total'
            : null;
    final daily = plan.price / 365;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingXs,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.name, style: AppTypography.cardTitle),
                ),
                Text(
                  '₹${plan.price.toStringAsFixed(0)}/year',
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              'Approximately ₹${daily.toStringAsFixed(2)} per day',
              style: AppTypography.caption,
            ),
            if (familyCoverage != null) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              _benefitRow(
                  Icons.family_restroom, 'Family coverage', familyCoverage),
            ],
            if (plan.visitsIncluded > 0) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              _benefitRow(
                Icons.home_outlined,
                'Included home visits',
                '${plan.visitsIncluded} shared per membership year',
              ),
            ] else ...[
              const SizedBox(height: AppDimensions.spacingSm),
              _benefitRow(Icons.home_outlined, 'Home visits', 'Not included'),
            ],
            if (plan.additionalVisits != null &&
                plan.additionalVisits! > 0) ...[
              const SizedBox(height: AppDimensions.spacingXs),
              _benefitRow(
                Icons.add_home_outlined,
                'Additional included visits',
                '${plan.additionalVisits} per membership year',
              ),
            ],
            if (plan.includedVisitDistanceKm != null) ...[
              const SizedBox(height: AppDimensions.spacingXs),
              _benefitRow(
                Icons.place_outlined,
                'Included visit distance',
                '${plan.includedVisitDistanceKm!.toStringAsFixed(0)} km',
              ),
            ],
            if (plan.features.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              const Divider(),
              for (final benefit in plan.features)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppDimensions.spacingXs,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: AppDimensions.iconSizeSm,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppDimensions.spacingSm),
                      Expanded(child: Text(benefit, style: AppTypography.body)),
                    ],
                  ),
                ),
            ],
            if (plan.documentStorage && plan.storageDurationDays != null) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              _benefitRow(
                Icons.folder_outlined,
                'Document storage entitlement',
                '${plan.storageDurationDays} days',
              ),
            ],
            const SizedBox(height: AppDimensions.spacingMd),
            AppButton(
              label: isCurrent ? 'Current Plan' : 'Subscribe Now',
              onPressed: isCurrent ? null : () => subscribe(plan),
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _benefitRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppDimensions.iconSizeSm, color: AppColors.primary),
        const SizedBox(width: AppDimensions.spacingSm),
        Expanded(child: Text(label, style: AppTypography.body)),
        const SizedBox(width: AppDimensions.spacingSm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
