import 'package:flutter/material.dart';

import '../../core/models/auth_models.dart';
import '../../core/state/app_scope.dart';
import '../../widgets/widgets.dart';
import '../admin/admin_dashboard_screen.dart';
import '../admin/admin_field_members_screen.dart';
import '../admin/admin_more_screen.dart';
import '../admin/admin_payments_screen.dart';
import '../admin/admin_requests_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../field_member/field_history_screen.dart';
import '../field_member/field_member_dashboard.dart';
import '../field_member/field_profile_screen.dart';
import '../notifications/notifications_screen.dart';
import '../policy/policy_list_screen.dart';
import '../profile/customer_profile_hub_screen.dart';
import '../service/my_requests_screen.dart';
import '../service/service_request_screen.dart';

/// Role-independent names for the destinations a screen may want to open.
///
/// Screens ask for a destination ("take me to my requests") rather than an
/// index, so the same call works for every role shell.
enum ShellTab {
  home,
  policies,
  request,
  requests,
  today,
  history,
  notifications,
  profile,
  overview,
  team,
  payments,
  more,
}

/// Lets a tab page move the persistent shell to another tab.
class RoleShellScope extends InheritedWidget {
  const RoleShellScope({
    super.key,
    required this.currentTab,
    required this.openTab,
    required this.refreshBadges,
    required super.child,
  });

  final ShellTab currentTab;
  final void Function(ShellTab tab) openTab;
  final VoidCallback refreshBadges;

  static RoleShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RoleShellScope>();
  }

  @override
  bool updateShouldNotify(RoleShellScope oldWidget) {
    return oldWidget.currentTab != currentTab;
  }
}

extension ShellNavigation on BuildContext {
  /// Returns `false` when the screen is rendered outside a role shell (for
  /// example in a widget test or a deep-linked detail route).
  bool openShellTab(ShellTab tab) {
    final shell = RoleShellScope.maybeOf(this);
    if (shell == null) return false;
    shell.openTab(tab);
    return true;
  }

  void refreshShellBadges() => RoleShellScope.maybeOf(this)?.refreshBadges();
}

/// The signed-in application shell.
///
/// One [Scaffold] owns the bottom bar; the role's pages live in an
/// [IndexedStack] so switching tabs never builds a second dashboard on top of
/// the first. A revisiting tab is rebuilt from a fresh key so real data (a new
/// request, a paid charge) is never hidden behind a stale cached list.
class RoleShell extends StatefulWidget {
  const RoleShell({super.key});

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int _index = 0;
  int _unread = 0;
  bool _badgeLoaded = false;
  final Set<int> _built = {0};
  final List<int> _revision = List<int>.filled(5, 0);

  AppRole get _role => context.session.role ?? AppRole.customer;

  List<AppNavItem> get _items {
    switch (_role) {
      case AppRole.customer:
        return const [
          AppNavItem(
            label: 'Home',
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
          ),
          AppNavItem(
            label: 'Policies',
            icon: Icons.shield_outlined,
            activeIcon: Icons.shield_rounded,
          ),
          AppNavItem(
            label: 'Request',
            icon: Icons.add_rounded,
            activeIcon: Icons.add_rounded,
            isPrimary: true,
          ),
          AppNavItem(
            label: 'Requests',
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long_rounded,
          ),
          AppNavItem(
            label: 'Profile',
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
          ),
        ];
      case AppRole.fieldMember:
        return [
          const AppNavItem(
            label: 'Today',
            icon: Icons.today_outlined,
            activeIcon: Icons.today_rounded,
          ),
          const AppNavItem(
            label: 'History',
            icon: Icons.history_rounded,
            activeIcon: Icons.history_rounded,
          ),
          AppNavItem(
            label: 'Notifications',
            icon: Icons.notifications_none_rounded,
            activeIcon: Icons.notifications_rounded,
            badgeCount: _unread,
          ),
          const AppNavItem(
            label: 'Profile',
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
          ),
        ];
      case AppRole.admin:
        return const [
          AppNavItem(
            label: 'Overview',
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard_rounded,
          ),
          AppNavItem(
            label: 'Requests',
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long_rounded,
          ),
          AppNavItem(
            label: 'Team',
            icon: Icons.groups_outlined,
            activeIcon: Icons.groups_rounded,
          ),
          AppNavItem(
            label: 'Payments',
            icon: Icons.account_balance_wallet_outlined,
            activeIcon: Icons.account_balance_wallet_rounded,
          ),
          AppNavItem(
            label: 'More',
            icon: Icons.more_horiz_rounded,
            activeIcon: Icons.more_horiz_rounded,
          ),
        ];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_badgeLoaded) return;
    _badgeLoaded = true;
    _refreshBadges();
  }

