import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/display_name_helper.dart';
import 'billing_screen.dart';
import 'expense_screen.dart';
import 'workfile_wizard_screen.dart';
import 'workfile_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'added_documents_screen.dart';

import '../theme/app_theme.dart';
import '../services/document_service.dart';
import '../widgets/payment_reminder_widget.dart';
import '../widgets/promised_payment_reminder_widget.dart';
import '../widgets/case_stages_widget.dart';
import '../widgets/task_management_widget.dart';
import '../models/task_model.dart';
import 'login_screen.dart';
import 'audit_history_screen.dart';
import 'case_calendar_screen.dart';
import 'case_detail_screen.dart';
import 'document_list_screen.dart';
import 'conflict_check_screen.dart';
import 'lead_management_screen.dart';
import 'communication_log_screen.dart';
import 'document_template_screen.dart';
import 'internal_staff_chat_screen.dart';
import 'task_management_screen.dart';
import 'client_management_screen.dart';
import 'case_list_screen.dart';
import 'inward_post_screen.dart';
import 'file_acknowledgement_screen.dart';
import 'file_delivery_screen.dart';
import '../services/vault_service.dart';
import '../services/attendance_service.dart';
import '../services/case_service.dart';
import '../services/meeting_service.dart';
import '../services/task_service.dart';
import '../services/session_tracking_service.dart';
import '../services/case_timer_service.dart';
import '../services/logging_service.dart';
import '../services/billing_service.dart';
import '../services/role_service.dart';
import '../widgets/responsive.dart';
import 'supreme_today_webview_screen.dart';
import 'travel_log_screen.dart';

class StaffDashboard extends StatefulWidget {
  final String userEmail;
  final String userRole;
  const StaffDashboard({
    super.key,
    required this.userEmail,
    this.userRole = 'Staff',
  });

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> with WidgetsBindingObserver {
  String _searchQuery = '';
  bool _isCheckedIn = false;
  String _checkInTime = '--';
  String _checkOutTime = '--';
  String _activeTime = '0m';
  int _totalActiveSeconds = 0;
  Timer? _sessionTimer;
  List<DailyRecord> _dailyHistory = [];
  
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _vaultFiles = [];

  int _chamberDocCount = 0;

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  List<Map<String, dynamic>> _assignedCases = [];
  List<Map<String, dynamic>> _meetingsToday = [];
  
  // Case Timer tracking
  String? _activeCaseId;
  int _activeCaseSeconds = 0;
  Timer? _caseTimerTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStateData();
    _startSessionTimer();
    _initCaseTimer();
  }

