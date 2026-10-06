import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import '../models/task_model.dart';
import '../models/Tasks.dart' as AmplifyTasks;
import '../models/Checklists.dart' as AmplifyChecklists;

class TaskService {
  /// Fetch all tasks
  static Future<List<Task>> getTasks() async {
    try {
      final List<Task> parsedTasks = [];

      // 1. Fetch from Checklists table (Web app likely saves tasks here)
      try {
        final checklistReq = ModelQueries.list(AmplifyChecklists.Checklists.classType);
        final checklistRes = await Amplify.API.query(request: checklistReq).response;
        final checklistItems = checklistRes.data?.items.whereType<AmplifyChecklists.Checklists>() ?? [];
        print('=== TASK_SERVICE: Raw Checklists from API: ${checklistItems.length}, errors: ${checklistRes.errors} ===');
        for (final c in checklistItems) {
          String? caseId;
          String? priority;
          String? remark;
          String? createdBy;
          String? assignedToStr = c.assigned_to;
          
          if (c.data != null && c.data!.isNotEmpty) {
            try {
              final dataJson = jsonDecode(c.data!);
              caseId = dataJson['case_id']?.toString();
              priority = dataJson['priority']?.toString();
              remark = dataJson['remark']?.toString();
              createdBy = dataJson['created_by']?.toString();
              assignedToStr ??= dataJson['assigned_to']?.toString();
            } catch (_) {}
          }
          
          print('=== TASK_SERVICE: Checklist item id=${c.id}, title=${c.title}, assignedTo=$assignedToStr, createdBy=$createdBy ===');
          
          parsedTasks.add(Task(
            id: c.id,
            title: c.title ?? 'Untitled Task',
            remark: remark ?? c.description,
            priority: priority ?? 'Medium',
            assignedTo: assignedToStr,
            caseId: caseId,
            isRelatedToCase: caseId != null && caseId.isNotEmpty,
            isCompleted: c.status == 'completed' || c.status == 'done',
            createdBy: createdBy,
          ));
        }
      } catch (e) {
        print('=== TASK_SERVICE: Error fetching from Checklists table: $e ===');
      }

      // 2. Fetch from Tasks table
      final request = ModelQueries.list(AmplifyTasks.Tasks.classType);
      final response = await Amplify.API.query(request: request).response;
      final items = response.data?.items ?? [];
      print('=== TASK_SERVICE: Raw items from API: ${items.length}, errors: ${response.errors} ===');
      for (final t in items) {
        if (t == null) continue;
        try {
          // Try parsing from JSON stored in description or data fields first
          final jsonString = t.description ?? t.data ?? '';
          if (jsonString.trim().isNotEmpty && jsonString.trim().startsWith('{')) {
            try {
              final json = jsonDecode(jsonString);
              parsedTasks.add(Task.fromJson(json));
              continue;
            } catch (_) {}
          }
          
          // If the data field contains JSON, try parsing it
          if (t.data != null && t.data!.trim().isNotEmpty && t.data!.trim().startsWith('{')) {
            try {
              final json = jsonDecode(t.data!);
              parsedTasks.add(Task.fromJson(json));
              continue;
            } catch (_) {}
          }
          
          // Fallback: build Task from native Amplify model fields
          // This handles tasks created from the deployed web app
          final title = t.title ?? 'Untitled Task';
          if (title.isEmpty && (t.description ?? '').isEmpty) continue;
          
          // Parse the data field for extra info if it exists but isn't valid JSON
          String? assignedToStr;
          String? priority;
          String? caseId;
          String? status;
          String? createdBy;
          String? remark;
          
          // The data field might contain additional JSON-encoded task metadata
          if (t.data != null && t.data!.isNotEmpty) {
            try {
              final dataJson = jsonDecode(t.data!);
              assignedToStr = dataJson['assigned_to']?.toString();
              priority = dataJson['priority']?.toString();
              caseId = dataJson['case_id']?.toString();
              createdBy = dataJson['created_by']?.toString();
              remark = dataJson['remark']?.toString();
            } catch (_) {}
          }
          
          // Use the assigned_to int field as a fallback (might be a user index)
          assignedToStr ??= t.assigned_to?.toString();
          
          parsedTasks.add(Task(
            id: t.id,
            title: title,
            remark: remark ?? t.description,
            priority: priority ?? 'Medium',
            assignedTo: assignedToStr,
            caseId: caseId,
            isRelatedToCase: caseId != null && caseId.isNotEmpty,
            isCompleted: t.status == 'completed' || t.status == 'done',
            deadline: t.due_date != null ? DateTime.tryParse(t.due_date!) : null,
            createdBy: createdBy,
          ));
        } catch(e) {
          print('=== TASK_SERVICE: Failed to parse task: $e ===');
        }
      }
      print('=== TASK_SERVICE: Parsed tasks: ${parsedTasks.length} ===');
      return parsedTasks;
    } catch (e) {
      print('=== TASK_SERVICE: Error fetching tasks: $e ===');
      return [];
    }
  }

