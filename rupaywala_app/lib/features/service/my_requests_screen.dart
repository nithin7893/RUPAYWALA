import 'package:flutter/material.dart';
import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/widgets.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<ServiceRequest> requests = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadRequests();
  }

  void loadRequests() async {
    try {
      final result = await context.api.service.myRequests();

      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Requests"),
      ),
      body: isLoading
          ? const AppLoading(message: "Loading requests...")
          : requests.isEmpty
              ? const EmptyState(
                  icon: Icons.assignment_outlined,
                  title: "No Requests Found",
                  subtitle: "You haven't created any service requests yet",
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spacingSm),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
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
                                    request.requestType,
                                    style: AppTypography.cardTitle,
                                  ),
                                ),
                                StatusChip(label: request.statusLabel),
                              ],
                            ),
                            if (request.description != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Text(
                                request.description!,
                                style: AppTypography.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (request.customerAddress != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      size: AppDimensions.iconSizeSm,
                                      color: AppColors.textHint),
                                  const SizedBox(
                                      width: AppDimensions.spacingXs),
                                  Expanded(
                                    child: Text(
                                      request.customerAddress!,
                                      style: AppTypography.caption,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (request.distanceKm != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Row(
                                children: [
                                  Icon(Icons.route_outlined,
                                      size: AppDimensions.iconSizeSm,
                                      color: AppColors.textHint),
                                  const SizedBox(
                                      width: AppDimensions.spacingXs),
                                  Text(
                                    "Distance: ${Fmt.km(request.distanceKm)}",
                                    style: AppTypography.caption,
                                  ),
                                  if (request.extraCharge > 0) ...[
                                    const SizedBox(
                                        width: AppDimensions.spacingSm),
                                    Text(
                                      "Extra: ${Fmt.money(request.extraCharge)}",
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            if (request.branchId != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Row(
                                children: [
                                  Icon(Icons.store_outlined,
                                      size: AppDimensions.iconSizeSm,
                                      color: AppColors.textHint),
                                  const SizedBox(
                                      width: AppDimensions.spacingXs),
                                  Text(
                                    "Branch: ${request.branchName ?? request.branchId}",
                                    style: AppTypography.caption,
                                  ),
                                ],
                              ),
                            ],
                            if (request.createdAt != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Row(
                                children: [
                                  Icon(Icons.access_time,
                                      size: AppDimensions.iconSizeSm,
                                      color: AppColors.textHint),
                                  const SizedBox(
                                      width: AppDimensions.spacingXs),
                                  Text(
                                    Fmt.dateTime(request.createdAt),
                                    style: AppTypography.caption,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
