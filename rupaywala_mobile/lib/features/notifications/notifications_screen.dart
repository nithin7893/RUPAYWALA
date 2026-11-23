import 'package:flutter/material.dart';

import '../../core/models/auth_models.dart';
import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';
import '../admin/admin_request_detail_screen.dart';
import '../field_member/field_task_detail_screen.dart';
import '../service/request_detail_screen.dart';

/// Real notification feed for every role.
///
/// Counts come from `GET /notifications/unread-count`; nothing is fabricated.
/// Read / read-all / delete map directly to the repository methods.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.isTab = false,
    this.onChanged,
  });

  final bool isTab;

  /// Lets the shell refresh its unread badge after a change.
  final VoidCallback? onChanged;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = const [];
  int _unread = 0;
  bool _loading = true;
  bool _markingAll = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final feed = await context.api.notifications.feed();
      if (!mounted) return;
      setState(() {
        _items = feed.items;
        _unread = feed.unreadCount;
        _loading = false;
      });
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead) return;
    // Optimistic: the list is the source of truth for this session and a
    // failure simply reverts on the next refresh.
    setState(() {
      _items = [
        for (final item in _items)
          if (item.id == notification.id)
            AppNotification(
              id: item.id,
              title: item.title,
              message: item.message,
              category: item.category,
              referenceType: item.referenceType,
              referenceId: item.referenceId,
              isRead: true,
              createdAt: item.createdAt,
            )
          else
            item,
      ];
      _unread = (_unread - 1).clamp(0, 999);
    });
    widget.onChanged?.call();
    try {
      await context.api.notifications.markRead(notification.id);
    } catch (_) {
      // A stale badge is corrected by the next load.
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _unread == 0) return;
    setState(() => _markingAll = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.notifications.markAllRead();
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in _items)
            AppNotification(
              id: item.id,
              title: item.title,
              message: item.message,
              category: item.category,
              referenceType: item.referenceType,
              referenceId: item.referenceId,
              isRead: true,
              createdAt: item.createdAt,
            ),
        ];
        _unread = 0;
        _markingAll = false;
      });
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _markingAll = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not mark all as read: $error')),
      );
    }
  }

  Future<bool> _delete(AppNotification notification) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.api.notifications.delete(notification.id);
      if (!mounted) return false;
      setState(() {
        _items = _items.where((item) => item.id != notification.id).toList();
        if (!notification.isRead && _unread > 0) _unread -= 1;
      });
      widget.onChanged?.call();
      return true;
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete: $error')),
      );
      return false;
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      await _markRead(notification);
    }
    final referenceId = notification.referenceId;
    if (referenceId == null || !mounted) return;

    final role = context.session.role ?? AppRole.customer;
    final Widget destination = switch (role) {
      AppRole.admin => AdminRequestDetailScreen(requestId: referenceId),
      AppRole.fieldMember => FieldTaskDetailScreen(requestId: referenceId),
      AppRole.customer => RequestDetailScreen(requestId: referenceId),
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppPageHeader(
        title: 'Notifications',
        showBack: !widget.isTab,
        actions: [
          if (_unread > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: const Text('Mark all read'),
            ),
          AppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh notifications',
            onPressed: _loading ? () {} : _load,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(itemCount: 4)
          : _error != null
              ? ErrorStateView(
                  title: 'Notifications could not load',
                  message: _error!,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            EmptyState(
                              icon: Icons.notifications_none_rounded,
                              title: 'No notifications yet',
                              subtitle:
                                  'Updates about your requests, payments and account will appear here.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.xxxl,
                          ),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Dismissible(
                              key: ValueKey('notification-${item.id}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) => _delete(item),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.xl,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.errorSoft,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.error,
                                ),
                              ),
                              child: _NotificationTile(
                                notification: item,
                                onTap: () => _open(item),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color, background) = _style(notification.category);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: AppText.title.copyWith(
                          fontSize: 14,
                          fontWeight: notification.isRead
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!notification.isRead) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 5),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.message,
                  style: AppText.caption.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  Fmt.relative(notification.createdAt),
                  style: AppText.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, Color) _style(String category) {
    switch (category.toLowerCase()) {
      case 'payment':
        return (
          Icons.account_balance_wallet_outlined,
          AppColors.success,
          AppColors.successSoft,
        );
      case 'request':
        return (
          Icons.local_shipping_outlined,
          AppColors.info,
          AppColors.infoSoft,
        );
      case 'assignment':
        return (
          Icons.support_agent_outlined,
          AppColors.primary,
          AppColors.primarySoft,
        );
      case 'subscription':
        return (
          Icons.workspace_premium_outlined,
          AppColors.warning,
          AppColors.warningSoft,
        );
      default:
        return (
          Icons.notifications_none_rounded,
          AppColors.textSecondary,
          AppColors.neutralSoft,
        );
    }
  }
}
