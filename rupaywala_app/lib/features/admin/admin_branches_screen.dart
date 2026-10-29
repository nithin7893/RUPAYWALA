import 'package:flutter/material.dart';
import '../../core/models/service_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class AdminBranchesScreen extends StatefulWidget {
  const AdminBranchesScreen({super.key});

  @override
  State<AdminBranchesScreen> createState() => _AdminBranchesScreenState();
}

class _AdminBranchesScreenState extends State<AdminBranchesScreen> {
  List<Branch> _branches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final branches = await context.api.admin.branches();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load branches: $e")),
        );
      }
    }
  }

  Future<void> _addBranch() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _BranchFormDialog(title: "Add Branch"),
    );
    if (result == null) return;

    try {
      await context.api.admin.addBranch(
        name: result["name"]!,
        address: result["address"]!,
        contactNumber: result["contact_number"],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Branch added successfully")),
        );
      }
      _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to add branch: $e")),
        );
      }
    }
  }

  Future<void> _editBranch(Branch branch) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _BranchFormDialog(
        title: "Edit Branch",
        initialName: branch.name,
        initialAddress: branch.address,
        initialContact: branch.contactNumber,
      ),
    );
    if (result == null) return;

    try {
      await context.api.admin.updateBranch(
        branch.id,
        name: result["name"],
        address: result["address"],
        contactNumber: result["contact_number"],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Branch updated successfully")),
        );
      }
      _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update branch: $e")),
        );
      }
    }
  }

  Future<void> _deleteBranch(Branch branch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Branch"),
        content: Text("Are you sure you want to deactivate '${branch.name}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await context.api.admin.deactivateBranch(branch.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Branch deactivated successfully")),
        );
      }
      _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete branch: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Branch Management"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBranch,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const AppLoading(message: "Loading branches...")
          : _branches.isEmpty
              ? const EmptyState(
                  icon: Icons.store_outlined,
                  title: "No Branches",
                  subtitle: "Tap + to add your first branch",
                )
              : RefreshIndicator(
                  onRefresh: _loadBranches,
                  child: ListView.builder(
                    padding: AppDimensions.pagePadding,
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      return _BranchCard(
                        branch: branch,
                        onEdit: () => _editBranch(branch),
                        onDelete: () => _deleteBranch(branch),
                      );
                    },
                  ),
                ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final Branch branch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BranchCard({
    required this.branch,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingMd),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.spacingSm),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusSm),
                    ),
                    child: Icon(
                      Icons.store,
                      size: AppDimensions.iconSizeMd,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          branch.name,
                          style: AppTypography.cardTitle,
                        ),
                        const SizedBox(height: AppDimensions.spacingXs),
                        Text(
                          branch.address,
                          style: AppTypography.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == "edit") onEdit();
                      if (value == "delete") onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: "edit",
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text("Edit"),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: "delete",
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text("Delete", style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: AppDimensions.spacingLg),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.location_on_outlined,
                    label:
                        "${branch.latitude.toStringAsFixed(4)}, ${branch.longitude.toStringAsFixed(4)}",
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Row(
                children: [
                  if (branch.contactNumber != null &&
                      branch.contactNumber!.isNotEmpty)
                    _InfoChip(
                      icon: Icons.phone_outlined,
                      label: branch.contactNumber!,
                    ),
                  if (branch.contactNumber != null &&
                      branch.contactNumber!.isNotEmpty)
                    const SizedBox(width: AppDimensions.spacingMd),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}

class _BranchFormDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialAddress;
  final String? initialContact;

  const _BranchFormDialog({
    required this.title,
    this.initialName,
    this.initialAddress,
    this.initialContact,
  });

  @override
  State<_BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<_BranchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _contactCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? "");
    _addressCtrl = TextEditingController(text: widget.initialAddress ?? "");
    _contactCtrl = TextEditingController(text: widget.initialContact ?? "");
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      "name": _nameCtrl.text.trim(),
      "address": _addressCtrl.text.trim(),
      "contact_number": _contactCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppInputField(
                label: "Branch Name",
                hint: "Enter branch name",
                controller: _nameCtrl,
                validator: (v) => v == null || v.trim().isEmpty
                    ? "Branch name is required"
                    : null,
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              AppInputField(
                label: "Address",
                hint: "Enter full address",
                controller: _addressCtrl,
                maxLines: 3,
                validator: (v) => v == null || v.trim().isEmpty
                    ? "Address is required"
                    : null,
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              AppInputField(
                label: "Contact Number",
                hint: "Enter contact number",
                controller: _contactCtrl,
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        AppButton(
          label: "Save",
          onPressed: _submit,
        ),
      ],
    );
  }
}
