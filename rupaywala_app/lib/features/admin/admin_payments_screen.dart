import 'package:flutter/material.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  List<PaymentRecord> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    try {
      final payments = await context.api.admin.payments(statuses: ['pending']);
      if (mounted) {
        setState(() {
          _payments = payments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading payments: $e")),
        );
      }
    }
  }

  Future<void> _verifyPayment(String txnId, String action) async {
    try {
      await context.api.admin.verifyPayment(txnId: txnId, action: action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payment $action")),
        );
        _loadPayments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payment Verification"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPayments,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _payments.isEmpty
              ? EmptyState(
                  icon: Icons.payment_outlined,
                  title: "No Pending Payments",
                  subtitle: "Payment verification requests will appear here",
                  actionLabel: "Refresh",
                  onAction: _loadPayments,
                )
              : ListView.builder(
                  padding: AppDimensions.pagePadding,
                  itemCount: _payments.length,
                  itemBuilder: (context, index) {
                    final payment = _payments[index];
                    return Container(
                      margin: const EdgeInsets.only(
                          bottom: AppDimensions.spacingMd),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(
                                      AppDimensions.spacingSm),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusSm),
                                  ),
                                  child: Icon(
                                    Icons.payment,
                                    color: AppColors.warning,
                                    size: AppDimensions.iconSizeMd,
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.spacingMd),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Txn ID: ${payment.txnId}",
                                        style: AppTypography.cardTitle,
                                      ),
                                      Text(
                                        "UTR: ${payment.utrNumber ?? 'N/A'}",
                                        style: AppTypography.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppDimensions.spacingSm,
                                    vertical: AppDimensions.spacingXs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusFull),
                                  ),
                                  child: Text(
                                    payment.status,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),
                            Text(
                              "Amount: ₹${payment.amount}",
                              style: AppTypography.cardTitle,
                            ),
                            Text(
                              "Plan: ${payment.planName ?? payment.title}",
                              style: AppTypography.body,
                            ),
                            Text(
                              payment.relatedRequestId == null
                                  ? "Payment type: ${payment.paymentType}"
                                  : "Request ID: ${payment.relatedRequestId}",
                              style: AppTypography.caption,
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),
                            Row(
                              children: [
                                Expanded(
                                  child: AppButton(
                                    label: "Approve",
                                    onPressed: () => _verifyPayment(
                                      payment.txnId,
                                      'approve',
                                    ),
                                    icon: Icons.check,
                                    variant: AppButtonVariant.secondary,
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.spacingMd),
                                Expanded(
                                  child: AppButton(
                                    label: "Reject",
                                    onPressed: () => _verifyPayment(
                                      payment.txnId,
                                      'reject',
                                    ),
                                    icon: Icons.close,
                                    variant: AppButtonVariant.danger,
                                  ),
                                ),
                              ],
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
