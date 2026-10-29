import 'json_utils.dart';

/// `GET /profile/me`
class CustomerProfile {
  final int id;
  final String fullName;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? email;
  final String? phoneNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? policyNumber;
  final String? insuranceProvider;
  final String? policyType;
  final String? policyDetails;
  final DateTime? policyValidFrom;
  final DateTime? policyValidTill;
  final String? emergencyContactName;
  final String? emergencyContactNumber;
  final bool profileCompleted;

  const CustomerProfile({
    required this.id,
    required this.fullName,
    this.dateOfBirth,
    this.gender,
    this.email,
    this.phoneNumber,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.policyNumber,
    this.insuranceProvider,
    this.policyType,
    this.policyDetails,
    this.policyValidFrom,
    this.policyValidTill,
    this.emergencyContactName,
    this.emergencyContactNumber,
    this.profileCompleted = false,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    return CustomerProfile(
      id: J.integer(json['id']),
      fullName: J.text(json['full_name']),
      dateOfBirth: J.parse(json['date_of_birth']),
      gender: J.str(json['gender']),
      email: J.str(json['email']),
      phoneNumber: J.str(json['phone_number']),
      address: J.str(json['address']),
      city: J.str(json['city']),
      state: J.str(json['state']),
      pincode: J.str(json['pincode']),
      policyNumber: J.str(json['policy_number']),
      insuranceProvider: J.str(json['insurance_provider']),
      policyType: J.str(json['policy_type']),
      policyDetails: J.str(json['policy_details']),
      policyValidFrom: J.parse(json['policy_valid_from']),
      policyValidTill: J.parse(json['policy_valid_till']),
      emergencyContactName: J.str(json['emergency_contact_name']),
      emergencyContactNumber: J.str(json['emergency_contact_number']),
      profileCompleted: J.flag(json['profile_completed']),
    );
  }

  bool get exists => id > 0;

  int? get age {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years -= 1;
    }
    return years < 0 ? null : years;
  }

  String get fullAddress {
    final parts = [address, city, state, pincode]
        .whereType<String>()
        .where((p) => p.isNotEmpty);
    return parts.isEmpty ? '' : parts.join(', ');
  }
}

/// `GET /subscriptions/plans`
class SubscriptionPlan {
  final int id;
  final String? code;
  final String name;
  final String? description;
  final List<String> features;
  final double price;
  final int visitsIncluded;
  final int? additionalVisits;
  final double? includedVisitDistanceKm;
  final bool documentVerification;
  final bool onlineSubmission;
  final bool documentStorage;
  final int? storageDurationDays;
  final bool prioritySupport;
  final Map<String, bool> addonEligibility;
  final int? maxPolicies;
  final int? maxFamilyMembers;
  final int? maxAdultMembers;
  final int? maxChildMembers;
  final int validityDays;

  const SubscriptionPlan({
    required this.id,
    this.code,
    required this.name,
    this.description,
    this.features = const [],
    required this.price,
    required this.visitsIncluded,
    this.additionalVisits,
    this.includedVisitDistanceKm,
    this.documentVerification = false,
    this.onlineSubmission = false,
    this.documentStorage = false,
    this.storageDurationDays,
    this.prioritySupport = false,
    this.addonEligibility = const {},
    this.maxPolicies,
    this.maxFamilyMembers,
    this.maxAdultMembers,
    this.maxChildMembers,
    required this.validityDays,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: J.integer(json['id']),
      code: J.str(json['code']),
      name: J.text(json['plan_name']),
      description: J.str(json['plan_description']),
      features: J.stringList(json['features']),
      price: J.dbl(json['price']),
      visitsIncluded: J.integer(json['visits_included']),
      additionalVisits: J.intOrNull(json['additional_visits']),
      includedVisitDistanceKm:
          J.numeric(json['included_visit_distance_km'])?.toDouble(),
      documentVerification: J.flag(json['document_verification']),
      onlineSubmission: J.flag(json['online_submission']),
      documentStorage: J.flag(json['document_storage']),
      storageDurationDays: J.intOrNull(json['storage_duration_days']),
      prioritySupport: J.flag(json['priority_support']),
      addonEligibility: J.asMap(json['addon_eligibility']).map(
            (key, value) => MapEntry(key, J.flag(value)),
          ),
      maxPolicies: J.intOrNull(json['max_policies']),
      maxFamilyMembers: J.intOrNull(json['max_family_members']),
      maxAdultMembers: J.intOrNull(json['max_adult_members']),
      maxChildMembers: J.intOrNull(json['max_child_members']),
      validityDays: J.integer(json['validity_days'], 365),
    );
  }

