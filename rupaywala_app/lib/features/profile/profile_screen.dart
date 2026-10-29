import 'package:flutter/material.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../subscription/subscription_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final addressController = TextEditingController();
  final cityController = TextEditingController();
  final stateController = TextEditingController();
  final pincodeController = TextEditingController();
  final dobController = TextEditingController();

  String gender = "male";
  DateTime? dob;
  bool isLoading = false;

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        dob = picked;
        dobController.text = picked.toString().split(" ")[0];
      });
    }
  }

  void createProfile() async {
    if (nameController.text.isEmpty || dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please fill required fields (Name & DOB)")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await context.api.customer.saveProfile(
        fullName: nameController.text,
        dateOfBirth: dobController.text,
        gender: gender,
        email: emailController.text,
        address: addressController.text,
        city: cityController.text,
        state: stateController.text,
        pincode: pincodeController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile Created Successfully")),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const SubscriptionScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Profile creation failed: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    addressController.dispose();
    cityController.dispose();
    stateController.dispose();
    pincodeController.dispose();
    dobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Profile"),
      ),
      body: SingleChildScrollView(
        padding: AppDimensions.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppDimensions.spacingMd),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          color: AppColors.primary,
                          size: AppDimensions.iconSizeMd),
                      const SizedBox(width: AppDimensions.spacingSm),
                      Text("Personal Information",
                          style: AppTypography.cardTitle),
                    ],
                  ),
                  const Divider(height: AppDimensions.spacingXl),
                  AppInputField(
                    label: "Full Name *",
                    hint: "Enter your full name",
                    controller: nameController,
                    prefixIcon: const Icon(Icons.badge_outlined,
                        color: AppColors.textHint),
                  ),
                  const SizedBox(height: AppDimensions.spacingMd),
                  InkWell(
                    onTap: isLoading ? null : pickDate,
                    child: IgnorePointer(
                      child: AppInputField(
                        label: "Date of Birth *",
                        hint: dob == null ? "Select your date of birth" : null,
                        controller: dobController,
                        prefixIcon: const Icon(Icons.calendar_today_outlined,
                            color: AppColors.textHint),
                        suffixIcon: const Icon(Icons.calendar_today,
                            color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingMd),
                  DropdownButtonFormField<String>(
                    initialValue: gender,
                    items: const [
                      DropdownMenuItem(value: "male", child: Text("Male")),
                      DropdownMenuItem(value: "female", child: Text("Female")),
                      DropdownMenuItem(value: "other", child: Text("Other")),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          gender = value;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: "Gender",
                      prefixIcon:
                          Icon(Icons.wc_outlined, color: AppColors.textHint),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingMd),
                  AppInputField(
                    label: "Email",
                    hint: "Enter your email address",
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          color: AppColors.primary,
                          size: AppDimensions.iconSizeMd),
                      const SizedBox(width: AppDimensions.spacingSm),
                      Text("Address Details", style: AppTypography.cardTitle),
                    ],
                  ),
                  const Divider(height: AppDimensions.spacingXl),
                  AppInputField(
                    label: "Address",
                    hint: "Enter your street address",
                    controller: addressController,
                    maxLines: 2,
                    prefixIcon: const Icon(Icons.home_outlined,
                        color: AppColors.textHint),
                  ),
                  const SizedBox(height: AppDimensions.spacingMd),
                  AppInputField(
                    label: "City",
                    hint: "Enter your city",
                    controller: cityController,
                    prefixIcon: const Icon(Icons.location_city_outlined,
                        color: AppColors.textHint),
                  ),
                  const SizedBox(height: AppDimensions.spacingMd),
                  Row(
                    children: [
                      Expanded(
                        child: AppInputField(
                          label: "State",
                          hint: "Enter state",
                          controller: stateController,
                          prefixIcon: const Icon(Icons.map_outlined,
                              color: AppColors.textHint),
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spacingMd),
                      Expanded(
                        child: AppInputField(
                          label: "Pincode",
                          hint: "6 digits",
                          controller: pincodeController,
                          keyboardType: TextInputType.number,
                          prefixIcon: const Icon(Icons.pin_outlined,
                              color: AppColors.textHint),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            AppButton(
              label: "Create Profile",
              onPressed: createProfile,
              isLoading: isLoading,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
