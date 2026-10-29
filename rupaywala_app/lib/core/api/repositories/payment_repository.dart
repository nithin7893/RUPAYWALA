import '../api_client.dart';
import '../../models/customer_models.dart';
import '../../models/json_utils.dart';

/// UPI payment intents and their verification lifecycle.
class PaymentRepository {
  PaymentRepository(this._api);

  final ApiClient _api;

  /// Creates (or reuses) a plan purchase intent.
  Future<PaymentIntent> createPlanPayment(int planId,
      {String? idempotencyKey}) {
    return _create({
      'plan_id': planId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey
    });
  }

  /// Creates (or reuses) the extra-distance-charge intent for a request.
  Future<PaymentIntent> createRequestPayment(int requestId,
      {String? idempotencyKey}) {
    return _create({
      'request_id': requestId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey
    });
  }

  Future<PaymentIntent> _create(Map<String, dynamic> body) async {
    final data = J.asMap(await _api.post('/payments/create', body: body));
    return PaymentIntent.fromJson(data);
  }

  /// Hands the UTR / reference number to an admin for manual verification.
  Future<void> submitUtr(
      {required String txnId, required String utrNumber}) async {
    await _api.post(
      '/payments/submit',
      body: {'txn_id': txnId, 'utr_number': utrNumber},
    );
  }

  /// The extra-charge flow uses its own endpoints with query parameters.
  Future<void> submitRequestUtr({
    required int requestId,
    required String txnId,
    required String utrNumber,
  }) async {
    await _api.post(
      '/service/request/$requestId/submit-extra-charge-utr',
      query: {'txn_id': txnId, 'utr_number': utrNumber},
    );
  }

  Future<PaymentIntent> status(String txnId) async {
    final data = J.asMap(await _api.get('/payments/status/$txnId'));
    return PaymentIntent.fromJson(data);
  }

  Future<List<PaymentRecord>> myPayments({int limit = 50}) async {
    final data =
        await _api.get('/payments/my-payments', query: {'limit': limit});
    return J.asMapList(data).map(PaymentRecord.fromJson).toList();
  }
}