  Future<void> _refreshBadges() async {
    try {
      final count = await context.api.notifications.unreadCount();
      if (!mounted) return;
      setState(() => _unread = count);
    } catch (_) {
      // A badge is a convenience, never a blocker. A failed count simply
      // leaves the previous value in place.
    }
  }

  ShellTab _tabForIndex(int index) {
    final tabs = switch (_role) {
      AppRole.customer => const [
          ShellTab.home,
          ShellTab.policies,
          ShellTab.request,
          ShellTab.requests,
          ShellTab.profile,
        ],
      AppRole.fieldMember => const [
          ShellTab.today,
          ShellTab.history,
          ShellTab.notifications,
          ShellTab.profile,
        ],
      AppRole.admin => const [
          ShellTab.overview,
          ShellTab.requests,
          ShellTab.team,
          ShellTab.payments,
          ShellTab.more,
        ],
    };
    return tabs[index.clamp(0, tabs.length - 1)];
  }

  int _indexForTab(ShellTab tab) {
    final tabs = switch (_role) {
      AppRole.customer => const [
          ShellTab.home,
          ShellTab.policies,
          ShellTab.request,
          ShellTab.requests,
          ShellTab.profile,
        ],
      AppRole.fieldMember => const [
          ShellTab.today,
          ShellTab.history,
          ShellTab.notifications,
          ShellTab.profile,
        ],
      AppRole.admin => const [
          ShellTab.overview,
          ShellTab.requests,
          ShellTab.team,
          ShellTab.payments,
          ShellTab.more,
        ],
    };
    final index = tabs.indexOf(tab);
    return index < 0 ? 0 : index;
  }

  void _openTab(ShellTab tab) {
    final index = _indexForTab(tab);
    if (index == _index) return;
    setState(() {
      _index = index;
      _built.add(index);
      _revision[index] = _revision[index] + 1;
    });
    if (tab == ShellTab.notifications) _refreshBadges();
  }

  void _onNavTap(int index) {
    _openTab(_tabForIndex(index));
  }

  Widget _pageFor(int index) {
    if (!_built.contains(index)) return const SizedBox.shrink();

    final Widget page = switch (_role) {
      AppRole.customer => switch (index) {
          0 => const DashboardScreen(),
          1 => const PolicyListScreen(embedded: true),
          2 => ServiceRequestScreen(
              onCreated: (request) {
                _openTab(ShellTab.requests);
              },
            ),
          3 => const MyRequestsScreen(),
          _ => const CustomerProfileHubScreen(),
        },
      AppRole.fieldMember => switch (index) {
          0 => const FieldMemberDashboard(),
          1 => const FieldHistoryScreen(),
          2 => NotificationsScreen(
              isTab: true,
              onChanged: _refreshBadges,
            ),
          _ => const FieldProfileScreen(),
        },
      AppRole.admin => switch (index) {
          0 => const AdminDashboardScreen(),
          1 => const AdminRequestsScreen(),
          2 => const AdminFieldMembersScreen(),
          3 => const AdminPaymentsScreen(),
          _ => const AdminMoreScreen(),
        },
    };

    return KeyedSubtree(
      key: ValueKey('${_role.wireName}-$index-${_revision[index]}'),
      child: page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final tab = _tabForIndex(_index);

    return RoleShellScope(
      currentTab: tab,
      openTab: _openTab,
      refreshBadges: _refreshBadges,
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: List.generate(items.length, _pageFor),
        ),
        bottomNavigationBar: AppBottomNavBar(
          items: items,
          currentIndex: _index,
          onTap: _onNavTap,
        ),
      ),
    );
  }
}
