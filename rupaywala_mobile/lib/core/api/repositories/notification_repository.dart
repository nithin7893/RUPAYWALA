import '../api_client.dart';
import '../../models/json_utils.dart';
import '../../models/ops_models.dart';

/// Notification feed, available to every role.
class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  Future<NotificationFeed> feed({int limit = 50}) async {
    final data =
        J.asMap(await _api.get('/notifications', query: {'limit': limit}));
    return NotificationFeed.fromJson(data);
  }

  Future<int> unreadCount() async {
    final data = J.asMap(await _api.get('/notifications/unread-count'));
    return J.integer(data['unread_count']);
  }

  Future<void> markRead(int notificationId) async {
    await _api.put('/notifications/$notificationId/read');
  }

  Future<void> markAllRead() async {
    await _api.put('/notifications/mark-all-read');
  }

  Future<void> delete(int notificationId) async {
    await _api.delete('/notifications/$notificationId');
  }
}
