import 'package:flutter/material.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../policy/policy_list_screen.dart';
import '../policy/add_policy_screen.dart';
import '../service/service_request_screen.dart';
import '../service/my_requests_screen.dart';
import '../subscription/subscription_screen.dart';
import '../auth/phone_input_screen.dart';
import '../profile/account_profile_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
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
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("No new notifications")),
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
            const SizedBox(height: AppDimensions.spacingSm),
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
                      Icons.account_balance_wallet,
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
                          "Welcome to Rupaywala",
                          style: AppTypography.sectionTitle,
                        ),
                        const SizedBox(height: AppDimensions.spacingXs),
                        Text(
                          "Manage your policies & services",
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
              "Quick Actions",
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: AppDimensions.spacingMd,
              mainAxisSpacing: AppDimensions.spacingMd,
              childAspectRatio: 1.1,
              children: [
                DashboardCard(
                  title: "Add Policy",
                  subtitle: "Add a new insurance policy",
                  icon: Icons.add_circle_outline,
                  iconColor: AppColors.secondary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AddPolicyScreen()),
                    );
                  },
                ),
                DashboardCard(
                  title: "My Policies",
                  subtitle: "View all your policies",
                  icon: Icons.policy_outlined,
                  iconColor: AppColors.primary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PolicyListScreen()),
                    );
                  },
                ),
                DashboardCard(
                  title: "Request Service",
                  subtitle: "Get help with your policy",
                  icon: Icons.support_agent_outlined,
                  iconColor: AppColors.info,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServiceRequestScreen(),
                      ),
                    );
                  },
                ),
                DashboardCard(
                  title: "My Requests",
                  subtitle: "Track your service requests",
                  icon: Icons.assignment_outlined,
                  iconColor: AppColors.warning,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyRequestsScreen()),
                    );
                  },
                ),
                DashboardCard(
                  title: "Subscriptions",
                  subtitle: "View plans and manage your membership",
                  icon: Icons.card_membership_outlined,
                  iconColor: AppColors.secondary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingLg),
          ],
        ),
      ),
    );
  }
}
