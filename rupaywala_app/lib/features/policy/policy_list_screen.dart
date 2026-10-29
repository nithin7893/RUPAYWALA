import 'package:flutter/material.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/utils/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'add_policy_screen.dart';

class PolicyListScreen extends StatefulWidget {
  const PolicyListScreen({super.key});

  @override
  State<PolicyListScreen> createState() => _PolicyListScreenState();
}

class _PolicyListScreenState extends State<PolicyListScreen> {
  List<Policy> policies = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadPolicies();
  }

  void loadPolicies() async {
    try {
      final result = await context.api.customer.policies();

      if (!mounted) return;
      setState(() {
        policies = result;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load policies: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Policies"),
      ),
      body: isLoading
          ? const AppLoading(message: "Loading policies...")
          : policies.isEmpty
              ? EmptyState(
                  icon: Icons.policy_outlined,
                  title: "No Policies Found",
                  subtitle: "Add your first insurance policy to get started",
                  actionLabel: "Add Policy",
                  onAction: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AddPolicyScreen()),
                    );
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spacingSm),
                  itemCount: policies.length,
                  itemBuilder: (context, index) {
                    final p = policies[index];
                    final isFloater = p.policyCategory == "floater";
                    final members = p.members;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacingMd,
                        vertical: AppDimensions.spacingXs,
                      ),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(
                                      AppDimensions.spacingSm),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusSm),
                                  ),
                                  child: Icon(
                                    isFloater
                                        ? Icons.people_outlined
                                        : Icons.person_outlined,
                                    color: AppColors.primary,
                                    size: AppDimensions.iconSizeMd,
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.spacingMd),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.title.isEmpty
                                            ? "Unknown Type"
                                            : p.title,
                                        style: AppTypography.cardTitle,
                                      ),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isFloater
                                              ? AppColors.secondary
                                                  .withOpacity(0.1)
                                              : AppColors.info.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                              AppDimensions.radiusFull),
                                        ),
                                        child: Text(
                                          isFloater ? "Floater" : "Individual",
                                          style: AppTypography.caption.copyWith(
                                            color: isFloater
                                                ? AppColors.secondaryDark
                                                : AppColors.info,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),
                            const Divider(),
                            const SizedBox(height: AppDimensions.spacingSm),
                            _buildInfoRow(Icons.business_outlined, "Provider",
                                p.providerName),
                            const SizedBox(height: AppDimensions.spacingSm),
                            _buildInfoRow(
                                Icons.numbers, "Policy No.", p.policyNumber),
                            if (p.coverageAmount != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              _buildInfoRow(Icons.currency_rupee, "Coverage",
                                  "₹${Fmt.money(p.coverageAmount)}"),
                            ],
                            if (p.expiryDate != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              _buildInfoRow(Icons.event_outlined, "Expiry",
                                  Fmt.date(p.expiryDate)),
                            ],
                            if (isFloater && members.isNotEmpty) ...[
                              const SizedBox(height: AppDimensions.spacingMd),
                              const Divider(),
                              const SizedBox(height: AppDimensions.spacingSm),
                              Row(
                                children: [
                                  Icon(Icons.group_outlined,
                                      size: AppDimensions.iconSizeSm,
                                      color: AppColors.textHint),
                                  const SizedBox(
                                      width: AppDimensions.spacingSm),
                                  Text(
                                    "Covered Members (${members.length})",
                                    style: AppTypography.caption
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppDimensions.spacingSm),
                              ...members.map<Widget>((m) {
                                return Container(
                                  margin: const EdgeInsets.only(
                                      bottom: AppDimensions.spacingXs),
                                  padding: const EdgeInsets.all(
                                      AppDimensions.spacingSm),
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusSm),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: AppColors.secondary
                                            .withOpacity(0.1),
                                        child: Text(
                                          (m["member_name"] ?? "?")[0]
                                              .toString()
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.secondaryDark,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                          width: AppDimensions.spacingSm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              m["member_name"] ?? "",
                                              style: AppTypography.body
                                                  .copyWith(fontSize: 13),
                                            ),
                                            Text(
                                              "${m["relationship"]} | Age: ${m["age"]}",
                                              style: AppTypography.caption
                                                  .copyWith(fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (m["phone_number"] != null &&
                                          (m["phone_number"] as String)
                                              .isNotEmpty)
                                        Icon(Icons.phone_outlined,
                                            size: 14,
                                            color: AppColors.textHint),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value) {
    return Row(
      children: [
        Icon(icon, size: AppDimensions.iconSizeSm, color: AppColors.textHint),
        const SizedBox(width: AppDimensions.spacingSm),
        Text("$label:", style: AppTypography.body),
        const SizedBox(width: AppDimensions.spacingSm),
        Expanded(
          child: Text(
            value ?? "N/A",
            style: AppTypography.body,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
