import 'json_utils.dart';

/// Canonical request statuses, mirroring `RequestStatus` on the backend.
enum RequestStage {
  requested('requested', 'Submitted'),
  paymentPending('payment_pending', 'Payment Pending'),
  paymentComplete('payment_completed', 'Payment Complete'),
  waitingForAssignment('waiting_for_assignment', 'Waiting for Assignment'),
  assigned('assigned', 'Assigned'),
  inProgress('in_progress', 'In Progress'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const RequestStage(this.wire, this.label);

  final String wire;
  final String label;

  static RequestStage fromWire(String? value) {
    for (final stage in RequestStage.values) {
      if (stage.wire == value) return stage;
    }
    return RequestStage.requested;
  }
}

/// `GET /service/service-types`
class ServiceType {
  final int id;
  final String code;
  final String name;
  final String? description;

  const ServiceType({
    required this.id,
    required this.code,
    required this.name,
    this.description,
  });

  factory ServiceType.fromJson(Map<String, dynamic> json) {
    return ServiceType(
      id: J.integer(json['id']),
      code: J.text(json['code']),
      name: J.text(json['name']),
      description: J.str(json['description']),
    );
  }

  /// Maps the backend icon slug onto a Material icon so the app keeps one
  /// consistent icon family instead of raw slugs.
  String get iconKey => code;
}

/// `GET /service/branches` and `/admin/branches`
class Branch {
  final int id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? contactNumber;
  final String? city;
  final String? state;
  final bool isActive;

  const Branch({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.contactNumber,
    this.city,
    this.state,
    this.isActive = true,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: J.integer(json['id']),
      name: J.text(json['name']),
      address: J.text(json['address']),
      latitude: J.dbl(json['latitude']),
      longitude: J.dbl(json['longitude']),
      contactNumber: J.str(json['contact_number']),
      city: J.str(json['city']),
      state: J.str(json['state']),
      isActive: J.flag(json['is_active'], fallback: true),
    );
  }
}

/// One row of `POST /service/geocode`
class PlaceSuggestion {
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const PlaceSuggestion({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      placeId: J.text(json['place_id']),
      name: J.text(json['name']),
      address: J.text(json['address']),
      latitude: J.dbl(json['latitude']),
      longitude: J.dbl(json['longitude']),
    );
  }

  String get title => name.isEmpty ? address : name;
}

/// One row of `POST /service/nearest-branches`
class BranchQuote {
  final int id;
  final String name;
  final String address;
  final double distanceKm;
  final double durationMinutes;
  final double excessDistanceKm;
  final double extraCharge;
  final double taxAmount;
  final double totalAmount;
  final bool withinThreshold;

  const BranchQuote({
    required this.id,
    required this.name,
    required this.address,
    required this.distanceKm,
    required this.durationMinutes,
    required this.excessDistanceKm,
    required this.extraCharge,
    required this.taxAmount,
    required this.totalAmount,
    required this.withinThreshold,
  });

  factory BranchQuote.fromJson(Map<String, dynamic> json) {
    return BranchQuote(
      id: J.integer(json['id']),
      name: J.text(json['name']),
      address: J.text(json['address']),
      distanceKm: J.dbl(json['distance_km']),
      durationMinutes: J.dbl(json['duration_minutes']),
      excessDistanceKm: J.dbl(json['excess_distance_km']),
      extraCharge: J.dbl(json['extra_charge']),
      taxAmount: J.dbl(json['tax_amount']),
      totalAmount: J.dbl(json['total_amount']),
      withinThreshold: J.flag(json['within_threshold']),
    );
  }
}

/// `POST /service/check-distance`
class DistanceQuote {
  final int? branchId;
  final String? branchName;
  final double distanceKm;
  final double durationMinutes;
  final double thresholdKm;
  final double chargePerKm;
  final double roundTripFactor;
  final double excessDistanceKm;
  final double extraCharge;
  final double taxPercent;
  final double taxAmount;
  final double totalAmount;
  final bool withinThreshold;
  final bool requiresPayment;
  final String message;

