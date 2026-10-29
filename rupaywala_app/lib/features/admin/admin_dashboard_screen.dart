import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/state/app_scope.dart';
import '../../widgets/widgets.dart';
import 'admin_requests_screen.dart';
import 'admin_field_members_screen.dart';
import 'admin_payments_screen.dart';
import 'admin_branches_screen.dart';
import 'admin_distance_rate_screen.dart';
import '../auth/phone_input_screen.dart';
import '../profile/account_profile_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        actions: [
          IconButton(
            tooltip: 'My profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccountProfileScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await context.session.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const PhoneInputScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppDimensions.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppDimensions.spacingMd),
            AppCard(
              padding: const EdgeInsets.all(AppDimensions.spacingLg),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.spacingSm),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusSm),
                    ),
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: AppDimensions.iconSizeLg,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Admin Panel",
                          style: AppTypography.sectionTitle,
                        ),
                        const SizedBox(height: AppDimensions.spacingXs),
                        Text(
                          "Manage requests and team members",
                          style: AppTypography.body,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Text(
              "Management",
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            DashboardCard(
              title: "Service Requests",
              subtitle: "View and assign requests to field members",
              icon: Icons.assignment_outlined,
              iconColor: AppColors.primary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminRequestsScreen()),
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            DashboardCard(
              title: "Field Members",
              subtitle: "View and manage your team",
              icon: Icons.people_outline,
              iconColor: AppColors.secondary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminFieldMembersScreen()),
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            DashboardCard(
              title: "Branch Management",
              subtitle: "Add, edit or delete branch locations",
              icon: Icons.store_outlined,
              iconColor: AppColors.info,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminBranchesScreen()),
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            DashboardCard(
              title: "Payment Verification",
              subtitle: "Approve or reject payment requests",
              icon: Icons.payment_outlined,
              iconColor: AppColors.warning,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminPaymentsScreen()),
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            DashboardCard(
              title: "Distance Rate",
              subtitle: "Manage rate per km for extra distance charges",
              icon: Icons.speed,
              iconColor: AppColors.info,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminDistanceRateScreen()),
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacingLg),
          ],
        ),
      ),
    );
  }
}
