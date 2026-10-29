import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_scope.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class PaymentScreen extends StatefulWidget {
  final int planId;
  final String planName;
  final double amount;

  const PaymentScreen({
    super.key,
    required this.planId,
    required this.planName,
    required this.amount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final utrController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool isLoading = true;
  bool isSubmitting = false;
  String? txnId;
  String? upiUrl;
  DateTime? expiresAt;
  Timer? pollTimer;
  Api? _api;
  SessionController? _session;
  ScaffoldMessengerState? _messenger;
  String? _loadError;
  bool _initializationStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.api;
    _session = context.session;
    _messenger = ScaffoldMessenger.of(context);
    if (_initializationStarted) return;
    _initializationStarted = true;
    initPayment();
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    utrController.dispose();
    super.dispose();
  }

  Future<void> initPayment() async {
    final api = _api!;
    try {
      final result = await api.payments.createPlanPayment(widget.planId);

      if (!mounted) return;
      setState(() {
        txnId = result.txnId;
        upiUrl = result.upiUrl;
        expiresAt = result.expiresAt;
        _loadError = null;
        isLoading = false;
      });

      if (txnId != null && txnId!.isNotEmpty) startPolling();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          _loadError = e.message;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Payment setup failed: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          isLoading = false;
          _loadError = 'Could not set up payment. Please try again.';
        });
      }
    }
  }

  void startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkPaymentStatus();
    });
  }

  void checkPaymentStatus() async {
    if (txnId == null || isSubmitting) return;

    try {
      final result = await _api!.payments.status(txnId!);
      final status = result.status;

      if (status == "success") {
        pollTimer?.cancel();
        if (mounted) {
          await _session!.refresh();
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } on ApiException {
      // Silently ignore polling errors - payment still pending
    }
  }

  void openUpiApp() async {
    final paymentUrl = upiUrl;
    if (paymentUrl == null || paymentUrl.isEmpty) return;

    if (kIsWeb) {
      if (mounted) {
        _messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              "This browser cannot open UPI apps. Scan the QR code with your phone.",
            ),
          ),
        );
      }
      return;
    }

    final uri = Uri.tryParse(paymentUrl);
    if (uri == null || uri.scheme != 'upi') {
      _messenger?.showSnackBar(
        const SnackBar(content: Text("The UPI payment link is invalid.")),
      );
      return;
    }

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _messenger?.showSnackBar(
          const SnackBar(content: Text("No UPI app found on device")),
        );
      }
    } on Exception {
      if (mounted) {
        _messenger?.showSnackBar(
          const SnackBar(content: Text("Could not open a UPI app.")),
        );
      }
    }
  }

  void submitUtr() async {
    if (txnId == null || !_formKey.currentState!.validate()) return;

    setState(() => isSubmitting = true);

    try {
      await _api!.payments.submitUtr(
        txnId: txnId!,
        utrNumber: utrController.text.trim(),
      );

      if (mounted) {
        _messenger?.showSnackBar(
          const SnackBar(content: Text("Payment submitted for verification")),
        );
      }

      pollTimer?.cancel();
      startPolling();
    } catch (e) {
      if (mounted) {
        _messenger?.showSnackBar(
          SnackBar(content: Text("Failed to submit: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  String getExpiryText() {
    if (expiresAt == null) return "";
    final diff = expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return "Expired";
    final mins = diff.inMinutes;
    final secs = diff.inSeconds % 60;
    return "${mins}m ${secs}s";
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return expiresAt!.difference(DateTime.now()).isNegative;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Complete Payment"),
      ),
      body: isLoading
          ? const AppLoading(message: "Setting up payment...")
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: AppDimensions.pagePadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InfoBanner(
                          tone: InfoTone.error,
                          icon: Icons.error_outline_rounded,
                          message: _loadError!,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),
                        AppButton(
                          label: "Retry",
                          onPressed: () {
                            setState(() {
                              isLoading = true;
                              _loadError = null;
                              txnId = null;
                              upiUrl = null;
                            });
                            initPayment();
                          },
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: AppDimensions.pagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        child: Column(
                          children: [
                            Text(
                              widget.planName,
                              style: AppTypography.sectionTitle,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppDimensions.spacingSm),
                            Text(
                              "₹${widget.amount.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 28,
                                color: AppColors.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: AppDimensions.spacingSm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDimensions.spacingMd,
                                vertical: AppDimensions.spacingXs,
                              ),
                              decoration: BoxDecoration(
                                color: isExpired
                                    ? AppColors.error.withValues(alpha: 0.1)
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(
                                    AppDimensions.radiusFull),
                              ),
                              child: Text(
                                "Expires in: ${getExpiryText()}",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isExpired
                                      ? AppColors.error
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingLg),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.qr_code_2,
                                    color: AppColors.primary,
                                    size: AppDimensions.iconSizeMd),
                                const SizedBox(width: AppDimensions.spacingSm),
                                Text("Scan QR to Pay",
                                    style: AppTypography.cardTitle),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),
                            if (upiUrl != null && upiUrl!.isNotEmpty)
                              Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: AppColors.border),
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusMd),
                                  ),
                                  padding: const EdgeInsets.all(
                                      AppDimensions.spacingMd),
                                  child: QrImageView(
                                    data: upiUrl!,
                                    size: 220,
                                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                                  ),
                                ),
                              )
                            else
                              const InfoBanner(
                                tone: InfoTone.error,
                                icon: Icons.qr_code_2,
                                message: "The payment QR code is unavailable.",
                              ),
                            if (kIsWeb &&
                                upiUrl != null &&
                                upiUrl!.isNotEmpty) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Text(
                                "On a computer? Scan this QR with your phone's UPI app.",
                                style: AppTypography.body,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: AppDimensions.spacingMd),
                            AppButton(
                              label: kIsWeb
                                  ? "Open UPI App (mobile only)"
                                  : "Pay via UPI App",
                              onPressed: upiUrl == null || upiUrl!.isEmpty
                                  ? null
                                  : openUpiApp,
                              icon: Icons.open_in_new,
                              variant: AppButtonVariant.secondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingLg),
                      AppCard(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.receipt_long,
                                      color: AppColors.primary,
                                      size: AppDimensions.iconSizeMd),
                                  const SizedBox(
                                      width: AppDimensions.spacingSm),
                                  Text("Manual Verification",
                                      style: AppTypography.cardTitle),
                                ],
                              ),
                              const SizedBox(height: AppDimensions.spacingSm),
                              Text(
                                "After payment, enter your UTR / Reference Number below",
                                style: AppTypography.body,
                              ),
                              const SizedBox(height: AppDimensions.spacingMd),
                              AppInputField(
                                label: "UTR / Reference Number",
                                hint: "e.g. 325678901234",
                                controller: utrController,
                                prefixIcon: const Icon(Icons.numbers,
                                    color: AppColors.textHint),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Please enter UTR number";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: AppDimensions.spacingMd),
                              AppButton(
                                label: "Submit & Verify",
                                onPressed: submitUtr,
                                isLoading: isSubmitting,
                                icon: Icons.verified,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingLg),
                    ],
                  ),
                ),
    );
  }
}
