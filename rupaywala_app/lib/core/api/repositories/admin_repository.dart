import '../api_client.dart';
import '../../models/customer_models.dart';
import '../../models/json_utils.dart';
import '../../models/ops_models.dart';
import '../../models/service_models.dart';

/// Admin-only operational endpoints.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<AdminDashboardStats> dashboard() async {
    final data = J.asMap(await _api.get('/admin/dashboard'));
    return AdminDashboardStats.fromJson(data);
  }

  Future<List<ServiceRequest>> requests({
    List<String> statuses = const [],
    int? branchId,
    bool unassignedOnly = false,
    int limit = 200,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      if (unassignedOnly) 'unassigned_only': true,
      if (branchId != null) 'branch_id': branchId,
      if (statuses.isNotEmpty) 'status_filter': statuses.join(','),
    };
    final data = await _api.get('/admin/requests', query: query);
    return J.asMapList(data).map(ServiceRequest.fromJson).toList();
  }

  Future<ServiceRequest> cancelRequest(int requestId, {String? reason}) async {
    final data = J.asMap(
      await _api.post(
        '/admin/requests/$requestId/cancel',
        query: {
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim()
        },
      ),
    );
    return ServiceRequest.fromJson(data);
  }

  Future<void> assignFieldMember({
    required int requestId,
    required int fieldMemberId,
    String? notes,
  }) async {
    await _api.post(
      '/admin/assign-field-member',
      body: {
        'request_id': requestId,
        'field_member_id': fieldMemberId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
  }

  Future<void> unassignFieldMember(int requestId) async {
    await _api
        .post('/admin/unassign-field-member', query: {'request_id': requestId});
  }

  // -------------------------------------------------------------------
  // Field members
  // -------------------------------------------------------------------
  Future<List<ManagedFieldMember>> fieldMembers(
      {String? approvalStatus}) async {
    final data = await _api.get(
      '/admin/field-members',
      query: {if (approvalStatus != null) 'approval_status': approvalStatus},
    );
    return J.asMapList(data).map(ManagedFieldMember.fromJson).toList();
  }

  Future<ManagedFieldMember> createFieldMember({
    required String username,
    required String password,
    required String fullName,
    required String phoneNumber,
    String? employeeCode,
    String? region,
  }) async {
    final data = J.asMap(
      await _api.post(
        '/admin/field-members',
        body: {
          'username': username,
          'password': password,
          'full_name': fullName,
          'phone_number': phoneNumber,
          if (employeeCode != null && employeeCode.trim().isNotEmpty)
            'employee_code': employeeCode.trim(),
          if (region != null && region.trim().isNotEmpty)
            'region': region.trim(),
        },
      ),
    );
    return ManagedFieldMember.fromJson(data);
  }

  Future<void> deactivateFieldMember(int fieldMemberId) async {
    await _api.delete('/admin/field-members/$fieldMemberId');
  }

  Future<void> reviewFieldMember({
    required int fieldMemberId,
    required String action,
    String? reason,
    bool promoteRole = true,
  }) async {
    await _api.post(
      '/admin/field-members/$fieldMemberId/review',
      body: {
        'action': action,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        'promote_role': promoteRole,
      },
    );
  }

  Future<void> setFieldMemberAvailability(
      int fieldMemberId, bool available) async {
    await _api.post(
      '/admin/field-members/$fieldMemberId/availability',
      query: {'is_available': available},
    );
  }

  // -------------------------------------------------------------------
  // Users
  // -------------------------------------------------------------------
  Future<List<ManagedUser>> users(
      {String? role, String? search, int limit = 200}) async {
    final data = await _api.get(
      '/admin/users',
      query: {
        'limit': limit,
        if (role != null) 'role': role,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return J.asMapList(data).map(ManagedUser.fromJson).toList();
  }

  Future<void> setUserStatus(int userId,
      {required String action, String? reason}) async {
    await _api.post(
      '/admin/users/$userId/status',
      body: {
        'action': action,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()
      },
    );
  }

  Future<void> setUserRole(int userId, String role) async {
    await _api.post('/admin/users/$userId/role', query: {'role': role});
  }

  // -------------------------------------------------------------------
  // Payments
  // -------------------------------------------------------------------
  Future<Map<String, dynamic>> paymentSummary() async {
    final data = J.asMap(await _api.get('/admin/payments/summary'));
    return data;
  }

  Future<List<PaymentRecord>> payments({
    List<String> statuses = const [],
    String? paymentType,
    int limit = 200,
  }) async {
    final data = await _api.get(
      '/admin/payments/list',
      query: {
        'limit': limit,
        if (statuses.isNotEmpty) 'status_filter': statuses.join(','),
        if (paymentType != null) 'payment_type': paymentType,
      },
    );
    return J.asMapList(data).map(PaymentRecord.fromJson).toList();
  }

  Future<void> verifyPayment({
    required String txnId,
    required String action,
    String? note,
  }) async {
    await _api.post(
      '/admin/payments/verify',
      body: {
        'txn_id': txnId,
        'action': action,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  // -------------------------------------------------------------------
  // Configuration
  // -------------------------------------------------------------------
  Future<DistanceRateConfig> distanceRate() async {
    final data = J.asMap(await _api.get('/admin/distance-rate'));
    return DistanceRateConfig.fromJson(data);
  }

  Future<DistanceRateConfig> updateDistanceRate({
    required double thresholdKm,
    required double ratePerKm,
    required double taxPercent,
    required double roundTripFactor,
  }) async {
    final data = J.asMap(
      await _api.put(
        '/admin/distance-rate',
        body: {
          'threshold_km': thresholdKm,
          'rate_per_km': ratePerKm,
          'tax_percent': taxPercent,
          'round_trip_factor': roundTripFactor,
        },
      ),
    );
    return DistanceRateConfig.fromJson(data);
  }

  /// Includes inactive branches, unlike the customer endpoint.
  Future<List<Branch>> branches() async {
    final data = await _api.get('/admin/branches');
    return J.asMapList(data).map(Branch.fromJson).toList();
  }

  Future<void> addBranch({
    required String name,
    required String address,
    String? contactNumber,
    String? city,
    String? state,
    String? pincode,
    double? latitude,
    double? longitude,
  }) async {
    await _api.post(
      '/admin/branches/add',
      body: {
        'name': name,
        'address': address,
        if (contactNumber != null && contactNumber.isNotEmpty)
          'contact_number': contactNumber,
        if (city != null && city.isNotEmpty) 'city': city,
        if (state != null && state.isNotEmpty) 'state': state,
        if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    );
  }

  Future<void> updateBranch(
    int branchId, {
    String? name,
    String? address,
    String? contactNumber,
    bool? isActive,
  }) async {
    await _api.put(
      '/admin/branches/$branchId',
      body: {
        if (name != null) 'name': name,
        if (address != null) 'address': address,
        if (contactNumber != null) 'contact_number': contactNumber,
        if (isActive != null) 'is_active': isActive,
      },
    );
  }

  /// Soft deactivates; refuses while open requests still reference the branch.
  Future<void> deactivateBranch(int branchId) async {
    await _api.delete('/admin/branches/$branchId');
  }

  Future<List<ServiceType>> serviceTypes({bool includeInactive = true}) async {
    final data = await _api.get('/admin/service-types');
    final list = J.asMapList(data).map(ServiceType.fromJson).toList();
    return includeInactive ? list : list;
  }

  Future<void> toggleServiceType(int serviceTypeId) async {
    await _api.post('/admin/service-types/$serviceTypeId/toggle');
  }

  Future<void> createPlan({
    required String name,
    double price = 0,
    int visitsIncluded = 0,
    int validityDays = 365,
    String? description,
    List<String> features = const [],
  }) async {
    await _api.post(
      '/admin/plans',
      body: {
        'plan_name': name,
        'price': price,
        'visits_included': visitsIncluded,
        'validity_days': validityDays,
        if (description != null && description.isNotEmpty)
          'plan_description': description,
        'features': features,
      },
    );
  }

  Future<Map<String, dynamic>> runMaintenance() async {
    final data = J.asMap(await _api.post('/admin/maintenance/run'));
    return data;
  }
}
