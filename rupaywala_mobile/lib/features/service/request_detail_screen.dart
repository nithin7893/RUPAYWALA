import 'package:flutter/material.dart';

import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../payment/payment_screen.dart';

/// Customer-facing request tracking.
///
/// The backend exposes `GET /service/request/{id}`, cancel and the
/// extra-charge payment intent, so those are the only actions shown here.
class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({
    super.key,
    required this.requestId,
    this.initialRequest,
  });

  final int requestId;

  /// Lets the screen paint instantly from a list row while the fresh copy
  /// loads in the background.
  final ServiceRequest? initialRequest;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  ServiceRequest? _request;
  bool _loading = true;
  bool _refreshing = false;
  bool _cancelling = false;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _request = widget.initialRequest;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(initial: widget.initialRequest != null);
  }

  Future<void> _load({bool initial = false}) async {
    if (!initial) {
      setState(() => _refreshing = true);
    }
    try {
      final request = await context.api.service.request(widget.requestId);
      if (!mounted) return;
      setState(() {
        _request = request;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pay() async {
    final request = _request;
    if (request == null) return;
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
    if (paid == true) {
      await context.session.refresh();
      await _load();
    }
  }

  Future<void> _cancel() async {
    final request = _request;
    if (request == null || _cancelling) return;

    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The visit will not be scheduled. If a visit was already used it is refunded by the backend.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await context.api.service.cancelRequest(
        request.id,
        reason: text.isEmpty ? null : text,
      );
      if (!mounted) return;
      setState(() {
        _request = updated;
        _cancelling = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Request cancelled.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not cancel: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Request details',
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh request',
            onPressed: _refreshing ? () {} : () => _load(),
          ),
        ],
      ),
      body: _loading && request == null
          ? const SkeletonList(itemCount: 3)
          : request == null
              ? ErrorStateView(
                  title: 'Request unavailable',
                  message: _error ?? 'This request could not be loaded.',
                  onRetry: () => _load(),
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
                      if (_error != null) ...[
                        InfoBanner(
                          tone: InfoTone.warning,
                          title: 'Showing saved details',
                          message:
                              'A fresh copy could not be loaded: $_error',
                          action: TextButton(
                            onPressed: () => _load(),
                            child: const Text('Retry'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _headline(request),
                      const SizedBox(height: AppSpacing.md),
                      RequestSummaryCard(request: request),
                      if (request.requiresPayment ||
                          request.extraCharge > 0) ...[
                        const SizedBox(height: AppSpacing.md),
                        ChargeBreakdownCard(
                          baseAmount: 0,
                          extraCharge: request.extraCharge,
                          taxAmount: request.taxAmount,
                          totalAmount: request.totalAmount,
                          chargePaid: request.chargePaid,
                          requiresPayment: request.requiresPayment,
                          trailingAction: request.requiresPayment &&
                                  !request.chargePaid
                              ? AppButton(
                                  label:
                                      'Pay ${Fmt.money(request.totalAmount)}',
                                  icon: Icons.payment_rounded,
                                  onPressed: _pay,
                                )
                              : null,
                        ),
                      ],
                      if (request.assignment != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        AssignmentCard(request: request),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      const SectionHeader(title: 'Progress'),
                      AppCard(child: RequestTimeline(request: request)),
                      if (request.cancellationReason?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoBanner(
                          tone: InfoTone.warning,
                          icon: Icons.cancel_outlined,
                          title: 'Cancellation reason',
                          message: request.cancellationReason!,
                        ),
                      ],
                      if (request.completionNotes?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoBanner(
                          tone: InfoTone.success,
                          icon: Icons.task_alt_rounded,
                          title: 'Completion notes',
                          message: request.completionNotes!,
                        ),
                      ],
                      if (request.proofImageUrl?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Proof document', style: AppText.cardTitle),
                              const SizedBox(height: AppSpacing.sm),
                              SecureDocumentImage(documentPath: request.proofImageUrl),
                            ],
                          ),
                        ),
                      ],
                      if (request.isOpen) ...[
                        const SizedBox(height: AppSpacing.xl),
                        AppButton(
                          label: _cancelling
                              ? 'Cancelling...'
                              : 'Cancel request',
                          variant: AppButtonVariant.secondary,
                          icon: Icons.close_rounded,
                          onPressed: _cancelling ? null : _cancel,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _helpCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _headline(ServiceRequest request) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(request.requestType, style: AppText.sectionTitle),
              const SizedBox(height: 2),
              Text(
                '${request.reference} · ${Fmt.dateTime(request.createdAt)}',
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusBadge(
          label: request.statusLabel,
          dense: false,
        ),
      ],
    );
  }

  Widget _helpCard() {
    return AppCard(
      color: AppColors.surfaceMuted,
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.support_agent_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Text(
              'Need help with this request? Contact your branch with the reference number above.',
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
