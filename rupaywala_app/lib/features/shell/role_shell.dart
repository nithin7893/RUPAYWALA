import 'package:flutter/material.dart';

import '../../core/models/auth_models.dart';
import '../../core/state/app_scope.dart';
import '../admin/admin_dashboard_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../field_member/field_member_dashboard.dart';

class RoleShell extends StatelessWidget {
  const RoleShell({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (context.session.role) {
      AppRole.customer => const DashboardScreen(),
      AppRole.fieldMember => const FieldMemberDashboard(),
      AppRole.admin => const AdminDashboardScreen(),
      null => const SizedBox.shrink(),
    };
  }
}
