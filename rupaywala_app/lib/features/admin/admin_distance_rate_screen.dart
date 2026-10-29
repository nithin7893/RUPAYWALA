import 'package:flutter/material.dart';
import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class AdminDistanceRateScreen extends StatefulWidget {
  const AdminDistanceRateScreen({super.key});

  @override
  State<AdminDistanceRateScreen> createState() =>
      _AdminDistanceRateScreenState();
}

class _AdminDistanceRateScreenState extends State<AdminDistanceRateScreen> {
  final rateController = TextEditingController();
  bool isLoading = true;
  bool isSaving = false;
  DistanceRateConfig? _config;
  double? currentRate;
  String? _loadError;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    loadRate();
  }

  @override
  void dispose() {
    rateController.dispose();
    super.dispose();
  }

  Future<void> loadRate() async {
    final api = context.api;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      isLoading = true;
      _loadError = null;
    });
    try {
      final result = await api.admin.distanceRate();
      if (!mounted) return;
      setState(() {
        _config = result;
        currentRate = result.ratePerKm;
        rateController.text = currentRate!.toStringAsFixed(2);
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          isLoading = false;
        });
        messenger.showSnackBar(
          SnackBar(content: Text("Failed to load rate: $e")),
        );
      }
    }
  }

  void saveRate() async {
    final api = context.api;
    final messenger = ScaffoldMessenger.of(context);
    final newRate = double.tryParse(rateController.text.trim());
    if (newRate == null || newRate <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Please enter a valid rate")),
      );
      return;
    }

    if (newRate == currentRate) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Rate is unchanged")),
      );
      return;
    }
    final config = _config;
    if (config == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Rate configuration is not available")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final updated = await api.admin.updateDistanceRate(
        thresholdKm: config.thresholdKm,
        ratePerKm: newRate,
        taxPercent: config.taxPercent,
        roundTripFactor: config.roundTripFactor,
      );
      if (mounted) {
        setState(() {
          _config = updated;
          currentRate = updated.ratePerKm;
          isSaving = false;
        });
        messenger.showSnackBar(
          SnackBar(
              content:
                  Text("Rate updated to ₹${newRate.toStringAsFixed(2)}/km")),
        );
        loadRate();
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSaving = false);
        messenger.showSnackBar(
          SnackBar(content: Text("Failed to update rate: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Distance Rate"),
      ),
      body: isLoading
          ? const AppLoading(message: "Loading rate configuration...")
          : _loadError != null
              ? ErrorStateView(message: _loadError!, onRetry: loadRate)
              : SingleChildScrollView(
                  padding: AppDimensions.pagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppDimensions.spacingMd),
                      // Current rate info card
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.speed,
                                    color: AppColors.primary,
                                    size: AppDimensions.iconSizeMd),
                                const SizedBox(width: AppDimensions.spacingSm),
                                Text("Current Rate",
                                    style: AppTypography.cardTitle),
                              ],
                            ),
                            const Divider(height: AppDimensions.spacingXl),
                            Container(
                              padding:
                                  const EdgeInsets.all(AppDimensions.spacingMd),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                    AppDimensions.radiusSm),
                                border:
                                    Border.all(color: AppColors.info, width: 1),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.currency_rupee,
                                      color: AppColors.info, size: 20),
                                  const SizedBox(
                                      width: AppDimensions.spacingSm),
                                  Text(
                                    "₹${currentRate?.toStringAsFixed(2) ?? '10.00'} per km",
                                    style: AppTypography.sectionTitle
                                        .copyWith(color: AppColors.info),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),
                            Text(
                              "First ${_config?.thresholdKm.toStringAsFixed(0) ?? '-'} km is free. Beyond that, customers are charged this rate per km.",
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingLg),
                      // Update rate card
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.edit_outlined,
                                    color: AppColors.primary,
                                    size: AppDimensions.iconSizeMd),
                                const SizedBox(width: AppDimensions.spacingSm),
                                Text("Update Rate",
                                    style: AppTypography.cardTitle),
                              ],
                            ),
                            const Divider(height: AppDimensions.spacingXl),
                            Text(
                              "Adjust the rate based on current petrol prices. Changes apply immediately.",
                              style: AppTypography.body,
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),
                            AppInputField(
                              label: "Rate per KM (₹)",
                              hint: "e.g. 10.00",
                              controller: rateController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              prefixIcon: const Icon(Icons.currency_rupee,
                                  color: AppColors.textHint),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Please enter a rate";
                                }
                                final rate = double.tryParse(value.trim());
                                if (rate == null || rate <= 0) {
                                  return "Please enter a valid positive number";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),
                            AppButton(
                              label: "Update Rate",
                              onPressed: saveRate,
                              isLoading: isSaving,
                              icon: Icons.save_outlined,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingLg),
                      const SizedBox(height: AppDimensions.spacingLg),
                    ],
                  ),
                ),
    );
  }
}