  /// A plan list merges the benefits that have dedicated columns with the
  /// free-form `features` array so the card always shows something useful.
  List<String> get benefits {
    final result = <String>[];
    if (visitsIncluded > 0) result.add('$visitsIncluded doorstep visits');
    if (maxPolicies != null && maxPolicies! > 0) {
      result.add('Up to $maxPolicies policies');
    }
    if (maxFamilyMembers != null && maxFamilyMembers! > 0) {
      result.add('Up to $maxFamilyMembers family members');
    }
    result.addAll(features.where((f) => f.trim().isNotEmpty));
    return result;
  }

  String get validityLabel {
    if (validityDays % 365 == 0 && validityDays >= 365) {
      final years = validityDays ~/ 365;
      return '$years year${years == 1 ? '' : 's'}';
    }
    if (validityDays % 30 == 0 && validityDays >= 30) {
      final months = validityDays ~/ 30;
      return '$months month${months == 1 ? '' : 's'}';
    }
    return '$validityDays days';
  }
}

/// `GET /subscriptions/my-subscription` and `/my-subscriptions`
class CustomerSubscription {
  final int id;
  final int planId;
  final String? planName;
  final double? price;
  final Map<String, dynamic> entitlements;
  final String status;
  final int totalVisits;
  final int usedVisits;
  final int remainingVisits;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? daysRemaining;
  final int numberOfPolicies;
  final int numberOfPersons;

  const CustomerSubscription({
    required this.id,
    required this.planId,
    this.planName,
    this.price,
    this.entitlements = const {},
    required this.status,
    required this.totalVisits,
    required this.usedVisits,
    required this.remainingVisits,
    this.startDate,
    this.endDate,
    this.daysRemaining,
    this.numberOfPolicies = 0,
    this.numberOfPersons = 0,
  });

  factory CustomerSubscription.fromJson(Map<String, dynamic> json) {
    return CustomerSubscription(
      id: J.integer(json['id']),
      planId: J.integer(json['plan_id']),
      planName: J.str(json['plan_name']),
      price: json['price'] == null ? null : J.dbl(json['price']),
      entitlements: J.asMap(json['entitlements']),
      status: J.text(json['status'], 'active'),
      totalVisits: J.integer(json['total_visits']),
      usedVisits: J.integer(json['used_visits']),
      remainingVisits: J.integer(json['remaining_visits']),
      startDate: J.parse(json['start_date']),
      endDate: J.parse(json['end_date']),
      daysRemaining: J.intOrNull(json['days_remaining']),
      numberOfPolicies: J.integer(json['number_of_policies']),
      numberOfPersons: J.integer(json['number_of_persons']),
    );
  }

  bool get isActive => status == 'active';

  /// 0.0 - 1.0 progress of the visit allowance consumed.
  double get usedFraction {
    if (totalVisits <= 0) return 0;
    final ratio = usedVisits / totalVisits;
    return ratio.clamp(0.0, 1.0);
  }

  bool get isExpiringSoon {
    final days = daysRemaining;
    return isActive && days != null && days <= 7;
  }
}

/// `GET /subscriptions/visits/balance`
class VisitBalance {
  final bool hasActiveSubscription;
  final int? subscriptionId;
  final String? planName;
  final int totalVisits;
  final int usedVisits;
  final int remainingVisits;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final bool canRequestService;
  final String? reason;

