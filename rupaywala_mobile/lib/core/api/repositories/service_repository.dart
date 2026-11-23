import '../api_client.dart';
import '../../models/customer_models.dart';
import '../../models/json_utils.dart';
import '../../models/service_models.dart';

/// Services, branches, location search, distance pricing and service requests.
class ServiceRepository {
  ServiceRepository(this._api);

  final ApiClient _api;

  Future<List<ServiceType>> serviceTypes() async {
    final data = await _api.get('/service/service-types');
    return J.asMapList(data).map(ServiceType.fromJson).toList();
  }

  Future<List<Branch>> branches() async {
    final data = await _api.get('/service/branches');
    return J.asMapList(data).map(Branch.fromJson).toList();
  }

  /// Autosuggest for the location step. The backend expects `query` and
  /// returns an array of candidates.
  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final data = await _api.post('/service/geocode', body: {'query': query});
    return J.asMapList(data).map(PlaceSuggestion.fromJson).toList();
  }

  /// Branches sorted by road distance, each with its own charge preview.
  Future<List<BranchQuote>> nearestBranches({
    required double latitude,
    required double longitude,
  }) async {
    final data = await _api.post(
      '/service/nearest-branches',
      body: {'customer_latitude': latitude, 'customer_longitude': longitude},
    );
    return J.asMapList(data).map(BranchQuote.fromJson).toList();
  }

  /// Full quote for one branch, including tax and the payable total.
  Future<DistanceQuote> checkDistance({
    required double latitude,
    required double longitude,
    required int branchId,
  }) async {
    final data = J.asMap(
      await _api.post(
        '/service/check-distance',
        body: {
          'customer_latitude': latitude,
          'customer_longitude': longitude,
          'branch_id': branchId,
        },
      ),
    );
    return DistanceQuote.fromJson(data);
  }

  /// Creates a persisted, signed, single-use fixed quotation.
  Future<FixedQuote> createFixedQuote({
    required int policyId,
    required String requestType,
    int? serviceTypeId,
    required double latitude,
    required double longitude,
    required String address,
    String? placeId,
    required int branchId,
    int? familyMemberId,
  }) async {
    final body = <String, dynamic>{
      'policy_id': policyId,
      'request_type': requestType,
      'customer_latitude': latitude,
      'customer_longitude': longitude,
      'customer_address': address,
      'branch_id': branchId,
    };
    if (serviceTypeId != null) body['service_type_id'] = serviceTypeId;
    if (familyMemberId != null) body['family_member_id'] = familyMemberId;
    if (placeId != null && placeId.isNotEmpty) {
      body['customer_place_id'] = placeId;
    }
    final data = J.asMap(await _api.post('/service/quote', body: body));
    return FixedQuote.fromJson(data);
  }

  Future<ServiceRequest> createRequest({
    required int policyId,
    required String requestType,
    String? description,
    int? serviceTypeId,
    required double latitude,
    required double longitude,
    required String address,
    String? placeId,
    required int branchId,
    int? familyMemberId,
    String? quoteId,
  }) async {
    final body = <String, dynamic>{
      'policy_id': policyId,
      'request_type': requestType,
      'customer_latitude': latitude,
      'customer_longitude': longitude,
      'customer_address': address,
      'branch_id': branchId,
    };
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }
    if (serviceTypeId != null) body['service_type_id'] = serviceTypeId;
    if (familyMemberId != null) body['family_member_id'] = familyMemberId;
    if (placeId != null && placeId.isNotEmpty) {
      body['customer_place_id'] = placeId;
    }
    if (quoteId != null && quoteId.isNotEmpty) {
      body['quote_id'] = quoteId;
    }

    final data = J.asMap(await _api.post('/service/request', body: body));
    return ServiceRequest.fromJson(data);
  }

  Future<List<ServiceRequest>> myRequests(
      {List<String> statuses = const [], int limit = 100}) {
    return _list('/service/my-requests', {'limit': limit}, statuses);
  }

  Future<ServiceRequest> request(int requestId) async {
    final data = J.asMap(await _api.get('/service/request/$requestId'));
    return ServiceRequest.fromJson(data);
  }

  Future<ServiceRequest> cancelRequest(int requestId, {String? reason}) async {
    final data = J.asMap(
      await _api.post(
        '/service/request/$requestId/cancel',
        query: {
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim()
        },
      ),
    );
    return ServiceRequest.fromJson(data);
  }

  /// Creates the extra-charge UPI intent for an existing request.
  Future<PaymentIntent> createExtraChargePayment(int requestId) async {
    final data = J.asMap(
      await _api.post('/service/request/$requestId/pay-extra-charge'),
    );
    return PaymentIntent.fromJson(data);
  }

  Future<List<ServiceRequest>> _list(
    String path,
    Map<String, dynamic> query,
    List<String> statuses,
  ) async {
    final merged = <String, dynamic>{...query};
    if (statuses.isNotEmpty) merged['status_filter'] = statuses.join(',');
    final data = await _api.get(path, query: merged);
    return J.asMapList(data).map(ServiceRequest.fromJson).toList();
  }
}
