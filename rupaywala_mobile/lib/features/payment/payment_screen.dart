import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';

/// UPI payment for a plan purchase or an existing request's extra charge.
///
/// The countdown ticks every second, status polling surfaces its own failures
/// instead of silently stopping, and the UTR form disables itself after a
/// successful submission so a payment cannot be reported twice. A verified
/// payment shows an explicit confirmation rather than dumping the user back on
/// an unrelated screen.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    this.planId,
    this.requestId,
    this.planName,
    this.amount = 0,
  }) : assert(
          planId != null || requestId != null,
          'A plan or request id is required',
        );

  final int? planId;
  final int? requestId;
  final String? planName;

  /// Display amount used before the intent resolves.
  final double amount;

  bool get isRequestPayment => requestId != null;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _utrController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  PaymentIntent? _intent;
  Timer? _pollTimer;
  Timer? _ticker;

  bool _loading = true;
  bool _submitting = false;
  bool _submitted = false;
  bool _paid = false;
  DateTime? _expiresAt;
  DateTime _now = DateTime.now();
  String? _loadError;
  String? _pollError;
  DateTime? _lastChecked;
  late final String _idempotencyKey;
  Api? _api;
  ScaffoldMessengerState? _messenger;
  bool _started = false;

  bool get _expired {
    final at = _expiresAt;
    if (at == null) return false;
    return !at.isAfter(_now);
  }

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'mobile-${widget.planId ?? 'r${widget.requestId}'}-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.api;
    _messenger = ScaffoldMessenger.of(context);
    if (_started) return;
    _started = true;
    _createIntent();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ticker?.cancel();
    _utrController.dispose();
    super.dispose();
  }

  Future<void> _createIntent({bool newKey = false}) async {
    _pollTimer?.cancel();
    _ticker?.cancel();
    setState(() {
      _loading = true;
      _loadError = null;
      _pollError = null;
      _paid = false;
      _submitted = false;
      _intent = null;
      _lastChecked = null;
    });

    try {
      final api = _api!;
      final result = widget.isRequestPayment
          ? await api.payments.createRequestPayment(
              widget.requestId!,
              idempotencyKey: newKey ? null : _idempotencyKey,
            )
          : await api.payments.createPlanPayment(
              widget.planId!,
              idempotencyKey: newKey ? null : _idempotencyKey,
            );

      if (!mounted) return;
      setState(() {
        _intent = result;
        _expiresAt = result.expiresAt ??
            DateTime.now().add(const Duration(minutes: 10));
        _now = DateTime.now();
        _loading = false;
      });
      _startTicker();
      _startPolling();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    } catch (error, stack) {
      debugPrint('Payment setup failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not set up payment. Please try again.';
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStatus(silent: true);
    });
  }

  Future<void> _checkStatus({bool silent = false}) async {
    final txn = _intent?.txnId;
    if (txn == null || txn.isEmpty || _paid) return;

    if (!silent && mounted) {
      setState(() => _pollError = null);
    }

    try {
      final result = await _api!.payments.status(txn);
      if (!mounted) return;

      final status = result.status.toLowerCase();
      final success = status == 'success' ||
          status == 'completed' ||
          status == 'verified' ||
          status == 'paid';
      setState(() {
        _lastChecked = DateTime.now();
        _pollError = null;
        if (success) _paid = true;
      });

      if (success) {
        _pollTimer?.cancel();
        _ticker?.cancel();
        await context.session.refresh();
      }
    } on ApiException catch (error) {
      if (!mounted || _paid) return;
      setState(() {
        _pollError = error.message;
        _lastChecked = DateTime.now();
      });
    } catch (error) {
      if (!mounted || _paid) return;
      setState(() {
        _pollError = 'Could not confirm the payment: $error';
        _lastChecked = DateTime.now();
      });
    }
  }

  Future<void> _openUpiApp() async {
    final url = _intent?.upiUrl;
    if (url == null || url.isEmpty) return;

    if (kIsWeb) {
      _messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'This browser cannot open UPI apps. Scan the QR code with your phone.',
          ),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'upi') {
      _messenger?.showSnackBar(
        const SnackBar(content: Text('The UPI payment link is invalid.')),
      );
      return;
    }

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _messenger?.showSnackBar(
          const SnackBar(content: Text('No UPI app found on device.')),
        );
      }
    } on Exception {
      if (mounted) {
        _messenger?.showSnackBar(
          const SnackBar(content: Text('Could not open a UPI app.')),
        );
      }
    }
  }

  Future<void> _submitUtr() async {
    if (_submitting || _submitted) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final txn = _intent?.txnId;
    if (txn == null || txn.isEmpty) return;

    setState(() {
      _submitting = true;
      _pollError = null;
    });

    try {
      final utr = _utrController.text.trim();
      if (widget.isRequestPayment) {
        await _api!.payments.submitRequestUtr(
          requestId: widget.requestId!,
          txnId: txn,
          utrNumber: utr,
        );
      } else {
        await _api!.payments.submitUtr(txnId: txn, utrNumber: utr);
      }

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
      _startPolling();
      _messenger?.showSnackBar(
        const SnackBar(
          content: Text('Reference submitted. We are verifying your payment.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _messenger?.showSnackBar(
        SnackBar(content: Text('Could not submit: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _paid ? 'Payment received' : 'Complete payment';
    return AppScaffold(
      appBar: AppPageHeader(
        title: title,
        onBack: () => Navigator.of(context).pop(_paid),
      ),
      body: _loading
          ? const AppLoading(message: 'Setting up payment...')
          : _loadError != null
              ? _setupError()
              : _paid
                  ? _success()
                  : _paymentContent(),
    );
  }

  Widget _setupError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoBanner(
              tone: InfoTone.error,
              icon: Icons.error_outline_rounded,
              title: 'Payment could not start',
              message: _loadError!,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () => _createIntent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _success() {
    final intent = _intent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      children: [
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 40,
              color: AppColors.success,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Payment received',
          textAlign: TextAlign.center,
          style: AppText.screenTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.isRequestPayment
              ? 'Your extra distance charge is paid. The request can now be assigned to a field member.'
              : 'Your membership is active. Visit allowances update as soon as the backend confirms the payment.',
          textAlign: TextAlign.center,
          style: AppText.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (intent != null)
          AppCard(
            child: Column(
              children: [
                InfoRow(
                  label: 'Amount',
                  value: Fmt.money(intent.amount, decimals: true),
                  icon: Icons.currency_rupee_rounded,
                ),
                InfoRow(
                  label: 'Transaction',
                  value: intent.txnId,
                  icon: Icons.receipt_long_outlined,
                ),
                if (intent.planName != null)
                  InfoRow(
                    label: widget.isRequestPayment ? 'Request' : 'Plan',
                    value: intent.planName!,
                    icon: Icons.workspace_premium_outlined,
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Done',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  Widget _paymentContent() {
    final intent = _intent!;
    final payable = widget.isRequestPayment ? intent.extraCharge : intent.baseAmount;
    final total = intent.amount > 0 ? intent.amount : widget.amount;

    return RefreshIndicator(
      onRefresh: () => _checkStatus(),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          AppCard(
            child: Column(
              children: [
                Text(
                  widget.planName ?? intent.planName ?? 'Rupaywala',
                  style: AppText.cardTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Fmt.money(total, decimals: true),
                  style: AppText.metricLarge.copyWith(
                    color: AppColors.primary,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _CountdownChip(expired: _expired, expiresAt: _expiresAt),
              ],
            ),
          ),
          if (intent.extraCharge > 0 || intent.taxAmount > 0) ...[
            const SizedBox(height: AppSpacing.md),
            ChargeBreakdownCard(
              baseAmount: intent.baseAmount,
              extraCharge: intent.extraCharge,
              taxAmount: intent.taxAmount,
              totalAmount: total,
              chargePaid: false,
              requiresPayment: true,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (_expired) ...[
            InfoBanner(
              tone: InfoTone.warning,
              icon: Icons.timer_off_outlined,
              title: 'This payment link expired',
              message:
                  'The QR is no longer valid. Generate a fresh payment link to continue.',
              action: TextButton(
                onPressed: () => _createIntent(newKey: true),
                child: const Text('Get a new QR'),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.qr_code_2_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Scan QR to Pay', style: AppText.cardTitle),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (intent.upiUrl.isNotEmpty)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: QrImageView(
                        data: intent.upiUrl,
                        size: 216,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                  )
                else
                  const InfoBanner(
                    tone: InfoTone.error,
                    icon: Icons.qr_code_2_rounded,
                    message: 'The payment QR code is unavailable.',
                  ),
                const SizedBox(height: AppSpacing.md),
                if (kIsWeb && intent.upiUrl.isNotEmpty) ...[
                  Text(
                    'On a computer? Scan this QR with your phone’s UPI app.',
                    style: AppText.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                AppButton(
                  label: kIsWeb
                      ? 'Open UPI App (mobile only)'
                      : 'Pay via UPI App',
                  icon: Icons.open_in_new_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: intent.upiUrl.isEmpty || _expired
                      ? null
                      : _openUpiApp,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  payable > 0
                      ? 'You can also scan the QR or open any UPI app, then enter the reference number below.'
                      : 'Pay the amount shown in your UPI app, then enter the reference number below.',
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _statusCard(),
          const SizedBox(height: AppSpacing.lg),
          _utrCard(),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final checked = _lastChecked;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Waiting for confirmation',
                  style: AppText.title.copyWith(fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: () => _checkStatus(),
                child: const Text('Check now'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            checked == null
                ? 'This screen checks automatically every few seconds.'
                : 'Last checked ${Fmt.relative(checked)}.',
            style: AppText.caption.copyWith(fontSize: 12),
          ),
          if (_submitted) ...[
            const SizedBox(height: AppSpacing.sm),
            const InfoBanner(
              tone: InfoTone.success,
              icon: Icons.hourglass_bottom_rounded,
              message:
                  'Reference submitted. Manual verification usually completes within a few minutes.',
            ),
          ],
          if (_pollError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBanner(
              tone: InfoTone.warning,
              icon: Icons.sync_problem_rounded,
              title: 'Could not confirm automatically',
              message: _pollError!,
              action: TextButton(
                onPressed: () => _checkStatus(),
                child: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _utrCard() {
    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('Already paid?', style: AppText.cardTitle),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Enter the UTR / reference number from your UPI app so the payment can be verified.',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            AppInputField(
              controller: _utrController,
              label: 'UTR / reference number',
              hint: 'e.g. 325678901234',
              prefixIcon: const Icon(Icons.numbers_rounded),
              enabled: !_submitted,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitUtr(),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 6) {
                  return 'Enter the reference number from your UPI app';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: _submitted ? 'Reference submitted' : 'Submit for verification',
              icon: _submitted
                  ? Icons.check_rounded
                  : Icons.verified_outlined,
              isLoading: _submitting,
              onPressed: _submitted || _submitting ? null : _submitUtr,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.expired, required this.expiresAt});

  final bool expired;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: expired ? AppColors.errorSoft : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            expired ? Icons.timer_off_outlined : Icons.timer_outlined,
            size: 14,
            color: expired ? AppColors.error : AppColors.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            expired
                ? 'Expired'
                : 'Expires in ${expiresAt == null ? '—' : Fmt.countdown(expiresAt!)}',
            style: TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: expired ? AppColors.error : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
