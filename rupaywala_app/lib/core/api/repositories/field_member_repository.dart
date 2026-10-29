import '../api_client.dart';
import '../../models/json_utils.dart';
import '../../models/ops_models.dart';
import '../../models/service_models.dart';

/// Operational endpoints for field members.
class FieldMemberRepository {
  FieldMemberRepository(this._api);

  final ApiClient _api;

  Future<List<FieldMemberJob>> assignments(
      {List<String> statuses = const []}) async {
    final data = await _api.get(
      '/field-member/my-assignments',
      query: {if (statuses.isNotEmpty) 'status_filter': statuses.join(',')},
    );
    return J.asMapList(data).map(FieldMemberJob.fromJson).toList();
  }

  Future<FieldMemberJob> job(int requestId) async {
    final data = J.asMap(await _api.get('/field-member/request/$requestId'));
    return FieldMemberJob.fromJson(data);
  }

  Future<FieldMemberStats> stats() async {
    final data = J.asMap(await _api.get('/field-member/my-stats'));
    return FieldMemberStats.fromJson(data);
  }

  Future<FieldMemberProfile> profile() async {
    final data = J.asMap(await _api.get('/field-member/my-profile'));
    return FieldMemberProfile.fromJson(data);
  }

  /// Moves `assigned` -> `in_progress`.
  Future<void> start(int requestId) async {
    await _api
        .post('/field-member/start-request', query: {'request_id': requestId});
  }

  /// Moves `in_progress` -> `completed`, which is the only place a visit is
  /// actually consumed, so the notes are mandatory.
  Future<void> complete({
    required int requestId,
    required String completionNotes,
    String? proofPath,
    List<int>? proofBytes,
  }) async {
    if (proofPath == null && proofBytes == null) {
      await _api.post(
        '/field-member/update-status',
        body: {
          'request_id': requestId,
          'status': 'completed',
          'completion_notes': completionNotes
        },
      );
      return;
    }
    // The backend takes `request_id` as a query parameter and `completion_notes`
    // as a form field, so they must not both be sent in the multipart body.
    await _api.multipart(
      '/field-member/complete-request',
      query: {'request_id': requestId},
      fields: {'completion_notes': completionNotes},
      filePath: proofPath,
      fileBytes: proofBytes,
      fileName: proofPath?.split('/').last ?? 'proof.jpg',
    );
  }

  Future<void> setAvailability(bool available) async {
    await _api.post(
      '/field-member/availability',
      query: {'is_available': available},
    );
  }

  /// Convenience view of the raw customer-shaped request after a status
  /// change, used to refresh a cached list.
  Future<ServiceRequest?> requestSnapshot(int requestId) async {
    try {
      final data = J.asMap(await _api.get('/service/request/$requestId'));
      return ServiceRequest.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
