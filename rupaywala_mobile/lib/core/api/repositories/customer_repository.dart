import '../api_client.dart';
import '../../models/customer_models.dart';
import '../../models/json_utils.dart';

/// Profile and policy endpoints, both scoped to the signed-in customer.
class CustomerRepository {
  CustomerRepository(this._api);

  final ApiClient _api;

  Future<CustomerProfile> profile() async {
    final data = J.asMap(await _api.get('/profile/me'));
    return CustomerProfile.fromJson(data);
  }

  /// Upsert — the backend creates the profile when it is missing, so the same
  /// call backs both "create" and "edit".
  Future<CustomerProfile> saveProfile({
    required String fullName,
    String? dateOfBirth,
    String? gender,
    String? email,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? policyNumber,
    String? insuranceProvider,
    String? policyType,
    String? policyDetails,
    String? policyValidFrom,
    String? policyValidTill,
    String? emergencyContactName,
    String? emergencyContactNumber,
  }) async {
    final body = <String, dynamic>{'full_name': fullName};
    void put(String key, String? value) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty) body[key] = text;
    }

    put('date_of_birth', dateOfBirth);
    put('gender', gender);
    put('email', email);
    put('address', address);
    put('city', city);
    put('state', state);
    put('pincode', pincode);
    put('policy_number', policyNumber);
    put('insurance_provider', insuranceProvider);
    put('policy_type', policyType);
    put('policy_details', policyDetails);
    put('policy_valid_from', policyValidFrom);
    put('policy_valid_till', policyValidTill);
    put('emergency_contact_name', emergencyContactName);
    put('emergency_contact_number', emergencyContactNumber);

    final data = J.asMap(await _api.put('/profile/update', body: body));
    return CustomerProfile.fromJson(data);
  }

  Future<List<Policy>> policies() async {
    final data = await _api.get('/policies/list');
    return J.asMapList(data).map(Policy.fromJson).toList();
  }

  Future<Policy> addPolicy({
    required String policyType,
    required String providerName,
    required String policyNumber,
    String policyCategory = 'individual',
    double? coverageAmount,
    String? startDate,
    String? expiryDate,
    int? numberOfMembers,
    List<Map<String, dynamic>>? members,
  }) async {
    final body = <String, dynamic>{
      'policy_type': policyType,
      'provider_name': providerName,
      'policy_number': policyNumber,
      'policy_category': policyCategory,
    };
    if (coverageAmount != null && coverageAmount > 0) {
      body['coverage_amount'] = coverageAmount;
    }
    if (startDate != null && startDate.isNotEmpty) {
      body['start_date'] = startDate;
    }
    if (expiryDate != null && expiryDate.isNotEmpty) {
      body['expiry_date'] = expiryDate;
    }
    if (numberOfMembers != null && numberOfMembers > 0) {
      body['number_of_members'] = numberOfMembers;
    }
    if (members != null && members.isNotEmpty) {
      body['members'] = members;
    }

    await _api.post('/policies/add', body: body);
    return policies().then((all) => all.firstWhere(
          (p) =>
              p.policyNumber.toUpperCase() == policyNumber.trim().toUpperCase(),
          orElse: () => Policy(
            id: 0,
            policyType: policyType,
            policyCategory: policyCategory,
            providerName: providerName,
            policyNumber: policyNumber,
          ),
        ));
  }

  Future<void> deletePolicy(int policyId) async {
    await _api.delete('/policies/delete/$policyId');
  }
}