  const DistanceQuote({
    this.branchId,
    this.branchName,
    required this.distanceKm,
    required this.durationMinutes,
    required this.thresholdKm,
    required this.chargePerKm,
    required this.roundTripFactor,
    required this.excessDistanceKm,
    required this.extraCharge,
    required this.taxPercent,
    required this.taxAmount,
    required this.totalAmount,
    required this.withinThreshold,
    required this.requiresPayment,
    required this.message,
  });

  factory DistanceQuote.fromJson(Map<String, dynamic> json) {
    return DistanceQuote(
      branchId: J.intOrNull(json['branch_id']),
      branchName: J.str(json['branch_name']),
      distanceKm: J.dbl(json['distance_km']),
      durationMinutes: J.dbl(json['duration_minutes']),
      thresholdKm: J.dbl(json['threshold_km']),
      chargePerKm: J.dbl(json['charge_per_km']),
      roundTripFactor: J.dbl(json['round_trip_factor'], 2),
      excessDistanceKm: J.dbl(json['excess_distance_km']),
      extraCharge: J.dbl(json['extra_charge']),
      taxPercent: J.dbl(json['tax_percent']),
      taxAmount: J.dbl(json['tax_amount']),
      totalAmount: J.dbl(json['total_amount']),
      withinThreshold: J.flag(json['within_threshold']),
      requiresPayment: J.flag(json['requires_payment']),
      message: J.text(json['message']),
    );
  }
}

/// The active assignment nested inside a service request.
class RequestAssignment {
  final int assignmentId;
  final int fieldMemberId;
  final String? fieldMemberName;
  final String? fieldMemberPhone;
  final String? employeeCode;
  final String status;
  final DateTime? assignedAt;

  const RequestAssignment({
    required this.assignmentId,
    required this.fieldMemberId,
    this.fieldMemberName,
    this.fieldMemberPhone,
    this.employeeCode,
    required this.status,
    this.assignedAt,
  });

  factory RequestAssignment.fromJson(Map<String, dynamic> json) {
    return RequestAssignment(
      assignmentId: J.integer(json['assignment_id']),
      fieldMemberId: J.integer(json['field_member_id']),
      fieldMemberName: J.str(json['field_member_name']),
      fieldMemberPhone: J.str(json['field_member_phone']),
      employeeCode: J.str(json['employee_code']),
      status: J.text(json['status'], 'active'),
      assignedAt: J.parse(json['assigned_at']),
    );
  }

  String get displayName {
    final name = fieldMemberName?.trim();
    return name == null || name.isEmpty ? 'Field member' : name;
  }
}

/// The latest extra-charge payment nested inside a service request.
class RequestPayment {
  final String txnId;
  final double amount;
  final String status;
  final String? utrNumber;
  final DateTime? createdAt;

  const RequestPayment({
    required this.txnId,
    required this.amount,
    required this.status,
    this.utrNumber,
    this.createdAt,
  });

