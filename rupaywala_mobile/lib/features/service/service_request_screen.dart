import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../payment/payment_screen.dart';
import '../policy/add_policy_screen.dart';
import '../shell/role_shell.dart';
import 'request_detail_screen.dart';

/// Guided three-step service request.
///
/// Step 1 picks the service and the policy, step 2 resolves the visit address
/// and the serving branch (the backend supplies both the nearest branches and
/// the distance quote), step 3 reviews the real charge breakdown before the
/// request is created. Nothing is submitted until the final step.
class ServiceRequestScreen extends StatefulWidget {
  const ServiceRequestScreen({super.key, this.onCreated});

  /// Called after the request exists. The shell uses it to move to Requests.
  final ValueChanged<ServiceRequest>? onCreated;

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  int _step = 0;

  List<ServiceType> _serviceTypes = const [];
  List<Policy> _policies = const [];
  bool _loadingCatalogs = true;
  String? _catalogError;

  ServiceType? _service;
  Policy? _policy;
  final _description = TextEditingController();

  final _placeQuery = TextEditingController();
  Timer? _searchDebounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  String? _searchError;
  PlaceSuggestion? _place;

  List<BranchQuote> _branches = const [];
  bool _loadingBranches = false;
  String? _branchError;
  BranchQuote? _branch;
  FixedQuote? _quote;
  bool _loadingQuote = false;
  String? _quoteError;