  /// Fetch tasks visible to a specific user (assigned to them, unassigned, or all staffs)
  static Future<List<Task>> getTasksForUser(String userEmail) async {
    final allTasks = await getTasks();
    final emailLower = userEmail.toLowerCase();
    final staffName = emailLower.split('@')[0];
    
    return allTasks.where((task) {
      final assignedTo = (task.assignedTo ?? '').toLowerCase().trim();
      // Show task if: unassigned, assigned to 'all', matches email, matches email prefix (staff name), or contains the staff name
      return assignedTo.isEmpty || 
             assignedTo == 'unassigned' || 
             assignedTo.contains('all') || 
             assignedTo == staffName ||
             assignedTo == emailLower ||
             staffName.contains(assignedTo) ||
             assignedTo.contains(staffName) ||
             assignedTo.contains(emailLower);
    }).toList();
  }

  /// Fetch tasks for a specific case
  static Future<List<Task>> getTasksByCase(String caseId) async {
    try {
      // In a real migration we'd query by caseId, but our AWS Tasks model currently uses JSON string mapping for extra fields.
      // So we fetch all and filter in memory for now.
      final allTasks = await getTasks();
      return allTasks.where((t) => t.caseId == caseId).toList();
    } catch (e) {
      print('Error fetching tasks for case: $e');
      return [];
    }
  }

  /// Fetch tasks assigned to a specific person
  static Future<List<Task>> getTasksByAssignee(String email) async {
    try {
      final allTasks = await getTasks();
      return allTasks.where((t) => t.assignedTo == email && !t.isCompleted).toList();
    } catch (e) {
      print('Error fetching tasks for assignee: $e');
      return [];
    }
  }

  /// Add a new task
  static Future<String?> addTask(Task task) async {
    try {
      // Because the current AWS Tasks schema differs from the app's Task fields, 
      // we'll serialize the full custom Task as a JSON string in the 'description' field for now,
      // or map standard fields where they match.
      final amplifyTask = AmplifyTasks.Tasks(
        id: task.id,
        title: task.title,
        description: jsonEncode(task.toJson()), // Store everything else in description
      );
      final request = ModelMutations.create(amplifyTask);
      await Amplify.API.mutate(request: request).response;
      return task.id;
    } catch (e) {
      print('Error adding task: $e');
      return null;
    }
  }

  /// Update task completion status
  static Future<void> updateTaskStatus(String id, bool isCompleted) async {
    try {
      final allTasks = await getTasks();
      final task = allTasks.firstWhere((t) => t.id == id);
      final updatedTask = task.copyWith(isCompleted: isCompleted, lastUpdated: DateTime.now());
      await updateTask(id, updatedTask);
    } catch (e) {
      print('Error updating task status: $e');
    }
  }

  /// Update detailed task properties
  static Future<void> updateTask(String id, Task task) async {
    try {
      final updatedTask = task.copyWith(lastUpdated: DateTime.now());
      final amplifyTask = AmplifyTasks.Tasks(
        id: id,
        title: updatedTask.title,
        description: jsonEncode(updatedTask.toJson()),
      );
      final request = ModelMutations.update(amplifyTask);
      await Amplify.API.mutate(request: request).response;
    } catch (e) {
      print('Error updating task: $e');
    }
  }

  /// Update specific task fields
  static Future<void> updateTaskDetails(String id, Map<String, dynamic> updates) async {
    try {
      final allTasks = await getTasks();
      final task = allTasks.firstWhere((t) => t.id == id);
      final json = task.toJson();
      json.addAll(updates);
      final updatedTask = Task.fromJson(json);
      await updateTask(id, updatedTask);
    } catch (e) {
      print('Error updating task details: $e');
    }
  }

  /// Delete a task
  static Future<void> deleteTask(String id) async {
    try {
      final amplifyTask = AmplifyTasks.Tasks(id: id);
      final request = ModelMutations.delete(amplifyTask);
      await Amplify.API.mutate(request: request).response;
    } catch (e) {
      print('Error deleting task: $e');
    }
  }

  /// Get overdue tasks
  static Future<List<Task>> getOverdueTasks() async {
    try {
      final allTasks = await getTasks();
      return allTasks.where((t) => t.isOverdue()).toList();
    } catch (e) {
      print('Error fetching overdue tasks: $e');
      return [];
    }
  }

  /// Get tasks by priority
  static Future<List<Task>> getTasksByPriority(String priority) async {
    try {
      final allTasks = await getTasks();
      return allTasks.where((t) => t.priority == priority && !t.isCompleted).toList();
    } catch (e) {
      print('Error fetching tasks by priority: $e');
      return [];
    }
  }

  /// Get high priority incomplete tasks
  static Future<List<Task>> getUrgentTasks() async {
    try {
      final allTasks = await getTasks();
      return allTasks.where((t) => !t.isCompleted && (t.priority == 'Critical' || t.priority == 'High')).toList();
    } catch (e) {
      print('Error fetching urgent tasks: $e');
      return [];
    }
  }

  /// TEMPORARY: Remove all auto-generated tasks created by the system
  static Future<void> removeAutoGeneratedTasks() async {
    try {
      final allTasks = await getTasks();
      for (final task in allTasks) {
        if (task.createdBy == 'System') {
          print('Deleting auto-generated task: ${task.title}');
          await deleteTask(task.id);
        }
      }
      print('Finished deleting auto-generated tasks.');
    } catch (e) {
      print('Error removing auto-generated tasks: $e');
    }
  }
}