  factory RequestPayment.fromJson(Map<String, dynamic> json) {
    return RequestPayment(
      txnId: J.text(json['txn_id']),
      amount: J.dbl(json['amount']),
      status: J.text(json['status'], 'pending'),
      utrNumber: J.str(json['utr_number']),
      createdAt: J.parse(json['created_at']),
    );
  }
}

/// `ServiceRequestResponse` — the shape returned by every request endpoint.
class ServiceRequest {
  final int id;
  final String reference;
  final int? policyId;
  final String? policyLabel;
  final int? serviceTypeId;
  final String requestType;
  final String? description;
  final double? customerLatitude;
  final double? customerLongitude;
  final String? customerAddress;
  final int? branchId;
  final String? branchName;
  final String? branchAddress;
  final double? distanceKm;
  final double? durationMinutes;
  final double thresholdKm;
  final double chargePerKm;
  final double excessDistanceKm;
  final double extraCharge;
  final double taxPercent;
  final double taxAmount;
  final double totalAmount;
  final bool chargePaid;
  final bool requiresPayment;
  final bool visitConsumed;
  final String status;
  final String statusLabel;
  final String? cancellationReason;
  final String? completionNotes;
  final RequestAssignment? assignment;
  final RequestPayment? payment;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  const ServiceRequest({
    required this.id,
    required this.reference,
    this.policyId,
    this.policyLabel,
    this.serviceTypeId,
    required this.requestType,
    this.description,
    this.customerLatitude,
    this.customerLongitude,
    this.customerAddress,
    this.branchId,
    this.branchName,
    this.branchAddress,
    this.distanceKm,
    this.durationMinutes,
    this.thresholdKm = 0,
    this.chargePerKm = 0,
    this.excessDistanceKm = 0,
    this.extraCharge = 0,
    this.taxPercent = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.chargePaid = true,
    this.requiresPayment = false,
    this.visitConsumed = false,
    required this.status,
    required this.statusLabel,
    this.cancellationReason,
    this.completionNotes,
    this.assignment,
    this.payment,
    this.assignedAt,
    this.startedAt,
    this.completedAt,
    this.createdAt,
  });

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    final rawStatus = J.text(json['status'], 'requested');
    final assignment = J.object(json['assignment']);
    final payment = J.object(json['payment']);
    return ServiceRequest(
      id: J.integer(json['id']),
      reference: J.text(json['reference'], '#${J.integer(json['id'])}'),
      policyId: J.intOrNull(json['policy_id']),
      policyLabel: J.str(json['policy_label']),
      serviceTypeId: J.intOrNull(json['service_type_id']),
      requestType: J.text(json['request_type']),
      description: J.str(json['description']),
      customerLatitude: json['customer_latitude'] == null
          ? null
          : J.dbl(json['customer_latitude']),
      customerLongitude: json['customer_longitude'] == null
          ? null
          : J.dbl(json['customer_longitude']),
      customerAddress: J.str(json['customer_address']),
      branchId: J.intOrNull(json['branch_id']),
      branchName: J.str(json['branch_name']),
      branchAddress: J.str(json['branch_address']),
      distanceKm:
          json['distance_km'] == null ? null : J.dbl(json['distance_km']),
      durationMinutes: json['duration_minutes'] == null
          ? null
          : J.dbl(json['duration_minutes']),
      thresholdKm: J.dbl(json['threshold_km']),
      chargePerKm: J.dbl(json['charge_per_km']),
      excessDistanceKm: J.dbl(json['excess_distance_km']),
      extraCharge: J.dbl(json['extra_charge']),
      taxPercent: J.dbl(json['tax_percent']),
      taxAmount: J.dbl(json['tax_amount']),
      totalAmount: J.dbl(json['total_amount']),
      chargePaid: J.flag(json['charge_paid'], fallback: true),
      requiresPayment: J.flag(json['requires_payment']),
      visitConsumed: J.flag(json['visit_consumed']),
      status: rawStatus,
      statusLabel:
          J.text(json['status_label'], RequestStage.fromWire(rawStatus).label),
      cancellationReason: J.str(json['cancellation_reason']),
      completionNotes: J.str(json['completion_notes']),
      assignment:
          assignment == null ? null : RequestAssignment.fromJson(assignment),
      payment: payment == null ? null : RequestPayment.fromJson(payment),
      assignedAt: J.parse(json['assigned_at']),
      startedAt: J.parse(json['started_at']),
      completedAt: J.parse(json['completed_at']),
      createdAt: J.parse(json['created_at']),
    );
  }

  RequestStage get stage => RequestStage.fromWire(status);

  bool get isCompleted => stage == RequestStage.completed;

  bool get isCancelled => stage == RequestStage.cancelled;

  /// Still moving: the customer can pay or cancel.
  bool get isOpen =>
      !isCompleted &&
      !isCancelled &&
      stage != RequestStage.inProgress &&
      stage != RequestStage.assigned;

  /// Work is with a field member.
  bool get isActive =>
      stage == RequestStage.assigned || stage == RequestStage.inProgress;

  bool get isAwaitingPayment => stage == RequestStage.paymentPending;

  /// Parses the list response returned by the collection endpoints.
  static List<ServiceRequest> listFrom(dynamic payload) {
    return J.asMapList(payload).map(ServiceRequest.fromJson).toList();
  }
}