  const VisitBalance({
    this.hasActiveSubscription = false,
    this.subscriptionId,
    this.planName,
    this.totalVisits = 0,
    this.usedVisits = 0,
    this.remainingVisits = 0,
    this.startDate,
    this.endDate,
    this.status = 'none',
    this.canRequestService = false,
    this.reason,
  });

  factory VisitBalance.fromJson(Map<String, dynamic> json) {
    return VisitBalance(
      hasActiveSubscription: J.flag(json['has_active_subscription']),
      subscriptionId: J.intOrNull(json['subscription_id']),
      planName: J.str(json['plan_name']),
      totalVisits: J.integer(json['total_visits']),
      usedVisits: J.integer(json['used_visits']),
      remainingVisits: J.integer(json['remaining_visits']),
      startDate: J.parse(json['start_date']),
      endDate: J.parse(json['end_date']),
      status: J.text(json['status'], 'none'),
      canRequestService: J.flag(json['can_request_service']),
      reason: J.str(json['reason']),
    );
  }
}

/// One row of `GET /subscriptions/visits/history`
class VisitLedgerEntry {
  final int id;
  final String type;
  final int quantity;
  final int? serviceRequestId;
  final String? note;
  final DateTime? createdAt;

  const VisitLedgerEntry({
    required this.id,
    required this.type,
    required this.quantity,
    this.serviceRequestId,
    this.note,
    this.createdAt,
  });

  factory VisitLedgerEntry.fromJson(Map<String, dynamic> json) {
    return VisitLedgerEntry(
      id: J.integer(json['id']),
      type: J.text(json['type'], 'allocated'),
      quantity: J.integer(json['quantity']),
      serviceRequestId: J.intOrNull(json['service_request_id']),
      note: J.str(json['note']),
      createdAt: J.parse(json['created_at']),
    );
  }

  bool get isAllocation => quantity > 0;

  String get label => switch (type) {
        'allocated' => 'Visits added',
        'consumed' => 'Visit used',
        'refunded' => 'Visit refunded',
        'expired' => 'Visits expired',
        _ => type,
      };
}

class SubscriptionFamilyMember {
  final int id;
  final String memberName;
  final String relationship;
  final String memberType;
  final DateTime? dateOfBirth;

  const SubscriptionFamilyMember({
    required this.id,
    required this.memberName,
    required this.relationship,
    required this.memberType,
    this.dateOfBirth,
  });

  factory SubscriptionFamilyMember.fromJson(Map<String, dynamic> json) {
    return SubscriptionFamilyMember(
      id: J.integer(json['id']),
      memberName: J.text(json['member_name']),
      relationship: J.text(json['relationship']),
      memberType: J.text(json['member_type']),
      dateOfBirth: J.parse(json['date_of_birth']),
    );
  }
}

/// `GET /policies/list`
class Policy {
  final int id;
  final String policyType;
  final String policyCategory;
  final String providerName;
  final String policyNumber;
  final double? coverageAmount;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final int? numberOfMembers;
  final List<Map<String, dynamic>> members;
  final bool isActive;
  final bool isValid;

  const Policy({
    required this.id,
    required this.policyType,
    required this.policyCategory,
    required this.providerName,
    required this.policyNumber,
    this.coverageAmount,
    this.startDate,
    this.expiryDate,
    this.numberOfMembers,
    this.members = const [],
    this.isActive = true,
    this.isValid = true,
  });

  factory Policy.fromJson(Map<String, dynamic> json) {
    return Policy(
      id: J.integer(json['id']),
      policyType: J.text(json['policy_type']),
      policyCategory: J.text(json['policy_category'], 'individual'),
      providerName: J.text(json['provider_name']),
      policyNumber: J.text(json['policy_number']),
      coverageAmount: json['coverage_amount'] == null
          ? null
          : J.dbl(json['coverage_amount']),
      startDate: J.parse(json['start_date']),
      expiryDate: J.parse(json['expiry_date']),
      numberOfMembers: J.intOrNull(json['number_of_members']),
      members: J.asMapList(json['members']),
      isActive: J.flag(json['is_active'], fallback: true),
      isValid: J.flag(json['is_valid'], fallback: true),
    );
  }

