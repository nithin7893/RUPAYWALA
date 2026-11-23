import 'package:flutter/material.dart';
import '../../core/models/ops_models.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  List<FieldMemberJob> tasks = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  void loadTasks() async {
    try {
      final result = await context.api.fieldMember.assignments();

      if (!mounted) return;
      setState(() {
        tasks = result;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load tasks: $e")),
        );
      }
    }
  }

  Future<void> completeTask(FieldMemberJob task) async {
    final notesController = TextEditingController();
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Complete task"),
        content: TextField(
          controller: notesController,
          decoration: const InputDecoration(labelText: "Completion notes"),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, notesController.text.trim()),
            child: const Text("Complete"),
          ),
        ],
      ),
    );
    notesController.dispose();
    if (notes == null || notes.isEmpty || !mounted) return;

    try {
      await context.api.fieldMember.complete(
        requestId: task.requestId,
        completionNotes: notes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Task marked as complete")),
        );
        loadTasks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to complete task: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Tasks"),
      ),
      body: isLoading
          ? const AppLoading(message: "Loading tasks...")
          : tasks.isEmpty
              ? const EmptyState(
                  icon: Icons.task_alt,
                  title: "No Tasks Assigned",
                  subtitle: "You don't have any pending tasks right now",
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spacingSm),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    final status = task.statusLabel;
                    final isCompleted = task.isDone;

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
                                    task.requestType,
                                    style: AppTypography.cardTitle,
                                  ),
                                ),
                                StatusChip(label: status),
                              ],
                            ),
                            if (task.description != null) ...[
                              const SizedBox(height: AppDimensions.spacingSm),
                              Text(
                                task.description!,
                                style: AppTypography.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: AppDimensions.spacingMd),
                            const Divider(),
                            const SizedBox(height: AppDimensions.spacingSm),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "Task ID: ${task.requestId}",
                                    style: AppTypography.caption,
                                  ),
                                ),
                                if (!isCompleted)
                                  SizedBox(
                                    width: 130,
                                    child: AppButton(
                                      label: "Complete",
                                      onPressed: () => completeTask(task),
                                      variant: AppButtonVariant.primary,
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppDimensions.spacingMd,
                                      vertical: AppDimensions.spacingXs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.success
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(
                                          AppDimensions.radiusSm),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: AppDimensions.iconSizeSm,
                                          color: AppColors.success,
                                        ),
                                        const SizedBox(
                                            width: AppDimensions.spacingXs),
                                        Text(
                                          "Done",
                                          style: TextStyle(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
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
