import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/status_style.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import 'admin_request_detail_screen.dart';

/// Payment verification queue.
///
/// Customers submit a UPI reference, so the only action here is verifying that
/// reference. Amounts and statuses come straight from `/admin/payments`.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  static const _filters = [
    'Pending verification',
    'All',
    'Successful',
    'Failed',
    'Expired',
  ];

  List<PaymentRecord> _payments = const [];
  Map<String, dynamic>? _summary;
  String _filter = 'Pending verification';
  bool _loading = true;
  String? _error;
  String? _summaryError;
  String? _verifyingTxn;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  List<String>? get _statuses => switch (_filter) {
        'Pending verification' => const ['pending_verification'],
        'Successful' => const ['success'],
        'Failed' => const ['failed'],
        'Expired' => const ['expired'],
        _ => null,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.api;
    try {
      final results = await Future.wait<Object?>([
        api.admin.payments(statuses: _statuses ?? const [], limit: 200),
        api.admin.paymentSummary(),
      ]);
      if (!mounted) return;
      setState(() {
        _payments = results[0] as List<PaymentRecord>;
        _summary = results[1] as Map<String, dynamic>;
        _summaryError = null;
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

  Future<void> _changeFilter(String filter) async {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    await _load();
  }

  Future<void> _verify(PaymentRecord payment, String action) async {
    if (_verifyingTxn != null) return;
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          action == 'approve' ? 'Approve this payment?' : 'Reject this payment?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${Fmt.money(payment.amount, decimals: true)} · ${payment.txnId}',
                style: AppText.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: action == 'approve'
                      ? 'Note (optional)'
                      : 'Reason for rejection',
                ),
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
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action == 'approve' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _verifyingTxn = payment.txnId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.admin.verifyPayment(
        txnId: payment.txnId,
        action: action,
        note: text.isEmpty ? null : text,
      );
      if (!mounted) return;
      setState(() => _verifyingTxn = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            action == 'approve' ? 'Payment approved.' : 'Payment rejected.',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _verifyingTxn = null);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not verify: $error')),
      );
    }
  }

  Future<void> _openRequest(PaymentRecord payment) async {
    final requestId = payment.relatedRequestId;
    if (requestId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminRequestDetailScreen(requestId: requestId),
      ),
    );
    if (mounted) _load();
  }

  int _summaryInt(String key) {
    final value = _summary?[key];
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _summaryDouble(String key) {
    final value = _summary?[key];
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _summaryInt('pending_verification');
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Payments',
        showBack: false,
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh payments',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_summary != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: _summaryCard(pending),
            ),
          if (_summaryError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: InfoBanner(
                tone: InfoTone.warning,
                message: _summaryError!,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: FilterChipRow(
              options: _filters,
              selected: _filter,
              onSelected: _changeFilter,
            ),
          ),
          Expanded(
            child: _loading
                ? const SkeletonList(itemCount: 4)
                : _error != null
                    ? ErrorStateView(
                        title: 'Payments could not load',
                        message: _error!,
                        onRetry: _load,
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: _payments.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 50),
                                  EmptyState(
                                    icon: Icons.account_balance_wallet_outlined,
                                    title: _filter == 'Pending verification'
                                        ? 'Nothing to verify'
                                        : 'No payments in this view',
                                    message:
                                        'Customer payments appear here after they submit a UPI reference.',
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  AppSpacing.md,
                                  AppSpacing.lg,
                                  AppSpacing.xxxl,
                                ),
                                itemCount: _payments.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (context, index) {
                                  final payment = _payments[index];
                                  return _PaymentCard(
                                    payment: payment,
                                    busy: _verifyingTxn == payment.txnId,
                                    onApprove: () =>
                                        _verify(payment, 'approve'),
                                    onReject: () => _verify(payment, 'reject'),
                                    onOpenRequest: payment.relatedRequestId ==
                                            null
                                        ? null
                                        : () => _openRequest(payment),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(int pending) {
    return AppCard(
      color: AppColors.primarySoft,
      borderColor: AppColors.primarySoft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collected', style: AppText.caption),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.money(
                      _summaryDouble('total_collected'),
                      decimals: true,
                    ),
                    style: AppText.metric.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 38, color: AppColors.border),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Awaiting review', style: AppText.caption),
                const SizedBox(height: 2),
                Text(
                  '$pending',
                  style: AppText.metric.copyWith(
                    color: pending > 0 ? AppColors.warning : AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Success', style: AppText.caption),
              const SizedBox(height: 2),
              Text(
                '${_summaryInt('success')}',
                style: AppText.title.copyWith(fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onOpenRequest,
  });

  final PaymentRecord payment;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onOpenRequest;

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.forPayment(payment.status);
    final canVerify = payment.status == 'pending_verification';
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: payment.isPlanPayment
                    ? Icons.workspace_premium_outlined
                    : Icons.route_outlined,
                color: style.color,
                background: style.background,
                size: 42,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment.title, style: AppText.cardTitle),
                    const SizedBox(height: 2),
                    Text(
                      '${payment.txnId} · ${Fmt.relative(payment.submittedAt ?? payment.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.money(payment.amount, decimals: true),
                    style: AppText.title.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  StatusBadge(
                    label: style.label,
                    color: style.color,
                    background: style.background,
                    icon: style.icon,
                    dense: true,
                  ),
                ],
              ),
            ],
          ),
          if (payment.utrNumber?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            InfoRow(
              label: 'UTR / reference',
              value: payment.utrNumber!,
              icon: Icons.numbers_rounded,
              isLast: true,
            ),
          ],
          if (canVerify) ...[
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
          if (onOpenRequest != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenRequest,
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text('View request'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