  Future<void> _initCaseTimer() async {
    _activeCaseId = await CaseTimerService.getActiveCaseId();
    _activeCaseSeconds = await CaseTimerService.getActiveSessionSeconds();
    if (_activeCaseId != null) {
      _caseTimerTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _activeCaseSeconds++;
          });
        }
      });
    }
  }

  void _startCaseTimer(Map<String, dynamic> caseFile) async {
    if (_activeCaseId != null) {
      return;
    }
    await CaseTimerService.startTimer(
      caseId: caseFile['id']!,
      caseTitle: caseFile['title']!,
      clientName: caseFile['clientName'] ?? 'Unknown client',
    );
    await LoggingService().logAction(
      action: 'Case Timer Started',
      targetType: 'Case Operations',
      targetId: caseFile['id'],
      details: 'Started timer on case: ${caseFile["title"]}',
    );
    setState(() {
      _activeCaseId = caseFile['id']!;
      _activeCaseSeconds = 0;
    });
    _caseTimerTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _activeCaseSeconds++;
        });
      }
    });
    Navigator.of(context).pop();
  }

  void _stopCaseTimer(String activityType, String notes) async {
    if (_activeCaseId == null) return;
    
    final result = await CaseTimerService.stopTimer();
    _caseTimerTicker?.cancel();
    
    setState(() {
      _activeCaseId = null;
      _activeCaseSeconds = 0;
    });

    if (result != null) {
      await BillingService.addBilling({
        'client_name': result.clientName,
        'invoice_no': 'TS-${DateTime.now().millisecondsSinceEpoch}',
        'date': DateTime.now().toIso8601String().split('T')[0],
        'amount': '0',
        'type': 'Timesheet',
        'category': result.caseId,
        'authorities': widget.userEmail.split('@')[0],
        'status': 'Unbilled',
        'data': {
          'hours_spent': result.hours.toStringAsFixed(2),
          'case_title': result.caseTitle,
          'activity_type': activityType,
          'notes': notes.isNotEmpty ? notes : 'Worked on case ${result.caseId}',
        }
      });
      
      // Add the case session time to the staff's daily active time
      await SessionTrackingService.addExtraTime(widget.userEmail, result.durationSeconds);
      
      await LoggingService().logAction(
        action: 'Case Timer Stopped',
        targetType: 'Case Operations',
        targetId: result.caseId,
        details: 'Logged timesheet. Duration: ${CaseTimerService.formatDuration(result.durationSeconds)}. Activity: $activityType.',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Timesheet logged: ${CaseTimerService.formatDuration(result.durationSeconds)}'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    }
  }

  void _showStopTimerDialog(Map<String, dynamic> caseFile) {
    String selectedActivity = 'Preparing Draft';
    final TextEditingController notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              title: const Text('Log Timesheet', style: TextStyle(color: AppTheme.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Select Activity Type', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedActivity,
                    dropdownColor: AppTheme.primaryColor,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    items: const [
                      DropdownMenuItem(value: 'Preparing Draft', child: Text('Preparing Draft')),
                      DropdownMenuItem(value: 'Legal Research', child: Text('Legal Research')),
                      DropdownMenuItem(value: 'Client Consultation', child: Text('Client Consultation')),
                      DropdownMenuItem(value: 'Court Appearance', child: Text('Court Appearance')),
                      DropdownMenuItem(value: 'Reviewing Documents', child: Text('Reviewing Documents')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (val) {
                      if (val != null) setStateDialog(() => selectedActivity = val);
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Additional Notes', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Describe the exact work done (e.g. prepared plaint draft)...',
                      hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
                  onPressed: () {
                    Navigator.pop(context); // Close this dialog
                    Navigator.pop(context); // Close the case details dialog
                    _stopCaseTimer(selectedActivity, notesController.text.trim());
                  },
                  child: const Text('STOP TIMER & LOG', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  String _formatCaseDuration(int seconds) {
    if (seconds == 0) return "00:00:00";
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _caseTimerTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_isCheckedIn) {
        SessionTrackingService.checkOut(widget.userEmail);
        AttendanceService.updateStatus(widget.userEmail, false, '--');
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isCheckedIn) {
        SessionTrackingService.checkIn(widget.userEmail);
        final now = DateTime.now();
        final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? "PM" : "AM"}';
        AttendanceService.updateStatus(widget.userEmail, true, timeStr);
      }
    }
  }

  void _startSessionTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshSessionStats();
    });
  }

  Future<void> _refreshSessionStats() async {
    final stats = await SessionTrackingService.getStats(widget.userEmail);
    final history = await SessionTrackingService.getDailyHistory(widget.userEmail);
    if (mounted) {
      setState(() {
        _isCheckedIn = stats.isActive;
        _checkInTime = stats.checkInTime;
        _checkOutTime = stats.checkOutTime;
        _totalActiveSeconds = stats.totalActiveSeconds;
        _activeTime = SessionTrackingService.formatDuration(stats.totalActiveSeconds);
        _dailyHistory = history;
      });
    }
  }

  Future<void> _loadStateData() async {
    try {
      final docs = await DocumentService.getAllDocuments();
      if (!mounted) return;
      setState(() {
        _chamberDocCount = docs.length;
      });
      
      final statusRecord = await AttendanceService.getStatus(widget.userEmail);
      if (statusRecord != null) {
        _isCheckedIn = statusRecord['is_checked_in'] as bool;
        _checkInTime = statusRecord['last_check_in_time'] as String;
      } else {
        final now = DateTime.now();
        final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? "PM" : "AM"}';
        await AttendanceService.updateStatus(widget.userEmail, true, timeStr);
        _isCheckedIn = true;
      }

      await _refreshSessionStats();
      
      final currentUserName = widget.userEmail;
      final cases = await CaseService.getCasesByAssignee(currentUserName);
      final meetings = await MeetingService.getMeetings();

      if (mounted) {
        setState(() {
          _assignedCases = cases.map((c) => {
            'db_id': c['id'].toString(),
            'id': c['case_id'].toString(),
            'title': c['case_title'].toString(),
            'clientName': c['client_name']?.toString() ?? 'Unknown client',
            'hearingDate': c['next_hearing']?.toString() ?? '',
            'type': c['case_type'].toString(),
            'status': c['status'].toString(),
            'notes': c['notes']?.toString() ?? '',
          }).toList();

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final tomorrow = today.add(const Duration(days: 1));

          final List<Map<String, dynamic>> allMeetings = [];
          
          allMeetings.addAll(meetings.map((m) => {
            'date': m['meeting_date'].toString(),
            'time': m['meeting_time'].toString(),
            'title': m['title'].toString(),
            'location': m['type'].toString(),
          }));

          for (var c in cases) {
            final rawHearing = c['next_hearing_date'] ?? c['next_hearing'] ?? c['hearingDate'] ?? c['hearing_date'];
            if (rawHearing != null && rawHearing.toString().trim().isNotEmpty && rawHearing.toString() != 'null' && rawHearing.toString() != 'N/A') {
              final parsed = DateTime.tryParse(rawHearing.toString());
              if (parsed != null) {
                final hearingDate = DateTime(parsed.year, parsed.month, parsed.day);
                String dateStr = rawHearing.toString().split('T')[0];
                if (hearingDate == today) dateStr = 'Today';
                else if (hearingDate == tomorrow) dateStr = 'Tomorrow';
                
                allMeetings.add({
                  'date': dateStr,
                  'time': c['hearing_time']?.toString() ?? c['time']?.toString() ?? '10:30 AM',
                  'title': 'Hearing: ${c['case_title'] ?? c['title'] ?? c['case_number'] ?? 'Case'}',
                  'location': c['court_details']?.toString() ?? c['court']?.toString() ?? 'Court',
                });
              }
            }
          }

          _meetingsToday = allMeetings;
        });
      }
      
      final fetchedTasks = await TaskService.getTasksForUser(widget.userEmail);
      
      // Load vault files
      final fetchedFiles = await VaultService.getFiles(widget.userEmail);

      if (!mounted) return;
      
      setState(() {
        _tasks = fetchedTasks.map((task) => {
          'id': task.id,
          'title': task.title,
          'isCompleted': task.isCompleted,
        }).toList();

        _vaultFiles = fetchedFiles.map((e) => {
          'id': e['id'],
          'fileName': e['file_name'],
          'uploadDate': e['upload_date'],
          'fileSize': e['file_size'],
        }).toList();
      });

    } catch (e) {
      print('Error loading staff dashboard data: $e');
    }
  }

  // Handle check-in and check-out status toggling
  Future<void> _toggleCheckIn() async {
    setState(() {
      _isCheckedIn = !_isCheckedIn;
      if (_isCheckedIn) {
        final now = DateTime.now();
        _checkInTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? "PM" : "AM"}';
      } else {
        _checkInTime = '--';
      }
    });

    await AttendanceService.updateStatus(widget.userEmail, _isCheckedIn, _checkInTime);
    
    if (_isCheckedIn) {
      await SessionTrackingService.checkIn(widget.userEmail);
    } else {
      await SessionTrackingService.checkOut(widget.userEmail);
    }

    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _isCheckedIn ? AppTheme.successGreen : AppTheme.errorRed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(_isCheckedIn ? Icons.login_rounded : Icons.logout_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              _isCheckedIn ? 'Checked in successfully at $_checkInTime' : 'Checked out successfully.',
              style: const TextStyle(fontFamily: 'Montserrat', color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  // Navigate to document list screen
  void _navigateToDocuments() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => DocumentListScreen(userEmail: widget.userEmail),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
    // Refresh document count on return
    final docs = await DocumentService.getAllDocuments();
    if (!mounted) return;
    setState(() => _chamberDocCount = docs.length);
  }

  // Trigger file picking using file_picker
  Future<void> _handleUploadDocument() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'zip', 'jpg', 'png'],
      );

      if (result != null) {
        PlatformFile pickedFile = result.files.first;
        
        // Start simulated upload animations
        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
          _uploadStatus = 'Initiating Secure Vault Connection...';
        });

        // Step 1: Encrypting
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        setState(() {
          _uploadProgress = 0.35;
          _uploadStatus = 'Encrypting document payload...';
        });

        // Step 2: Hashing
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        setState(() {
          _uploadProgress = 0.70;
          _uploadStatus = 'Applying Cochin Ledger verification hash...';
        });

        // Step 3: Completing
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        
        final now = DateTime.now();
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final dateStr = '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';
        
        final double sizeInMb = pickedFile.size / (1024 * 1024);
        final sizeStr = '${sizeInMb.toStringAsFixed(1)} MB';

        setState(() {
          _uploadProgress = 1.0;
          _uploadStatus = 'Upload successful!';
        });

        await VaultService.addFile(
          fileName: pickedFile.name,
          uploadDate: dateStr,
          fileSize: sizeStr,
          ownerEmail: widget.userEmail,
        );

        final fetchedFiles = await VaultService.getFiles(widget.userEmail);
        if (mounted) {
          setState(() {
            _vaultFiles = fetchedFiles.map((e) => {
              'id': e['id'],
              'fileName': e['file_name'],
              'uploadDate': e['upload_date'],
              'fileSize': e['file_size'],
            }).toList();
          });
        }

        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        setState(() {
          _isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.successGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${pickedFile.name} successfully secured in Chamber Vault.',
                    style: const TextStyle(fontFamily: 'Montserrat', color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.errorRed,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('Error picking file: $e', style: const TextStyle(fontFamily: 'Montserrat')),
        ),
      );
    }
  }

  // Remove file from vault
  Future<void> _deleteVaultFile(int index) async {
    final fileId = _vaultFiles[index]['id'];
    final fileName = _vaultFiles[index]['fileName'];
    
    await VaultService.deleteFile(fileId);
    
    setState(() {
      _vaultFiles.removeAt(index);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.errorRed.withAlpha(200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('$fileName deleted from vault.'),
        ),
      );
    });
  }

  // Toggle complete state of a task
  Future<void> _toggleTask(int index) async {
    final task = _tasks[index];
    final taskId = task['id'];
    final newStatus = !(task['isCompleted'] as bool);
    
    await TaskService.updateTaskStatus(taskId, newStatus);
    
    setState(() {
      _tasks[index]['isCompleted'] = newStatus;
    });
  }

  // Trigger Add Task popup modal
  void _showAddTaskDialog() {
    final controller = TextEditingController();
    final notesController = TextEditingController();
    String selectedPriority = 'Normal';
    DateTime? selectedDueDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          final canSave = controller.text.trim().isNotEmpty;
          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.25)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Create New Assignment Task',
                    style: TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Task title',
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      hintText: 'Enter task description...',
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    style: const TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Notes',
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      hintText: 'Optional work instructions',
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedPriority,
                          decoration: InputDecoration(
                            labelText: 'Priority',
                            filled: true,
                            fillColor: AppTheme.secondaryColor,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Normal', child: Text('Normal', style: TextStyle(color: AppTheme.textPrimary))),
                            DropdownMenuItem(value: 'High', child: Text('High', style: TextStyle(color: AppTheme.textPrimary))),
                            DropdownMenuItem(value: 'Urgent', child: Text('Urgent', style: TextStyle(color: AppTheme.textPrimary))),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => selectedPriority = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDueDate ?? now,
                              firstDate: DateTime(now.year),
                              lastDate: DateTime(now.year + 2),
                            );
                            if (picked != null) setState(() => selectedDueDate = picked);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentColor,
                            side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.25)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(selectedDueDate == null ? 'Set Due Date' : _formatDate(selectedDueDate!), style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.15)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('CANCEL', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: canSave
                              ? () async {
                                  final newTask = Task(
                                    id: Task.generateId(),
                                    title: controller.text.trim(),
                                    assignedTo: widget.userEmail.split('@')[0],
                                    createdAt: DateTime.now(),
                                    lastUpdated: DateTime.now(),
                                  );
                                  await TaskService.addTask(newTask);
                                  final fetchedTasks = await TaskService.getTasksForUser(widget.userEmail);
                                  
                                  if (!mounted) return;
                                  setState(() {
                                    _tasks = fetchedTasks.map((task) => {
                                      'id': task.id,
                                      'title': task.title,
                                      'isCompleted': task.isCompleted,
                                    }).toList();
                                  });
                                  Navigator.of(context).pop();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: const Text('SAVE TASK', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // Show details of assigned cases
  void _showCaseDetails(Map<String, dynamic> caseFile) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.25)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  caseFile['id']!,
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Case Ledger File',
                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caseFile['title']!,
                style: const TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 14),
              _buildDetailRow('Case Type', caseFile['type']!),
              _buildDetailRow('Next Hearing Date', caseFile['hearingDate']!),
              _buildDetailRow('Chamber Status', caseFile['status']!),
              const SizedBox(height: 12),
              const Text(
                'Case Summary / Assignment Instructions:',
                style: TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  caseFile['notes']!,
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textPrimary, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            StatefulBuilder(
              builder: (context, setStateDialog) {
                final isThisCaseActive = _activeCaseId == caseFile['id'];
                final isAnyCaseActive = _activeCaseId != null;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isThisCaseActive)
                      TextButton.icon(
                        icon: const Icon(Icons.stop_circle_rounded, color: AppTheme.errorRed, size: 18),
                        label: Text('Stop Session (${_formatCaseDuration(_activeCaseSeconds)})', style: const TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold, fontFamily: 'Montserrat', fontSize: 12)),
                        onPressed: () {
                          _showStopTimerDialog(caseFile);
                        },
                      )
                    else if (!isAnyCaseActive)
                      TextButton.icon(
                        icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.successGreen, size: 18),
                        label: const Text('Start Session', style: TextStyle(color: AppTheme.successGreen, fontWeight: FontWeight.bold, fontFamily: 'Montserrat', fontSize: 12)),
                        onPressed: () {
                          _startCaseTimer(caseFile);
                        },
                      )
                    else
                      const SizedBox.shrink(),
                      
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CaseDetailScreen(caseFile: caseFile.map((k, v) => MapEntry(k, v.toString()))),
                          ),
                        );
                      },
                      child: const Text('VIEW DETAILS', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('DISMISS', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              }
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding ?? const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accentColor.withOpacity(0.15), width: 1.2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final showSidebar = size.width > 950;
    final isDesktop = size.width > 1100;
    final isMobile = size.width < 600;
    final isTablet = size.width >= 600 && size.width < 950;
    final horizontalPadding = isMobile ? 8.0 : (isTablet ? 12.0 : 4.0);
    final verticalSpacing = isMobile ? 16.0 : 24.0;
    final sectionPadding = isMobile ? 12.0 : 20.0;

    final filteredCases = _assignedCases.where((c) {
      return c['title']!.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c['id']!.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c['type']!.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c['status']!.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    Widget mainContent = Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBanner(),
              SizedBox(height: verticalSpacing),
              _buildMetricsGrid(),
              SizedBox(height: verticalSpacing),
              // Payment Reminder Widget
              CompactPaymentReminderWidget(),
              SizedBox(height: verticalSpacing),
              PromisedPaymentReminderWidget(staffName: widget.userEmail.split('@').first),
              SizedBox(height: verticalSpacing),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          _buildAssignedCasesSection(sectionPadding, filteredCases),
                          SizedBox(height: verticalSpacing),
                          _buildDocumentVaultSection(sectionPadding),
                        ],
                      ),
                    ),
                    SizedBox(width: verticalSpacing),
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          _buildCalendarCard(),
                          SizedBox(height: verticalSpacing),
                          _buildTodoSection(sectionPadding),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAssignedCasesSection(sectionPadding, filteredCases),
                    SizedBox(height: verticalSpacing),
                    _buildCalendarCard(),
                    SizedBox(height: verticalSpacing),
                    _buildTodoSection(sectionPadding),
                    SizedBox(height: verticalSpacing),
                    _buildDocumentVaultSection(sectionPadding),
                  ],
                ),
              SizedBox(height: verticalSpacing),
              _buildDailyAttendanceHistory(),
            ],
          ),
        ),
        
        // Progress Overlay for uploading documents
        if (_isUploading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withAlpha(180),
              child: Center(
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.accentColor.withAlpha(120), width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _uploadStatus,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _uploadProgress,
                        backgroundColor: AppTheme.secondaryColor,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLogTravelDialog(context),
        icon: const Icon(Icons.directions_car),
        label: const Text('Log Travel', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppTheme.backgroundColor,
      drawer: !showSidebar ? Drawer(child: _buildSidebar(context, isDrawer: true)) : null,
      body: SafeArea(
        child: showSidebar
            ? Row(
                children: [
                  _buildSidebar(context),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: mainContent),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  Expanded(child: mainContent),
                ],
              ),
      ),
    );
  }

  void _showLogTravelDialog(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TravelLogScreen()));
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.accentColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppTheme.accentColor),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
          const SizedBox(width: 8),
          Image.asset('assets/logo.png', width: 28, height: 28),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'COCHIN UNITED',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'STAFF PORTAL',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAttendanceHistory() {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month_outlined, color: AppTheme.accentColor, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Daily Attendance Log',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_dailyHistory.length} Days',
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('DATE', style: TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor, letterSpacing: 1))),
                Expanded(flex: 2, child: Text('CHECK-IN', style: TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor, letterSpacing: 1))),
                Expanded(flex: 2, child: Text('CHECK-OUT', style: TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor, letterSpacing: 1))),
                Expanded(flex: 2, child: Text('ACTIVE TIME', style: TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor, letterSpacing: 1))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (_dailyHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No attendance data yet. Log in to start tracking.',
                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            ...List.generate(_dailyHistory.length, (index) {
              final record = _dailyHistory[index];
              final isToday = record.date == _todayStr();
              final activeStr = SessionTrackingService.formatDuration(record.totalActiveSeconds);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isToday ? AppTheme.accentColor.withValues(alpha: 0.06) : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.secondaryColor,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          if (isToday) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.successGreen),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            isToday ? 'Today' : _formatDateLabel(record.date),
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 12,
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                              color: isToday ? AppTheme.textPrimary : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        record.checkInTime,
                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.successGreen, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        record.checkOutTime == '--' && isToday ? 'Active' : record.checkOutTime,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          color: (record.checkOutTime == '--' && isToday) ? AppTheme.accentColor : AppTheme.errorRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        activeStr,
                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    ).animate().fade(duration: 600.ms).slideY(begin: 0.05, end: 0);
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatDateLabel(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        return '$day ${months[month - 1]} ${parts[0]}';
      }
    } catch (_) {}
    return dateStr;
  }

  Widget _buildTopBanner() {
    return _buildGlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: AppTheme.accentColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${DisplayNameHelper.fromEmail(widget.userEmail).toUpperCase()}!',
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  _isCheckedIn ? 'Status: Active Session (Checked in at $_checkInTime)' : 'Status: Offline',
                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 13, color: _isCheckedIn ? AppTheme.successGreen : AppTheme.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentColor),
              tooltip: 'Refresh Dashboard Data',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshing dashboard...'), duration: Duration(seconds: 1)));
                _loadStateData();
              },
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            icon: Icon(_isCheckedIn ? Icons.logout_rounded : Icons.login_rounded, size: 20),
            label: Text(_isCheckedIn ? 'CHECK OUT' : 'CHECK IN', style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isCheckedIn ? AppTheme.errorRed : AppTheme.successGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            onPressed: _toggleCheckIn,
          ).animate(target: _isCheckedIn ? 1 : 0).shimmer(duration: const Duration(seconds: 2), curve: Curves.easeInOut),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final int completedCount = _tasks.where((t) => t['isCompleted'] == true).length;
    final int totalTasks = _tasks.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double actualWidth = constraints.maxWidth;
        int cols = 1;
        if (actualWidth > 600) {
          cols = 3;
        } else if (actualWidth > 400) {
          cols = 2;
        }

        final double crossAxisSpacing = 12.0;
        final double totalSpacing = (cols - 1) * crossAxisSpacing;
        final double cellWidth = (actualWidth - totalSpacing) / cols;
        // Ensure height is exactly 120 pixels regardless of width
        final double aspectRatio = cellWidth / 120.0;

        return GridView.count(
          crossAxisCount: cols,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: 16.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: aspectRatio,
      children: [
        _buildMetricCard(
          title: 'ACTIVE TIME TODAY',
          value: _activeTime,
          icon: Icons.timer_outlined,
          color: AppTheme.accentColor,
          detail: _isCheckedIn ? '● Live tracking' : 'Session ended',
          onTap: () {},
        ),
        _buildMetricCard(
          title: 'TODAY\'S ASSIGNMENTS',
          value: '$completedCount / $totalTasks Done',
          icon: Icons.checklist_rounded,
          color: const Color(0xFFC084FC),
          detail: '${totalTasks - completedCount} pending tasks',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen()))),
        ),
        _buildMetricCard(
          title: 'CHAMBER DOCUMENTS',
          value: '$_chamberDocCount Documents',
          icon: Icons.description_outlined,
          color: const Color(0xFF34D399),
          detail: 'Encrypted document vault',
          onTap: () => _navigateToDocuments(),
        ),
      ],
        );
      },
    ).animate().fade(duration: 600.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String detail,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: _buildGlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 9,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignedCasesSection(double sectionPadding, List<Map<String, dynamic>> casesList) {
    return _buildGlassContainer(
      padding: EdgeInsets.all(sectionPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_shared_outlined, color: AppTheme.accentColor, size: 20),
              SizedBox(width: 8),
              Text(
                'My Assigned Case Files',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search cases field
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.1)),
            ),
            child: TextField(
              style: const TextStyle(
                fontFamily: 'Montserrat',
                color: AppTheme.textPrimary,
                fontSize: 13,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: 'Search cases by code, title, or status...',
                hintStyle: TextStyle(
                  fontFamily: 'Montserrat',
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                fillColor: Colors.transparent,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          casesList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No matching case files assigned',
                      style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: casesList.length,
                  separatorBuilder: (context, index) => Divider(
                    color: AppTheme.accentColor.withValues(alpha: 0.08),
                    height: 16,
                  ),
                  itemBuilder: (context, index) {
                    final caseFile = casesList[index];
                    return InkWell(
                      onTap: () => _showCaseDetails(caseFile),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    caseFile['title']!,
                                    style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        caseFile['id']!,
                                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '•  ${caseFile['type']!}',
                                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    caseFile['clientName'] ?? 'Unknown client',
                                    style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentColor.withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      caseFile['status']!,
                                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hear: ${caseFile['hearingDate']!}',
                                    style: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildDocumentVaultSection(double sectionPadding) {
    return _buildGlassContainer(
      padding: EdgeInsets.all(sectionPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, color: AppTheme.accentColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Secure Chamber Vault Uploads',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _handleUploadDocument,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 16, color: AppTheme.accentColor),
                label: const Text(
                  'UPLOAD',
                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _vaultFiles.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No documents uploaded to this workspace.',
                      style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _vaultFiles.length,
                  separatorBuilder: (context, index) => Divider(
                    color: AppTheme.accentColor.withValues(alpha: 0.08),
                    height: 16,
                  ),
                  itemBuilder: (context, index) {
                    final file = _vaultFiles[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, color: AppTheme.accentColor, size: 20),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file['fileName']!,
                                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Size: ${file['fileSize']!}  •  Uploaded ${file['uploadDate']!}',
                                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.errorRed),
                            onPressed: () => _deleteVaultFile(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: AppTheme.accentColor, size: 18),
              SizedBox(width: 8),
              Text(
                'My Upcoming Schedule',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _meetingsToday.length,
            separatorBuilder: (context, index) => Divider(color: AppTheme.accentColor.withValues(alpha: 0.05), height: 16),
            itemBuilder: (context, index) {
              final meeting = _meetingsToday[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          Text(
                            meeting['date']!,
                            style: const TextStyle(fontFamily: 'Montserrat', fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                          ),
                          Text(
                            meeting['time']!,
                            style: const TextStyle(fontFamily: 'Montserrat', fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meeting['title']!,
                            style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            meeting['location']!,
                            style: const TextStyle(fontFamily: 'Montserrat', fontSize: 8, color: AppTheme.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTodoSection(double sectionPadding) {
    return _buildGlassContainer(
      padding: EdgeInsets.all(sectionPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in_outlined, color: AppTheme.accentColor, size: 18),
              const SizedBox(width: 8),
              const Text(
                'My Task Checklist',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_task_rounded, size: 18, color: AppTheme.accentColor),
                onPressed: _showAddTaskDialog,
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.accentColor.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _tasks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('No personal tasks added.', style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tasks.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    final isCompleted = task['isCompleted'] == true;
                    return InkWell(
                      onTap: () => _toggleTask(index),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: isCompleted,
                                activeColor: AppTheme.accentColor,
                                checkColor: AppTheme.primaryColor,
                                side: BorderSide(color: AppTheme.textSecondary.withAlpha(120)),
                                onChanged: (_) => _toggleTask(index),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                task['title'],
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 11,
                                  color: isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
                                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 14, color: AppTheme.errorRed),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                final taskId = task['id']?.toString();
                                if (taskId != null) {
                                  await TaskService.deleteTask(taskId);
                                }
                                setState(() {
                                  _tasks.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, {bool isDrawer = false}) {
    // Extract username from email
    String displayName = 'Chamber Staff';
    if (widget.userEmail.contains('@')) {
      displayName = DisplayNameHelper.fromEmail(widget.userEmail);
      if (!displayName.startsWith('Adv.')) {
        displayName = 'Adv. $displayName';
      }
    }

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: isDrawer
            ? null
            : Border(
                right: BorderSide(
                  color: AppTheme.accentColor.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Logo & Branding
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Image.asset('assets/logo.png', width: 32, height: 32),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COCHIN UNITED',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'CHAMBER ASSOCIATES',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.secondaryColor, height: 1),
          // User profile card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_circle_outlined, color: AppTheme.accentColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          widget.userEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 9,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Nav Links
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.space_dashboard_outlined,
                  label: 'Staff Portal',
                  isActive: true,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.cases_rounded,
                  label: 'Case Management',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CaseListScreen()));
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.people_alt_rounded,
                  label: 'Client Data',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ClientManagementScreen()));
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.playlist_add_check_rounded,
                  label: 'Today\'s Task',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen())));
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.calendar_month_rounded,
                  label: 'Chamber Calendar',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const CaseCalendarScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
                              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                            ),
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 500),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.folder_shared_rounded,
                  label: 'Work File',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const WorkfileScreen()));
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.description_outlined,
                  label: 'Chamber Documents',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    _navigateToDocuments();
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text('FINANCE & DOCS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5)),
                ),
                if (RoleService.canManageBilling(widget.userRole)) ...[
                  _buildSidebarLink(
                    icon: Icons.receipt_long_rounded,
                    label: 'Billing',
                    isActive: false,
                    onTap: () {
                      if (isDrawer) Navigator.of(context).pop();
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => const BillingScreen(),
                      ));
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                _buildSidebarLink(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Expenses',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const ExpenseScreen(),
                    ));
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text('MANAGEMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5)),
                ),
                _buildSidebarLink(icon: Icons.task_alt_rounded, label: 'Deliveries and Pickup', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const FileDeliveryScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.mark_email_unread_rounded, label: 'Post Register', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => InwardPostScreen(currentUserRole: widget.userRole, currentUserName: widget.userEmail)));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.handshake_rounded, label: 'File Acknowledgement', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => FileAcknowledgementScreen(currentUserRole: widget.userRole, currentUserName: widget.userEmail)));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.history_rounded,
                  label: 'My Session Logs',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const AuditHistoryScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
                              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                            ),
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 500),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.directions_car_filled_outlined, label: 'Travel Logs', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TravelLogScreen()));
                }),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Divider(height: 1, color: Colors.white10),
                ),
                _buildSidebarLink(icon: Icons.smart_toy_rounded, label: 'Supreme AI', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SupremeTodayWebviewScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(
                  icon: Icons.chat_bubble_outline,
                  label: 'Staff Chat',
                  isActive: false,
                  onTap: () {
                    if (isDrawer) Navigator.of(context).pop();
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const InternalStaffChatScreen(userEmail: 'staff@cochinunited.com'),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
                              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                            ),
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 500),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.table_view_rounded, label: 'Upload Table', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddedDocumentsScreen()));
                }),
              ],
            ),
          ),
          // Footer
          const Divider(color: AppTheme.secondaryColor, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: _buildSidebarLink(
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              isActive: false,
              color: AppTheme.errorRed,
              onTap: () async {
                if (isDrawer) Navigator.of(context).pop();
                // Auto check-out on sign out
                await SessionTrackingService.checkOut(widget.userEmail);
                await AttendanceService.updateStatus(widget.userEmail, false, '--');
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    transitionDuration: const Duration(milliseconds: 600),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarLink({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    Color? color,
  }) {
    final displayColor = color ?? (isActive ? AppTheme.accentColor : AppTheme.textPrimary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accentColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: displayColor, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: displayColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple extension helper for capitalizing string titles
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}




