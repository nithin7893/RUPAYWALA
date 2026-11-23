import '../api_client.dart';
import '../api_exception.dart';
import '../../models/customer_models.dart';
import '../../models/json_utils.dart';

/// Plans, the current subscription, and the visit ledger.
class SubscriptionRepository {
  SubscriptionRepository(this._api);

  final ApiClient _api;

  Future<List<SubscriptionPlan>> plans() async {
    final data = await _api.get('/subscriptions/plans');
    return J.asMapList(data).map(SubscriptionPlan.fromJson).toList();
  }

  /// Throws an [ApiException] with the backend message when there is no
  /// subscription, which the caller renders as an empty state.
  Future<CustomerSubscription?> currentSubscription() async {
    try {
      final data = J.asMap(await _api.get('/subscriptions/my-subscription'));
      return CustomerSubscription.fromJson(data);
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<List<CustomerSubscription>> allSubscriptions() async {
    final data = await _api.get('/subscriptions/my-subscriptions');
    return J.asMapList(data).map(CustomerSubscription.fromJson).toList();
  }

  Future<VisitBalance> visitBalance() async {
    final data = J.asMap(await _api.get('/subscriptions/visits/balance'));
    return VisitBalance.fromJson(data);
  }

  Future<List<VisitLedgerEntry>> visitHistory({int limit = 50}) async {
    final data = await _api
        .get('/subscriptions/visits/history', query: {'limit': limit});
    return J.asMapList(data).map(VisitLedgerEntry.fromJson).toList();
  }

  Future<List<SubscriptionFamilyMember>> familyMembers() async {
    final data = await _api.get('/subscriptions/family-members');
    return J.asMapList(data).map(SubscriptionFamilyMember.fromJson).toList();
  }

  Future<SubscriptionFamilyMember> addFamilyMember({
    required String memberName,
    required String relationship,
    required String memberType,
    DateTime? dateOfBirth,
  }) async {
    final data = await _api.post(
      '/subscriptions/family-members',
      body: {
        'member_name': memberName,
        'relationship': relationship,
        'member_type': memberType,
        if (dateOfBirth != null)
          'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      },
    );
    return SubscriptionFamilyMember.fromJson(J.asMap(data));
  }

  Future<void> removeFamilyMember(int memberId) async {
    await _api.delete('/subscriptions/family-members/$memberId');
  }

  Future<PaymentTotals> paymentSummary() async {
    final data = J.asMap(await _api.get('/subscriptions/payments/summary'));
    return PaymentTotals.fromJson(data);
  }
}
