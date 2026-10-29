import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/customer_models.dart';
import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';

class ServiceRequestScreen extends StatefulWidget {
  const ServiceRequestScreen({super.key});

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  final typeController = TextEditingController();
  final descriptionController = TextEditingController();
  final addressController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool isLoading = false;
  bool isGeocoding = false;
  List<Branch> branches = [];
  List<Policy> policies = [];
  List<SubscriptionFamilyMember> familyMembers = [];
  DistanceQuote? distanceResult;
  bool isDistanceLoading = false;
  String? distanceError;
  int? selectedBranchId;
  int? selectedPolicyId;
  int? selectedFamilyMemberId;
  double? geocodedLat;
  double? geocodedLng;
  String? geocodedDisplayName;

  // Extra charge payment state
  bool isCreatingRequest = false;
  bool extraChargePaid = false;
  int? _createdRequestId;
  String? _extraChargeTxnId;
  String? _extraChargeUpiUrl;
  String? _extraChargeQrCodeBase64;
  DateTime? _extraChargeExpiresAt;
  bool _isSubmittingUtr = false;
  Timer? _paymentPollTimer;
  final _extraChargeUtrController = TextEditingController();
  final _extraChargeFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    loadBranches();
    loadPolicies();
    loadFamilyMembers();
  }

  Future<void> loadFamilyMembers() async {
    try {
      final api = context.api;
      final current = await api.subscriptions.currentSubscription();
      final limit = current?.entitlements['max_family_members'];
      if (current?.isActive != true || limit is! num || limit <= 1) return;
      final result = await api.subscriptions.familyMembers();
      if (!mounted) return;
      setState(() => familyMembers = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load family members: $e')),
      );
    }
  }

  @override
  void dispose() {
    _paymentPollTimer?.cancel();
    _extraChargeUtrController.dispose();
    typeController.dispose();
    descriptionController.dispose();
    addressController.dispose();
    super.dispose();
  }

  void loadBranches() async {
    try {
      final result = await context.api.service.branches();
      if (mounted) {
        setState(() {
          branches = result;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load branches: $e")),
        );
      }
    }
  }

  void loadPolicies() async {
    try {
      final result = await context.api.customer.policies();
      if (mounted) {
        setState(() {
          policies = result;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load policies: $e")),
        );
      }
    }
  }

  void getLocation() async {
    if (addressController.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid address")),
      );
      return;
    }

    setState(() {
      isGeocoding = true;
      geocodedLat = null;
      geocodedLng = null;
      geocodedDisplayName = null;
    });

    setState(() {
      distanceResult = null;
      distanceError = null;
    });

    try {
      final suggestions = await context.api.service.searchPlaces(
        addressController.text.trim(),
      );
      if (!mounted) return;
      if (suggestions.isEmpty) {
        throw StateError("No locations matched that address");
      }
      final suggestion = suggestions.length == 1
          ? suggestions.single
          : await showDialog<PlaceSuggestion>(
              context: context,
              builder: (dialogContext) => SimpleDialog(
                title: const Text("Choose your location"),
                children: suggestions
                    .map(
                      (place) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(dialogContext, place),
                        child: Text(place.address.isEmpty
                            ? place.title
                            : place.address),
                      ),
                    )
                    .toList(),
              ),
            );
      if (suggestion != null && mounted) {
        setState(() {
          geocodedLat = suggestion.latitude;
          geocodedLng = suggestion.longitude;
          geocodedDisplayName = suggestion.address;
          addressController.text = suggestion.address;
        });
      }
      if (mounted) setState(() => isGeocoding = false);
    } catch (e) {
      if (mounted) {
        setState(() => isGeocoding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location lookup failed: $e")),
        );
      }
    }
  }

  void checkDistance() async {
    if (geocodedLat == null || geocodedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please get your location first")),
      );
      return;
    }
    if (selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a branch")),
      );
      return;
    }

    Branch? selectedBranch;
    for (final branch in branches) {
      if (branch.id == selectedBranchId) {
        selectedBranch = branch;
        break;
      }
    }
    if (selectedBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid branch selected")),
      );
      return;
    }

    setState(() {
      isDistanceLoading = true;
      distanceError = null;
      distanceResult = null;
    });
    try {
      final quote = await context.api.service.checkDistance(
        latitude: geocodedLat!,
        longitude: geocodedLng!,
        branchId: selectedBranch.id,
      );
      if (mounted) setState(() => distanceResult = quote);
    } catch (e) {
      if (mounted) setState(() => distanceError = e.toString());
    } finally {
      if (mounted) setState(() => isDistanceLoading = false);
    }

    if (distanceError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(distanceError!)),
      );
    }
  }

  void createRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (geocodedLat == null || geocodedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please get your location first")),
      );
      return;
    }
    if (selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a branch")),
      );
      return;
    }

    final quote = distanceResult;

    if (quote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please check distance first")),
      );
      return;
    }

    // If extra charge applies and not yet paid, initiate payment flow
    if (quote.requiresPayment && !extraChargePaid) {
      await _initiateExtraChargePayment();
      return;
    }

    setState(() => isLoading = true);

    try {
      await context.api.service.createRequest(
        policyId: selectedPolicyId!,
        requestType: typeController.text,
        description: descriptionController.text,
        latitude: geocodedLat!,
        longitude: geocodedLng!,
        address: addressController.text.trim(),
        branchId: selectedBranchId!,
        familyMemberId: selectedFamilyMemberId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Service Request Created Successfully")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to create request: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // =============================
  // EXTRA CHARGE PAYMENT FLOW
  // =============================
  Future<void> _initiateExtraChargePayment() async {
    final api = context.api;
    setState(() => isCreatingRequest = true);

    try {
      // Step 1: Create the service request first
      final requestResult = await api.service.createRequest(
        policyId: selectedPolicyId!,
        requestType: typeController.text,
        description: descriptionController.text,
        latitude: geocodedLat!,
        longitude: geocodedLng!,
        address: addressController.text.trim(),
        branchId: selectedBranchId!,
        familyMemberId: selectedFamilyMemberId,
      );

      final requestId = requestResult.id;
      _createdRequestId = requestId;

      // Step 2: Initiate extra charge payment
      final paymentResult =
          await api.service.createExtraChargePayment(requestId);

      if (mounted) {
        setState(() {
          _extraChargeTxnId = paymentResult.txnId;
          _extraChargeUpiUrl = paymentResult.upiUrl;
          _extraChargeQrCodeBase64 = paymentResult.qrCodeBase64;
          _extraChargeExpiresAt = paymentResult.expiresAt;
          isCreatingRequest = false;
        });
        _startPaymentPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() => isCreatingRequest = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to initiate payment: $e")),
        );
      }
    }
  }

  void _startPaymentPolling() {
    _paymentPollTimer?.cancel();
    _paymentPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkExtraChargePaymentStatus();
    });
  }

  void _checkExtraChargePaymentStatus() async {
    if (_extraChargeTxnId == null || _isSubmittingUtr) return;

    try {
      final result = await context.api.payments.status(_extraChargeTxnId!);
      final status = result.status;

      if (status == "success") {
        _paymentPollTimer?.cancel();
        if (mounted) {
          setState(() => extraChargePaid = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Payment verified successfully!")),
          );
          // Now submit the request
          _submitAfterPayment();
        }
      }
    } catch (_) {
      // Silently ignore polling errors
    }
  }

  void _submitAfterPayment() async {
    setState(() => isLoading = true);

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Service Request Created Successfully")),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _openUpiApp() async {
    if (_extraChargeUpiUrl == null) return;

    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("UPI payment is only available on mobile devices")),
        );
      }
      return;
    }

    final uri = Uri.parse(_extraChargeUpiUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No UPI app found on device")),
        );
      }
    }
  }

  void _submitExtraChargeUtr() async {
    if (!_extraChargeFormKey.currentState!.validate()) return;
    if (_createdRequestId == null || _extraChargeTxnId == null) return;

    setState(() => _isSubmittingUtr = true);

    try {
      await context.api.payments.submitRequestUtr(
        requestId: _createdRequestId!,
        txnId: _extraChargeTxnId!,
        utrNumber: _extraChargeUtrController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("UTR submitted for verification")),
        );
      }

      _paymentPollTimer?.cancel();
      _startPaymentPolling();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to submit UTR: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingUtr = false);
    }
  }

  String _getExpiryText() {
    if (_extraChargeExpiresAt == null) return "";
    final diff = _extraChargeExpiresAt!.difference(DateTime.now());
    if (diff.isNegative) return "Expired";
    final mins = diff.inMinutes;
    final secs = diff.inSeconds % 60;
    return "${mins}m ${secs}s";
  }

  bool get _isExpired {
    if (_extraChargeExpiresAt == null) return false;
    return _extraChargeExpiresAt!.difference(DateTime.now()).isNegative;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Service Request")),
      body: SingleChildScrollView(
        padding: AppDimensions.pagePadding,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppDimensions.spacingMd),
              _buildRequestInfoCard(),
              const SizedBox(height: AppDimensions.spacingMd),
              _buildLocationCard(),
              const SizedBox(height: AppDimensions.spacingMd),
              _buildBranchCard(),
              // Show payment section if extra charge applies
              if (_showExtraChargePaymentSection) ...[
                const SizedBox(height: AppDimensions.spacingMd),
                _buildExtraChargePaymentCard(),
              ],
              const SizedBox(height: AppDimensions.spacingLg),
              // Show submit button only when no payment needed or payment is done
              if (!_showExtraChargePaymentSection || extraChargePaid)
                AppButton(
                  label: "Submit Request",
                  onPressed: createRequest,
                  isLoading: isLoading,
                  icon: Icons.send_outlined,
                ),
              if (_showExtraChargePaymentSection &&
                  !extraChargePaid &&
                  _createdRequestId == null)
                AppButton(
                  label: "Pay Extra Charge & Submit",
                  onPressed: createRequest,
                  isLoading: isCreatingRequest || isLoading,
                  icon: Icons.payment_outlined,
                ),
              const SizedBox(height: AppDimensions.spacingLg),
            ],
          ),
        ),
      ),
    );
  }

  bool get _showExtraChargePaymentSection {
    final result = distanceResult;
    return result != null && result.requiresPayment && !extraChargePaid;
  }

  Widget _buildRequestInfoCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent_outlined,
                  color: AppColors.primary, size: AppDimensions.iconSizeMd),
              const SizedBox(width: AppDimensions.spacingSm),
              Text("Request Information", style: AppTypography.cardTitle),
            ],
          ),
          const Divider(height: AppDimensions.spacingXl),
          DropdownButtonFormField<int>(
            value: selectedPolicyId,
            decoration: const InputDecoration(
              labelText: "Select Policy *",
              prefixIcon:
                  Icon(Icons.policy_outlined, color: AppColors.textHint),
            ),
            hint: const Text("Choose a policy"),
            items: policies.map<DropdownMenuItem<int>>((p) {
              return DropdownMenuItem(
                value: p.id,
                child: Text(
                  "${p.policyType} - ${p.providerName} (${p.policyNumber})",
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedPolicyId = val;
              });
            },
            validator: (value) {
              if (value == null) return "Please select a policy";
              return null;
            },
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          if (familyMembers.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              initialValue: selectedFamilyMemberId,
              decoration: const InputDecoration(
                labelText: 'Request for a family member (optional)',
                prefixIcon: Icon(
                  Icons.family_restroom,
                  color: AppColors.textHint,
                ),
              ),
              hint: const Text('Request for yourself'),
              items: familyMembers
                  .map(
                    (member) => DropdownMenuItem(
                      value: member.id,
                      child:
                          Text('${member.memberName} (${member.memberType})'),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => selectedFamilyMemberId = value),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
          ],
          AppInputField(
            label: "Request Type *",
            hint: "e.g. Claim, Renewal, Update",
            controller: typeController,
            prefixIcon:
                const Icon(Icons.category_outlined, color: AppColors.textHint),
            validator: (value) {
              if (value == null || value.isEmpty)
                return "Please enter request type";
              return null;
            },
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppInputField(
            label: "Description *",
            hint: "Describe your request in detail",
            controller: descriptionController,
            maxLines: 4,
            prefixIcon: const Icon(Icons.description_outlined,
                color: AppColors.textHint),
            validator: (value) {
              if (value == null || value.isEmpty)
                return "Please enter a description";
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  color: AppColors.primary, size: AppDimensions.iconSizeMd),
              const SizedBox(width: AppDimensions.spacingSm),
              Text("Your Location", style: AppTypography.cardTitle),
            ],
          ),
          const Divider(height: AppDimensions.spacingXl),
          AppInputField(
            label: "Enter your address *",
            hint: "e.g. 123 MG Road, Mumbai, Maharashtra",
            controller: addressController,
            maxLines: 2,
            prefixIcon:
                const Icon(Icons.search_outlined, color: AppColors.textHint),
            suffixIcon: geocodedLat != null
                ? const Icon(Icons.check_circle, color: AppColors.success)
                : null,
            validator: (value) {
              if (value == null || value.isEmpty)
                return "Please enter your address";
              return null;
            },
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppButton(
            label: "Get Location",
            onPressed: getLocation,
            isLoading: isGeocoding,
            icon: Icons.my_location_outlined,
          ),
          if (geocodedDisplayName != null) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            Container(
              padding: const EdgeInsets.all(AppDimensions.spacingMd),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                border: Border.all(color: AppColors.success, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle,
                      color: AppColors.success, size: AppDimensions.iconSizeSm),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Location Found",
                          style: AppTypography.label
                              .copyWith(color: AppColors.success),
                        ),
                        const SizedBox(height: AppDimensions.spacingXs),
                        Text(
                          geocodedDisplayName!,
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBranchCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store_outlined,
                  color: AppColors.primary, size: AppDimensions.iconSizeMd),
              const SizedBox(width: AppDimensions.spacingSm),
              Text("Select Branch", style: AppTypography.cardTitle),
            ],
          ),
          const Divider(height: AppDimensions.spacingXl),
          DropdownButtonFormField<int>(
            value: selectedBranchId,
            decoration: const InputDecoration(
              labelText: "Nearest Branch *",
              prefixIcon:
                  Icon(Icons.business_outlined, color: AppColors.textHint),
            ),
            hint: const Text("Select a branch"),
            items: branches.map<DropdownMenuItem<int>>((b) {
              return DropdownMenuItem(
                value: b.id,
                child: Text(b.name),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedBranchId = val;
                distanceResult = null;
              });
            },
            validator: (value) {
              if (value == null) return "Please select a branch";
              return null;
            },
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Column(
            children: [
              AppButton(
                label: "Check Distance",
                onPressed: checkDistance,
                isLoading: isDistanceLoading,
                icon: Icons.route_outlined,
              ),
              if (distanceError != null) ...[
                const SizedBox(height: AppDimensions.spacingSm),
                Container(
                  padding: const EdgeInsets.all(AppDimensions.spacingMd),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    border: Border.all(color: AppColors.error, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: AppDimensions.spacingSm),
                      Expanded(
                        child: Text(
                          distanceError!,
                          style: AppTypography.caption
                              .copyWith(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (distanceResult != null) ...[
                const SizedBox(height: AppDimensions.spacingMd),
                _buildDistanceQuoteCard(distanceResult!),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceQuoteCard(DistanceQuote quote) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Distance estimate", style: AppTypography.cardTitle),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
              "${Fmt.km(quote.distanceKm)} · ${Fmt.duration(quote.durationMinutes)}"),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            quote.message,
            style: AppTypography.body.copyWith(
              color:
                  quote.requiresPayment ? AppColors.warning : AppColors.success,
            ),
          ),
          if (quote.requiresPayment) ...[
            const Divider(height: AppDimensions.spacingLg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total extra charge"),
                Text(
                  Fmt.money(quote.totalAmount),
                  style: AppTypography.cardTitle,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExtraChargePaymentCard() {
    // Payment initiated - show QR code and UTR form
    if (_createdRequestId != null && _extraChargeTxnId != null) {
      return _buildPaymentActiveCard();
    }

    // Payment not yet initiated - show summary and Pay button
    final quote = distanceResult;
    if (quote == null) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment_outlined,
                  color: AppColors.warning, size: AppDimensions.iconSizeMd),
              const SizedBox(width: AppDimensions.spacingSm),
              Text("Extra Charge Payment", style: AppTypography.cardTitle),
            ],
          ),
          const Divider(height: AppDimensions.spacingXl),
          Container(
            padding: const EdgeInsets.all(AppDimensions.spacingMd),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              border: Border.all(color: AppColors.warning, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: AppDimensions.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.message,
                        style: AppTypography.body
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppDimensions.spacingXs),
                      Text(
                        "An extra charge of ${Fmt.money(quote.totalAmount)} "
                        "(${Fmt.km(quote.distanceKm)}) applies.",
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppButton(
            label: "Pay ${Fmt.money(quote.totalAmount)}",
            onPressed: _initiateExtraChargePayment,
            isLoading: isCreatingRequest,
            icon: Icons.payment_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentActiveCard() {
    return Column(
      children: [
        // Amount & expiry card
        AppCard(
          child: Column(
            children: [
              Text(
                "Extra Charge Payment",
                style: AppTypography.sectionTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                Fmt.money(distanceResult?.totalAmount),
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
                  color: _isExpired
                      ? AppColors.error.withOpacity(0.1)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Text(
                  "Expires in: ${_getExpiryText()}",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color:
                        _isExpired ? AppColors.error : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spacingLg),
        // QR code card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_2,
                      color: AppColors.primary, size: AppDimensions.iconSizeMd),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text("Scan QR to Pay", style: AppTypography.cardTitle),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              if (_extraChargeQrCodeBase64 != null)
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusMd),
                    ),
                    padding: const EdgeInsets.all(AppDimensions.spacingMd),
                    child: Image.memory(
                      base64Decode(_extraChargeQrCodeBase64!),
                      width: 220,
                      height: 220,
                    ),
                  ),
                ),
              const SizedBox(height: AppDimensions.spacingMd),
              AppButton(
                label: "Pay via UPI App",
                onPressed: _openUpiApp,
                icon: Icons.open_in_new,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spacingLg),
        // UTR submission card
        AppCard(
          child: Form(
            key: _extraChargeFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long,
                        color: AppColors.primary,
                        size: AppDimensions.iconSizeMd),
                    const SizedBox(width: AppDimensions.spacingSm),
                    Text("Manual Verification", style: AppTypography.cardTitle),
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
                  controller: _extraChargeUtrController,
                  prefixIcon:
                      const Icon(Icons.numbers, color: AppColors.textHint),
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
                  onPressed: _submitExtraChargeUtr,
                  isLoading: _isSubmittingUtr,
                  icon: Icons.verified,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimensions.spacingLg),
      ],
    );
  }
}
