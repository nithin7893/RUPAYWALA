import 'package:flutter/material.dart';
import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen> {
  List<ServiceRequest> requests = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadRequests();
  }

  Future<void> loadRequests() async {
    try {
      final result = await context.api.admin.requests();

      if (mounted)
        setState(() {
          requests = result;
          isLoading = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load requests: $e")),
        );
      }
    }
  }

  void assignDialog(int requestId) {
    final fieldController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Assign Field Member"),
          content: AppInputField(
            label: "Field Member ID",
            hint: "Enter member ID",
            controller: fieldController,
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (fieldController.text.isEmpty) return;

                try {
                  await context.api.admin.assignFieldMember(
                    requestId: requestId,
                    fieldMemberId: int.parse(fieldController.text),
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    loadRequests();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Field member assigned successfully")),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to assign: $e")),
                    );
                  }
                }
              },
              child: const Text("Assign"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Service Requests"),
      ),
      body: isLoading
          ? const AppLoading(message: "Loading requests...")
          : requests.isEmpty
              ? const EmptyState(
                  icon: Icons.assignment_outlined,
                  title: "No Requests Found",
                  subtitle: "There are no service requests to manage",
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spacingSm),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final r = requests[index];
                    final extraCharge = r.extraCharge;
                    final chargePaid = r.chargePaid;
                    final status = r.statusLabel;
                    final distanceKm = r.distanceKm;
                    final canAssign =
                        chargePaid && r.status != "charge_pending";

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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    r.requestType,
                                    style: AppTypography.cardTitle,
                                  ),
                                ),
                                StatusChip(label: status),
                              ],
                            ),
                            if (r.description != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Text(
                                r.description!,
                                style: AppTypography.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            // Distance & extra charge info
                            if (extraCharge > 0 || distanceKm != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Container(
                                padding: const EdgeInsets.all(
                                    AppDimensions.spacingSm),
                                decoration: BoxDecoration(
                                  color: chargePaid
                                      ? AppColors.success.withOpacity(0.1)
                                      : AppColors.warning.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusSm),
                                  border: Border.all(
                                    color: chargePaid
                                        ? AppColors.success
                                        : AppColors.warning,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      chargePaid
                                          ? Icons.check_circle
                                          : Icons.payment,
                                      color: chargePaid
                                          ? AppColors.success
                                          : AppColors.warning,
                                      size: 18,
                                    ),
                                    const SizedBox(
                                        width: AppDimensions.spacingSm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (distanceKm != null)
                                            Text(
                                              "Distance: ${distanceKm.toStringAsFixed(1)} km",
                                              style: AppTypography.caption
                                                  .copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          if (extraCharge > 0)
                                            Text(
                                              "Extra Charge: ₹${extraCharge.toStringAsFixed(0)}",
                                              style: AppTypography.caption
                                                  .copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppDimensions.spacingSm,
                                        vertical: AppDimensions.spacingXs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: chargePaid
                                            ? AppColors.success
                                            : AppColors.error,
                                        borderRadius: BorderRadius.circular(
                                            AppDimensions.radiusFull),
                                      ),
                                      child: Text(
                                        chargePaid ? "Paid" : "Unpaid",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: AppDimensions.spacingMd),
                            const Divider(),
                            const SizedBox(height: AppDimensions.spacingSm),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "Request ID: ${r.id}",
                                    style: AppTypography.caption,
                                  ),
                                ),
                                SizedBox(
                                  width: 140,
                                  child: AppButton(
                                    label:
                                        canAssign ? "Assign" : "Await Payment",
                                    onPressed: canAssign
                                        ? () => assignDialog(r.id)
                                        : null,
                                    variant: AppButtonVariant.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
