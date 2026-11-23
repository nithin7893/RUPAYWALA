import 'package:flutter/material.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class FamilyMemberEntry {
  final nameController = TextEditingController();
  final ageController = TextEditingController();
  String relationship = 'Self';
  final phoneController = TextEditingController();

  void dispose() {
    nameController.dispose();
    ageController.dispose();
    phoneController.dispose();
  }
}

class AddPolicyScreen extends StatefulWidget {
  const AddPolicyScreen({super.key});

  @override
  State<AddPolicyScreen> createState() => _AddPolicyScreenState();
}

class _AddPolicyScreenState extends State<AddPolicyScreen> {
  final typeController = TextEditingController();
  final providerController = TextEditingController();
  final numberController = TextEditingController();
  final amountController = TextEditingController();
  final expiryController = TextEditingController();
  final memberCountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;

  String selectedCategory = "individual";
  List<FamilyMemberEntry> familyMembers = [];

  static const List<String> relationshipOptions = [
    'Self',
    'Spouse',
    'Son',
    'Daughter',
    'Father',
    'Mother',
    'Brother',
    'Sister'
  ];

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppDimensions.spacingMd),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingMd),
                child: Text(
                  "Select Policy Category",
                  style: AppTypography.cardTitle,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingMd),
                child: Text(
                  "Choose Individual or Floater policy type",
                  style: AppTypography.caption,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(AppDimensions.spacingSm),
                  decoration: BoxDecoration(
                    color: selectedCategory == "individual"
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  ),
                  child: Icon(
                    Icons.person_outlined,
                    color: selectedCategory == "individual"
                        ? AppColors.primary
                        : AppColors.textHint,
                  ),
                ),
                title: const Text("Individual"),
                subtitle: const Text("Single person coverage"),
                trailing: selectedCategory == "individual"
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : Icon(Icons.circle_outlined,
                        color: AppColors.textHint.withValues(alpha: 0.5)),
                onTap: () {
                  setState(() => selectedCategory = "individual");
                  Navigator.pop(ctx);
                  _clearMembers();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(AppDimensions.spacingSm),
                  decoration: BoxDecoration(
                    color: selectedCategory == "floater"
                        ? AppColors.secondary.withValues(alpha: 0.1)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  ),
                  child: Icon(
                    Icons.people_outlined,
                    color: selectedCategory == "floater"
                        ? AppColors.secondary
                        : AppColors.textHint,
                  ),
                ),
                title: const Text("Floater"),
                subtitle: const Text("Family coverage for multiple members"),
                trailing: selectedCategory == "floater"
                    ? const Icon(Icons.check_circle, color: AppColors.secondary)
                    : Icon(Icons.circle_outlined,
                        color: AppColors.textHint.withValues(alpha: 0.5)),
                onTap: () {
                  setState(() => selectedCategory = "floater");
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: AppDimensions.spacingLg),
            ],
          ),
        );
      },
    );
  }

  void _updateMemberCount() {
    final count = int.tryParse(memberCountController.text) ?? 0;
    if (count < 0) return;

    while (familyMembers.length > count) {
      familyMembers.last.dispose();
      familyMembers.removeLast();
    }
    while (familyMembers.length < count) {
      familyMembers.add(FamilyMemberEntry());
    }
    setState(() {});
  }

  void _clearMembers() {
    for (var m in familyMembers) {
      m.dispose();
    }
    familyMembers.clear();
    memberCountController.clear();
  }

  void addPolicy() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedCategory == "floater") {
      final count = int.tryParse(memberCountController.text) ?? 0;
      if (count <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Please enter number of family members")),
        );
        return;
      }
      for (int i = 0; i < familyMembers.length; i++) {
        if (familyMembers[i].nameController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Please enter name for member ${i + 1}")),
          );
          return;
        }
        if (familyMembers[i].ageController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Please enter age for member ${i + 1}")),
          );
          return;
        }
      }
    }

    setState(() => isLoading = true);

    try {
      List<Map<String, dynamic>>? membersData;
      if (selectedCategory == "floater" && familyMembers.isNotEmpty) {
        membersData = familyMembers.map((m) {
          return <String, dynamic>{
            "member_name": m.nameController.text,
            "age": int.tryParse(m.ageController.text) ?? 0,
            "relationship": m.relationship,
            "phone_number": m.phoneController.text.isNotEmpty
                ? m.phoneController.text
                : null,
          };
        }).toList();
      }

      await context.api.customer.addPolicy(
        policyType: typeController.text,
        providerName: providerController.text,
        policyNumber: numberController.text,
        coverageAmount: double.tryParse(amountController.text.trim()),
        expiryDate: expiryController.text.trim(),
        policyCategory: selectedCategory,
        numberOfMembers:
            selectedCategory == "floater" ? familyMembers.length : null,
        members: membersData,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Policy Added Successfully")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to add policy: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    typeController.dispose();
    providerController.dispose();
    numberController.dispose();
    amountController.dispose();
    expiryController.dispose();
    memberCountController.dispose();
    for (var m in familyMembers) {
      m.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Policy"),
      ),
      body: SingleChildScrollView(
        padding: AppDimensions.pagePadding,
        child: Form(
          key: _formKey,
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
                        Icon(Icons.policy_outlined,
                            color: AppColors.primary,
                            size: AppDimensions.iconSizeMd),
                        const SizedBox(width: AppDimensions.spacingSm),
                        Text("Policy Details", style: AppTypography.cardTitle),
                      ],
                    ),
                    const Divider(height: AppDimensions.spacingXl),
                    GestureDetector(
                      onTap: _showCategoryPicker,
                      child: AbsorbPointer(
                        child: AppInputField(
                          label: "Policy Category *",
                          hint: "Tap to select Individual or Floater",
                          controller: TextEditingController(
                            text: selectedCategory == "individual"
                                ? "Individual"
                                : "Floater",
                          ),
                          prefixIcon: Icon(
                            selectedCategory == "individual"
                                ? Icons.person_outlined
                                : Icons.people_outlined,
                            color: AppColors.textHint,
                          ),
                          suffixIcon: const Icon(Icons.arrow_drop_down,
                              color: AppColors.textHint),
                          validator: (_) => null,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    AppInputField(
                      label: "Policy Type *",
                      hint: "e.g. Life, Health, Motor",
                      controller: typeController,
                      prefixIcon: const Icon(Icons.category_outlined,
                          color: AppColors.textHint),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please enter policy type";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    AppInputField(
                      label: "Provider Name *",
                      hint: "e.g. LIC, HDFC Ergo",
                      controller: providerController,
                      prefixIcon: const Icon(Icons.business_outlined,
                          color: AppColors.textHint),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please enter provider name";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    AppInputField(
                      label: "Policy Number *",
                      hint: "Enter unique policy number",
                      controller: numberController,
                      prefixIcon:
                          const Icon(Icons.numbers, color: AppColors.textHint),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please enter policy number";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    AppInputField(
                      label: "Coverage Amount",
                      hint: "Enter coverage amount",
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      prefixIcon: const Icon(Icons.currency_rupee,
                          color: AppColors.textHint),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    AppInputField(
                      label: "Expiry Date",
                      hint: "e.g. 2025-12-31",
                      controller: expiryController,
                      prefixIcon: const Icon(Icons.calendar_today_outlined,
                          color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              if (selectedCategory == "floater") ...[
                const SizedBox(height: AppDimensions.spacingLg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people_outlined,
                              color: AppColors.secondary,
                              size: AppDimensions.iconSizeMd),
                          const SizedBox(width: AppDimensions.spacingSm),
                          Text("Family Members",
                              style: AppTypography.cardTitle),
                        ],
                      ),
                      const Divider(height: AppDimensions.spacingXl),
                      AppInputField(
                        label: "Number of Family Members *",
                        hint: "Enter number of persons covered",
                        controller: memberCountController,
                        keyboardType: TextInputType.number,
                        prefixIcon: const Icon(Icons.group_outlined,
                            color: AppColors.textHint),
                        onChanged: (_) => _updateMemberCount(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Please enter number of members";
                          }
                          final n = int.tryParse(value);
                          if (n == null || n <= 0) {
                            return "Please enter a valid number";
                          }
                          return null;
                        },
                      ),
                      if (familyMembers.isNotEmpty) ...[
                        const SizedBox(height: AppDimensions.spacingLg),
                        ...List.generate(familyMembers.length, (index) {
                          return _buildMemberCard(index);
                        }),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppDimensions.spacingLg),
              AppButton(
                label: "Add Policy",
                onPressed: addPolicy,
                isLoading: isLoading,
                icon: Icons.add_circle_outline,
              ),
              const SizedBox(height: AppDimensions.spacingLg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCard(int index) {
    final member = familyMembers[index];
    return Container(
      margin: const EdgeInsets.only(bottom: AppDimensions.spacingMd),
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingSm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Text(
                  "Member ${index + 1}",
                  style: AppTypography.caption.copyWith(
                      color: AppColors.secondary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppInputField(
            label: "Name *",
            hint: "Enter member name",
            controller: member.nameController,
            prefixIcon:
                const Icon(Icons.person_outline, color: AppColors.textHint),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return "Please enter name";
              }
              return null;
            },
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppInputField(
            label: "Age *",
            hint: "Enter age",
            controller: member.ageController,
            keyboardType: TextInputType.number,
            prefixIcon:
                const Icon(Icons.cake_outlined, color: AppColors.textHint),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return "Please enter age";
              }
              final age = int.tryParse(value);
              if (age == null || age <= 0 || age > 120) {
                return "Please enter a valid age";
              }
              return null;
            },
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          DropdownButtonFormField<String>(
            initialValue: member.relationship,
            decoration: InputDecoration(
              labelText: "Relationship",
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 16, right: 8),
                child: Icon(Icons.family_restroom_outlined,
                    color: AppColors.textHint),
              ),
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: const BorderSide(color: AppColors.border, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide: const BorderSide(color: AppColors.border, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
            items: relationshipOptions.map((String r) {
              return DropdownMenuItem<String>(
                value: r,
                child: Text(r),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                member.relationship = newValue ?? 'Self';
              });
            },
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          AppInputField(
            label: "Phone Number (Optional)",
            hint: "Enter phone number",
            controller: member.phoneController,
            keyboardType: TextInputType.phone,
            prefixIcon:
                const Icon(Icons.phone_outlined, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}