  bool _submitting = false;
  String? _submitError;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadCatalogs();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _description.dispose();
    _placeQuery.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    setState(() {
      _loadingCatalogs = true;
      _catalogError = null;
    });
    final api = context.api;
    try {
      final results = await Future.wait([
        api.service.serviceTypes(),
        api.customer.policies(),
      ]);
      if (!mounted) return;
      setState(() {
        _serviceTypes = results[0] as List<ServiceType>;
        _policies = results[1] as List<Policy>;
        _loadingCatalogs = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCatalogs = false;
        _catalogError = '$error';
      });
    }
  }

  bool get _canContinueFromService => _service != null && _policy != null;

  bool get _canContinueFromLocation => _place != null && _branch != null;

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step.clamp(0, 2));
  }

  void _onPlaceChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _suggestions = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _searchPlaces(value.trim());
    });
  }

  Future<void> _searchPlaces(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await context.api.service.searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = '$error';
      });
    }
  }

  Future<void> _selectPlace(PlaceSuggestion place) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _place = place;
      _placeQuery.text = place.address.isEmpty ? place.title : place.address;
      _suggestions = const [];
      _branch = null;
      _quote = null;
      _quoteError = null;
      _branches = const [];
      _branchError = null;
      _loadingBranches = true;
    });

    try {
      final branches = await context.api.service.nearestBranches(
        latitude: place.latitude,
        longitude: place.longitude,
      );
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loadingBranches = false;
      });
      if (branches.length == 1) {
        await _selectBranch(branches.first);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingBranches = false;
        _branchError = '$error';
      });
    }
  }

  Future<void> _selectBranch(BranchQuote branch) async {
    final place = _place;
    final service = _service;
    final policy = _policy;
    if (place == null || service == null || policy == null) return;
    setState(() {
      _branch = branch;
      _quote = null;
      _quoteError = null;
      _loadingQuote = true;
    });
    try {
      final quote = await context.api.service.createFixedQuote(
        policyId: policy.id,
        requestType: service.name,
        serviceTypeId: service.id,
        latitude: place.latitude,
        longitude: place.longitude,
        address: place.address.isEmpty ? place.title : place.address,
        placeId: place.placeId,
        branchId: branch.id,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _loadingQuote = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingQuote = false;
        _quoteError = '$error';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final service = _service;
    final policy = _policy;
    final place = _place;
    final branch = _branch;
    if (service == null || policy == null || place == null || branch == null) {
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final request = await context.api.service.createRequest(
        policyId: policy.id,
        requestType: service.name,
        description: _description.text,
        serviceTypeId: service.id,
        latitude: place.latitude,
        longitude: place.longitude,
        address: place.address.isEmpty ? place.title : place.address,
        placeId: place.placeId,
        branchId: branch.id,
        quoteId: _quote?.quoteId,
      );

      if (!mounted) return;

      if (request.requiresPayment && !request.chargePaid) {
        final paid = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => PaymentScreen(
              requestId: request.id,
              planName: request.requestType,
              amount: request.totalAmount,
            ),
          ),
        );
        if (!mounted) return;
        if (paid != true) {
          // The request exists and is awaiting payment, so send the customer to
          // its tracking screen rather than pretending submission failed.
          _finish(request, paid: false);
          return;
        }
      }

      _finish(request, paid: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error is Exception ? '$error' : '$error';
      });
    }
  }

  void _finish(ServiceRequest request, {required bool paid}) {
    setState(() => _submitting = false);
    widget.onCreated?.call(request);
    final shell = RoleShellScope.maybeOf(context);
    if (shell != null) {
      shell.openTab(ShellTab.requests);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          paid && request.requiresPayment
              ? 'Request created and payment submitted for verification.'
              : 'Request ${request.reference} created.',
        ),
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RequestDetailScreen(
          requestId: request.id,
          initialRequest: request,
        ),
      ),
    );
  }

  void _resetForm() {
    setState(() {
      _step = 0;
      _service = null;
      _policy = null;
      _description.clear();
      _place = null;
      _placeQuery.clear();
      _suggestions = const [];
      _branches = const [];
      _branch = null;
      _quote = null;
      _submitError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'New request',
        showBack: false,
        actions: [
          if (_step > 0)
            TextButton(
              onPressed: _submitting ? null : _resetForm,
              child: const Text('Start over'),
            ),
        ],
      ),
      body: _loadingCatalogs
          ? const AppLoading(message: 'Loading services...')
          : _catalogError != null
              ? ErrorStateView(
                  title: 'Services unavailable',
                  message: _catalogError!,
                  onRetry: _loadCatalogs,
                )
              : Column(
                  children: [
                    _StepHeader(step: _step),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: kMediumAnimation,
                        child: switch (_step) {
                          0 => _serviceStep(),
                          1 => _locationStep(),
                          _ => _reviewStep(),
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _loadingCatalogs || _catalogError != null
          ? null
          : _bottomBar(),
    );
  }

  Widget _bottomBar() {
    final isLast = _step == 2;
    final enabled = switch (_step) {
      0 => _canContinueFromService,
      1 => _canContinueFromLocation && !_loadingQuote && _quote != null,
      _ => !_submitting && _quote != null,
    };
    final amount = _quote?.totalAmount ?? 0;
    final requiresPayment = _quote?.requiresPayment ?? false;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              if (_step > 0) ...[
                SizedBox(
                  width: 96,
                  child: AppButton(
                    label: 'Back',
                    variant: AppButtonVariant.secondary,
                    onPressed: _submitting ? null : () => _goToStep(_step - 1),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: AppButton(
                  label: !isLast
                      ? 'Continue'
                      : (requiresPayment
                          ? 'Submit & pay ${Fmt.money(amount)}'
                          : 'Submit request'),
                  trailingIcon:
                      isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  isLoading: _submitting,
                  onPressed: enabled
                      ? (isLast ? _submit : () => _goToStep(_step + 1))
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceStep() {
    return ListView(
      key: const ValueKey('service-step'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        const SectionHeader(title: 'What do you need?'),
        if (_serviceTypes.isEmpty)
          const InfoBanner(
            tone: InfoTone.warning,
            message:
                'No services are available right now. Please try again later.',
          )
        else
          for (final type in _serviceTypes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ChoiceCard(
                selected: _service?.id == type.id,
                icon: _serviceIcon(type.code),
                title: type.name,
                subtitle: type.description,
                onTap: () => setState(() => _service = type),
              ),
            ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Which policy?'),
        if (_policies.isEmpty)
          InfoBanner(
            tone: InfoTone.warning,
            icon: Icons.shield_outlined,
            title: 'Add a policy first',
            message:
                'Every request must be linked to an insurance policy on your account.',
            action: TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AddPolicyScreen(),
                  ),
                );
                if (mounted) _loadCatalogs();
              },
              child: const Text('Add policy'),
            ),
          )
        else
          for (final policy in _policies)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ChoiceCard(
                selected: _policy?.id == policy.id,
                icon: Icons.shield_outlined,
                title: policy.title,
                subtitle:
                    '${policy.providerName} · ${policy.policyNumber}',
                trailing: policy.isValid ? null : 'Expired',
                onTap: () => setState(() => _policy = policy),
              ),
            ),
        const SizedBox(height: AppSpacing.lg),
        AppInputField(
          controller: _description,
          label: 'Notes for the field member',
          hint: 'Anything they should know before the visit',
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }

  Widget _locationStep() {
    return ListView(
      key: const ValueKey('location-step'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        const SectionHeader(
          title: 'Where should we visit?',
          subtitle: 'Search for your address, then choose the nearest branch.',
        ),
        AppInputField(
          controller: _placeQuery,
          label: 'Visit address',
          hint: 'House, street, area or landmark',
          prefixIcon: const Icon(Icons.search_rounded),
          textCapitalization: TextCapitalization.words,
          onChanged: _onPlaceChanged,
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        if (_searchError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBanner(
            tone: InfoTone.error,
            message: _searchError!,
            action: TextButton(
              onPressed: () => _searchPlaces(_placeQuery.text.trim()),
              child: const Text('Retry'),
            ),
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final suggestion in _suggestions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(suggestion.title),
                    subtitle: Text(
                      suggestion.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectPlace(suggestion),
                  ),
              ],
            ),
          ),
        ],
        if (_place != null) ...[
          const SizedBox(height: AppSpacing.md),
          InfoBanner(
            tone: InfoTone.success,
            icon: Icons.check_circle_outline_rounded,
            message: _place!.address.isEmpty
                ? _place!.title
                : _place!.address,
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
            title: 'Choose a branch',
            subtitle: 'Branches are ordered by road distance.',
          ),
          if (_loadingBranches)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: AppLoading(message: 'Finding nearest branches...'),
            )
          else if (_branchError != null)
            ErrorStateView(
              title: 'Branches unavailable',
              message: _branchError!,
              onRetry: () => _selectPlace(_place!),
            )
          else if (_branches.isEmpty)
            const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No branches found',
              subtitle: 'Try a different address or contact support.',
              compact: true,
            )
          else
            for (final branch in _branches)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BranchCard(
                  branch: branch,
                  selected: _branch?.id == branch.id,
                  loadingQuote:
                      _loadingQuote && _branch?.id == branch.id,
                  onTap: () => _selectBranch(branch),
                ),
              ),
          if (_quoteError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBanner(
              tone: InfoTone.error,
              message: _quoteError!,
              action: TextButton(
                onPressed: () => _selectBranch(_branch!),
                child: const Text('Retry'),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _reviewStep() {
    final service = _service;
    final policy = _policy;
    final place = _place;
    final branch = _branch;
    final quote = _quote;

    if (service == null || policy == null || place == null || branch == null) {
      return const EmptyState(
        icon: Icons.info_outline,
        title: 'Missing details',
        subtitle: 'Go back and choose a service, policy and branch.',
      );
    }

    return ListView(
      key: const ValueKey('review-step'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        const SectionHeader(title: 'Review your request'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewRow(
                icon: Icons.handyman_outlined,
                label: 'Service',
                value: service.name,
              ),
              _ReviewRow(
                icon: Icons.shield_outlined,
                label: 'Policy',
                value: '${policy.title} · ${policy.policyNumber}',
              ),
              _ReviewRow(
                icon: Icons.location_on_outlined,
                label: 'Visit address',
                value: place.address.isEmpty ? place.title : place.address,
              ),
              _ReviewRow(
                icon: Icons.storefront_outlined,
                label: 'Branch',
                value: branch.name,
                isLast: _description.text.trim().isEmpty,
              ),
              if (_description.text.trim().isNotEmpty)
                _ReviewRow(
                  icon: Icons.notes_rounded,
                  label: 'Notes',
                  value: _description.text.trim(),
                  isLast: true,
                ),
            ],
          ),
        ),
        if (quote != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'Distance and charges',
            subtitle:
                '${Fmt.km(quote.distanceKm)} · ${Fmt.duration(quote.durationMinutes)} travel',
          ),
          ChargeBreakdownCard(
            baseAmount: 0,
            extraCharge: quote.extraCharge,
            taxAmount: quote.taxAmount,
            totalAmount: quote.totalAmount,
            chargePaid: !quote.requiresPayment,
            requiresPayment: quote.requiresPayment,
            note: quote.withinThreshold
                ? 'Your visit is within the ${Fmt.km(quote.thresholdKm)} included radius, so no extra distance charge applies.'
                : 'This branch is ${Fmt.km(quote.excessDistanceKm)} beyond the included ${Fmt.km(quote.thresholdKm)} radius, charged at ${Fmt.money(quote.chargePerKm, decimals: true)} per km (round trip ×${quote.roundTripFactor.toStringAsFixed(1)}).',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        InfoBanner(
          tone: InfoTone.info,
          icon: Icons.info_outline_rounded,
          message:
              'One visit will be deducted from your plan when the field member completes the job${quote?.requiresPayment == true ? '. The extra distance charge is collected by UPI before assignment.' : '.'}',
        ),
        if (_submitError != null) ...[
          const SizedBox(height: AppSpacing.md),
          InfoBanner(
            tone: InfoTone.error,
            icon: Icons.error_outline_rounded,
            message: _submitError!,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  static const _labels = ['Service', 'Location', 'Review'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          for (var index = 0; index < _labels.length; index++) ...[
            if (index > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  color: step >= index ? AppColors.primary : AppColors.border,
                ),
              ),
            _StepDot(
              number: index + 1,
              label: _labels[index],
              state: step == index
                  ? _StepState.current
                  : (step > index ? _StepState.done : _StepState.todo),
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { done, current, todo }

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.state,
  });

  final int number;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final done = state == _StepState.done;
    final current = state == _StepState.current;
    final color = done
        ? AppColors.primary
        : (current ? AppColors.primary : AppColors.border);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done || current ? color : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontFamily: AppText.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: current ? Colors.white : AppColors.textHint,
                  ),
                ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppText.caption.copyWith(
            fontSize: 11,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
            color: current ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? Colors.white : AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.title),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          style: AppText.caption.copyWith(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      trailing!,
                      style: AppText.caption.copyWith(color: AppColors.error),
                    ),
                  ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primary : AppColors.textHint,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.selected,
    required this.loadingQuote,
    required this.onTap,
  });

  final BranchQuote branch;
  final bool selected;
  final bool loadingQuote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 19,
                      color: selected ? AppColors.primary : AppColors.textHint,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(branch.name, style: AppText.title),
                    ),
                    if (loadingQuote)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      StatusBadge(
                        label: branch.withinThreshold
                            ? 'No extra charge'
                            : Fmt.money(branch.totalAmount),
                        color: branch.withinThreshold
                            ? AppColors.success
                            : AppColors.warning,
                        background: branch.withinThreshold
                            ? AppColors.successSoft
                            : AppColors.warningSoft,
                        dense: true,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 27),
                  child: Text(
                    branch.address,
                    style: AppText.caption.copyWith(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(left: 27),
                  child: Wrap(
                    spacing: AppSpacing.md,
                    children: [
                      _Meta(
                        icon: Icons.route_outlined,
                        text: Fmt.km(branch.distanceKm),
                      ),
                      _Meta(
                        icon: Icons.schedule_outlined,
                        text: Fmt.duration(branch.durationMinutes),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textHint),
        const SizedBox(width: 3),
        Text(text, style: AppText.caption.copyWith(fontSize: 11.5)),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textHint),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.caption),
                const SizedBox(height: 1),
                Text(value, style: AppText.title.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _serviceIcon(String code) {
  final value = code.toLowerCase();
  if (value.contains('renew')) return Icons.autorenew_rounded;
  if (value.contains('claim')) return Icons.assignment_turned_in_outlined;
  if (value.contains('doc')) return Icons.folder_open_outlined;
  if (value.contains('pickup')) return Icons.local_shipping_outlined;
  if (value.contains('verify') || value.contains('verification')) {
    return Icons.verified_outlined;
  }
  if (value.contains('health')) return Icons.health_and_safety_outlined;
  if (value.contains('vehicle') || value.contains('car')) {
    return Icons.directions_car_outlined;
  }
  return Icons.handyman_outlined;
}
