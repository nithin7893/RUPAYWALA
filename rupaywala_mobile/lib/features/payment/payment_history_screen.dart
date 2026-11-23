import 'package:flutter/material.dart';

import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../service/request_detail_screen.dart';

/// Every UPI payment on the account, with the verification state and the
/// reference number the customer submitted.
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<PaymentRecord> _payments = const [];
  PaymentTotals? _totals;
  bool _loading = true;
  String? _error;
  String? _totalsError;
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
    final api = context.api;
    try {
      final results = await Future.wait([
        api.payments.myPayments(),
        api.subscriptions.paymentSummary(),
      ]);
      if (!mounted) return;
      setState(() {
        _payments = results[0] as List<PaymentRecord>;
        _totals = results[1] as PaymentTotals;
        _totalsError = null;
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

  Future<void> _open(PaymentRecord payment) async {
    final requestId = payment.relatedRequestId;
    if (requestId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RequestDetailScreen(requestId: requestId),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Payments',
        actions: [
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh payments',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 3)
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
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 70),
                            EmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: 'No payments yet',
                              subtitle:
                                  'Plan purchases and extra distance charges will appear here after you pay.',
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.xxxl,
                          ),
                          children: [
                            if (_totals != null) _summary(_totals!),
                            if (_totalsError != null) ...[
                              InfoBanner(
                                tone: InfoTone.warning,
                                message: _totalsError!,
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            const SectionHeader(title: 'Payment history'),
                            for (final payment in _payments) ...[
                              _PaymentCard(
                                payment: payment,
                                onTap: payment.relatedRequestId == null
                                    ? null
                                    : () => _open(payment),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                          ],
                        ),
                ),
    );
  }

  Widget _summary(PaymentTotals totals) {
    return AppCard(
      color: AppColors.primarySoft,
      borderColor: AppColors.primarySoft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total paid', style: AppText.caption),
                const SizedBox(height: 2),
                Text(
                  Fmt.money(totals.totalPaid),
                  style: AppText.metric.copyWith(color: AppColors.primary),
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
                Text('Awaiting verification', style: AppText.caption),
                const SizedBox(height: 2),
                Text(
                  '${totals.awaitingVerification}',
                  style: AppText.metric.copyWith(
                    color: totals.awaitingVerification > 0
                        ? AppColors.warning
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, this.onTap});

  final PaymentRecord payment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = payment.status.toLowerCase();
    final verified = status == 'success' || status == 'completed';
    final pending = status == 'pending' || status == 'pending_verification';
    final color = verified
        ? AppColors.success
        : (pending ? AppColors.warning : AppColors.error);
    final background = verified
        ? AppColors.successSoft
        : (pending ? AppColors.warningSoft : AppColors.errorSoft);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: payment.isPlanPayment
                    ? Icons.workspace_premium_outlined
                    : Icons.route_outlined,
                color: color,
                background: background,
                size: 40,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment.title, style: AppText.cardTitle),
                    const SizedBox(height: 2),
                    Text(
                      Fmt.dateTime(payment.submittedAt ?? payment.createdAt),
                      style: AppText.caption.copyWith(fontSize: 12),
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
                    label: verified
                        ? 'Verified'
                        : (pending ? 'Verifying' : _label(status)),
                    color: color,
                    background: background,
                    dense: true,
                  ),
                ],
              ),
            ],
          ),
          if (payment.utrNumber?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            InfoRow(
              label: 'UTR / reference',
              value: payment.utrNumber!,
              icon: Icons.numbers_rounded,
              isLast: true,
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Spacer(),
                Text(
                  'View request',
                  style: AppText.label.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primary,
                  size: 19,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _label(String status) {
    if (status.isEmpty) return 'Unknown';
    return status[0].toUpperCase() + status.substring(1);
  }
}