  String get title {
    final type = policyType.trim();
    return type.isEmpty ? providerName : type;
  }

  /// Days until expiry, negative once it has lapsed.
  int? get daysToExpiry {
    final expiry = expiryDate;
    if (expiry == null) return null;
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final target = DateTime(expiry.year, expiry.month, expiry.day);
    return target.difference(midnight).inDays;
  }
}

/// One row of `GET /payments/my-payments`
class PaymentRecord {
  final String txnId;
  final String paymentType;
  final double amount;
  final String status;
  final String? utrNumber;
  final String? planName;
  final int? relatedRequestId;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;
  final DateTime? createdAt;

  const PaymentRecord({
    required this.txnId,
    required this.paymentType,
    required this.amount,
    required this.status,
    this.utrNumber,
    this.planName,
    this.relatedRequestId,
    this.submittedAt,
    this.verifiedAt,
    this.createdAt,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRecord(
      txnId: J.text(json['txn_id']),
      paymentType: J.text(json['payment_type'], 'extra_charge'),
      amount: J.dbl(json['amount']),
      status: J.text(json['status'], 'pending'),
      utrNumber: J.str(json['utr_number']),
      planName: J.str(json['plan_name']),
      relatedRequestId: J.intOrNull(json['related_request_id']),
      submittedAt: J.parse(json['submitted_at']),
      verifiedAt: J.parse(json['verified_at']),
      createdAt: J.parse(json['created_at']),
    );
  }

  bool get isPlanPayment => paymentType == 'subscription';

  String get title {
    if (isPlanPayment) return planName == null ? 'Plan payment' : planName!;
    return 'Extra distance charge';
  }
}

/// A UPI intent returned by the payment creation endpoints.
class PaymentIntent {
  final String txnId;
  final String paymentType;
  final double amount;
  final double baseAmount;
  final double extraCharge;
  final double taxAmount;
  final String upiUrl;
  final String? qrCodeBase64;
  final String status;
  final int? planId;
  final String? planName;
  final int? requestId;
  final DateTime? expiresAt;

  const PaymentIntent({
    required this.txnId,
    required this.paymentType,
    required this.amount,
    required this.baseAmount,
    required this.extraCharge,
    required this.taxAmount,
    required this.upiUrl,
    this.qrCodeBase64,
    required this.status,
    this.planId,
    this.planName,
    this.requestId,
    this.expiresAt,
  });

  factory PaymentIntent.fromJson(Map<String, dynamic> json) {
    return PaymentIntent(
      txnId: J.text(json['txn_id']),
      paymentType: J.text(json['payment_type'], 'extra_charge'),
      amount: J.dbl(json['amount']),
      baseAmount: J.dbl(json['base_amount']),
      extraCharge: J.dbl(json['extra_charge']),
      taxAmount: J.dbl(json['tax_amount']),
      upiUrl: J.text(json['upi_url']),
      qrCodeBase64: J.str(json['qr_code']),
      status: J.text(json['status'], 'pending'),
      planId: J.intOrNull(json['plan_id']),
      planName: J.str(json['plan_name']),
      requestId: J.intOrNull(json['request_id']),
      expiresAt: J.parse(json['expires_at']),
    );
  }
}

/// Aggregate counters from `GET /subscriptions/payments/summary`.
class PaymentTotals {
  final double totalPaid;
  final int awaitingVerification;

  const PaymentTotals({
    this.totalPaid = 0,
    this.awaitingVerification = 0,
  });

  factory PaymentTotals.fromJson(Map<String, dynamic> json) {
    return PaymentTotals(
      totalPaid: J.dbl(json['total_paid']),
      awaitingVerification: J.integer(json['awaiting_verification']),
    );
  }
}
