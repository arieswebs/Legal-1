import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'billing_screen.dart';
import 'expense_screen.dart';
import 'workfile_wizard_screen.dart';
import 'workfile_screen.dart';
import 'task_management_screen.dart';
import 'client_management_screen.dart';
import 'added_documents_screen.dart';
import 'automation_settings_screen.dart';

import 'work_management_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/payment_reminder_widget.dart';
import '../widgets/promised_payment_reminder_widget.dart';
import '../widgets/case_stages_widget.dart';
import '../widgets/task_management_widget.dart';
import '../models/task_model.dart';
import 'case_detail_screen.dart';
import 'document_list_screen.dart';
import 'login_screen.dart';
import 'audit_history_screen.dart';
import 'internal_staff_chat_screen.dart';
import 'case_calendar_screen.dart';
import 'case_management_screen.dart';
import 'case_list_screen.dart';
import 'inward_post_screen.dart';
import 'supreme_today_webview_screen.dart';
import 'client_folder_screen.dart';
import 'ecourts_dashboard.dart';
import 'file_delivery_screen.dart';
import 'admin_dashboard.dart';
import 'file_acknowledgement_screen.dart';
import 'travel_log_screen.dart';
import 'staff_management_screen.dart';
import '../models/inward_post_model.dart';
import '../services/case_service.dart';
import '../services/billing_service.dart';
import '../services/vault_service.dart';
import '../services/client_service.dart';
import 'package:file_picker/file_picker.dart';
import '../services/task_service.dart';
import '../services/user_service.dart';
import '../services/meeting_service.dart';
import '../services/document_service.dart';
import '../services/approval_service.dart';
import '../services/attendance_service.dart';
import '../services/session_tracking_service.dart';
import '../widgets/responsive.dart';
import '../utils/display_name_helper.dart';

class ManagerDashboard extends StatefulWidget {
  final String userEmail;
  final String userRole;
  const ManagerDashboard({
    super.key,
    this.userEmail = '',
    this.userRole = 'Manager',
  });

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  late String _currentUserRole;
  String _selectedRoleFilter = 'All';

  @override
  void initState() {
    super.initState();
    _currentUserRole = widget.userRole;
    _loadClients();
    _loadCases();
    _loadSharedChecklist();
    _loadDashboardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInwardPosts();
    });
  }

  Future<void> _loadCases() async {
    try {
      final cases = await CaseService.getCases();
      if (mounted) {
        setState(() {
          _clientCaseFiles = cases.map((c) {
            return {
              'db_id': (c['id'] ?? '').toString(),
              'clientName': (c['client_name'] ?? '').toString(),
              'caseId': (c['court_case_number'] ?? '').toString(),
              'caseTitle': (c['case_title'] ?? '').toString(),
              'caseType': (c['case_type'] ?? '').toString(),
              'hearingDate': '',
              'status': (c['case_status'] ?? '').toString(),
              'assignedTo': (c['responsible_staff'] ?? []).toString(),
              'advocates': '',
              'notes': (c['case_description'] ?? '').toString(),
            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading cases: $e');
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final users = await UserService.getAllUsers();
      final meetings = await MeetingService.getMeetings();
      final docs = await DocumentService.getAllDocuments();
      final attendances = await AttendanceService.getAllStatuses();


      final cases = await CaseService.getCases();

      final List<Map<String, dynamic>> updatedRoster = [];
      for (var u in users) {
        final userEmail = u['email'].toString();
        final statusRecord = attendances.firstWhere(
          (a) => a['staff_email'] == userEmail,
          orElse: () => <String, dynamic>{},
        );
        final isCheckedIn = statusRecord['is_checked_in'] == true;
        final checkInTime = statusRecord['last_check_in_time']?.toString() ?? '--';
        
        final sessionStats = await SessionTrackingService.getStats(userEmail);

        updatedRoster.add({
          'staffName': DisplayNameHelper.fromEmail(userEmail),
          'email': userEmail,
          'role': u['role'],
          'roleTitle': u['role'] == 'staff' ? 'Associate' : 'Senior',
          'checkInTime': isCheckedIn ? checkInTime : sessionStats.checkInTime,
          'checkOutTime': sessionStats.checkOutTime,
          'activeTime': SessionTrackingService.formatDuration(sessionStats.totalActiveSeconds),
          'status': isCheckedIn ? 'Checked-in' : 'Absent',
          'activeCase': 'Database Loaded',
        });
      }

      if (mounted) {
        setState(() {
          _staffRoster = updatedRoster;

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final tomorrow = today.add(const Duration(days: 1));

          final List<Map<String, dynamic>> allMeetings = [];
          
          allMeetings.addAll(meetings.map((m) => {
            'date': m['meeting_date'].toString(),
            'time': m['meeting_time'].toString(),
            'title': m['title'].toString(),
            'location': m['type'].toString(),
            'attendees': m['attendees'].toString(),
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
                  'attendees': c['handling_lawyer']?.toString() ?? c['assigned_counsel']?.toString() ?? 'Unassigned',
                });
              }
            }
          }

          _meetingsToday = allMeetings;

          _recentDocuments = docs.map((d) => {
            'title': d.title,
            'createdBy': d.createdBy,
            'date': d.createdAt.toIso8601String().split('T')[0],
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading dashboard data: $e');
    }
  }

  void _checkInwardPosts() {
    /*
    final pendingPosts = mockInwardPosts.where((p) => 
      (p.recipientName.toLowerCase().contains('manager') || p.recipientName.toLowerCase().contains('sarah')) && 
      p.status == 'pendingConfirmation'
    ).toList();
    */
    final pendingPosts = []; // Fixed compilation error

    for (var post in pendingPosts) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.3)),
            ),
            title: Row(
              children: [
                const Icon(Icons.mark_email_unread_outlined, color: AppTheme.accentColor),
                const SizedBox(width: 10),
                const Text('New Physical Post Received', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat', fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sender: \${post.senderName}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Received By: \${post.receivedBy}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Text('Description: \${post.description}', style: const TextStyle(color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    post.status = PostStatus.confirmed;
                  });
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen, foregroundColor: Colors.white),
                child: const Text('CONFIRM RECEIPT'),
              )
            ],
          );
        }
      );
    }
  }
  String _searchQuery = '';
  String _caseSearchQuery = '';
  String _selectedCaseType = 'All';
  String _caseSortField = 'Case Title';
  bool _isSortAscending = true;
  String _clientSearchQuery = '';
  int _activeSidebarIndex = 0;

  List<Map<String, String>> _clientCaseFiles = [];
  List<Map<String, dynamic>> _allClientsList = [];

  // Pending approvals loaded from backend or fallback
  List<Map<String, dynamic>> _pendingApprovals = [];
  Map<String, bool> _approvalSelected = {};

  Future<void> _loadClients() async {
    try {
      final clients = await ClientService().getAllClients();
      if (mounted) {
        setState(() {
          _allClientsList = clients;
        });
      }
    } catch (e) {
      print('Error loading clients: $e');
    }
  }

  Future<void> _loadPendingApprovals() async {
    try {
      final items = await ApprovalService.getPendingApprovals();
      if (!mounted) return;
      setState(() {
        _pendingApprovals = items;
        _approvalSelected = {for (var a in _pendingApprovals) (a['id'] ?? ''): false};
      });
    } catch (e) {
      // ignore errors for now
    }
  }

  Future<void> _approveApproval(String id) async {
    final ok = await ApprovalService.approve(id);
    if (ok && mounted) {
      setState(() {
        _pendingApprovals.removeWhere((a) => a['id'] == id);
        _approvalSelected.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approved')));
    }
  }

  Future<void> _rejectApproval(String id) async {
    final reasonController = TextEditingController();
    final cancelled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.12))),
          title: const Text('Reject Approval', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please provide a reason for rejection (optional)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Reason (e.g. incorrect amount, duplicate entry)',
                  filled: true,
                  fillColor: AppTheme.secondaryColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary))),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('REJECT', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    // If dialog was cancelled (true returned by CANCEL), don't proceed
    if (cancelled == true) return;

    final reason = reasonController.text.trim();
    final ok = await ApprovalService.reject(id, reason: reason.isEmpty ? null : reason);
    if (ok && mounted) {
      setState(() {
        _pendingApprovals.removeWhere((a) => a['id'] == id);
        _approvalSelected.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rejected${reason.isNotEmpty ? ': $reason' : ''}')));
    }
  }

  Future<void> _approveSelected() async {
    final ids = _approvalSelected.entries.where((e) => e.value).map((e) => e.key).toList();
    for (final id in ids) {
      await ApprovalService.approve(id);
    }
    if (mounted) {
      setState(() {
        _pendingApprovals.removeWhere((a) => ids.contains(a['id']));
        ids.forEach((id) => _approvalSelected.remove(id));
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approved ${ids.length} items')));
    }
  }

  void _toggleSelectAll(bool select) {
    setState(() {
      for (final k in _approvalSelected.keys.toList()) {
        _approvalSelected[k] = select;
      }
    });
  }

  List<String> get _caseTypeOptions {
    final options = <String>['All'];
    for (final caseFile in _clientCaseFiles) {
      final type = caseFile['caseType'];
      if (type != null && !options.contains(type)) {
        options.add(type);
      }
    }
    return options;
  }

  List<Map<String, String>> get _filteredCaseFiles {
    final query = _caseSearchQuery.trim().toLowerCase();
    final filtered = _clientCaseFiles.where((caseFile) {
      if (_selectedCaseType != 'All' && caseFile['caseType'] != _selectedCaseType) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return caseFile.values.any((value) => value.toLowerCase().contains(query));
    }).toList();

    filtered.sort((a, b) {
      final multiplier = _isSortAscending ? 1 : -1;
      switch (_caseSortField) {
        case 'Client':
          return multiplier * a['clientName']!.compareTo(b['clientName']!);
        case 'Case ID':
          return multiplier * a['caseId']!.compareTo(b['caseId']!);
        case 'Case Type':
          return multiplier * a['caseType']!.compareTo(b['caseType']!);
        case 'Hearing Date':
          return multiplier * _compareHearingDates(a['hearingDate'], b['hearingDate']);
        default:
          return multiplier * a['caseTitle']!.compareTo(b['caseTitle']!);
      }
    });

    return filtered;
  }

  int _compareHearingDates(String? aDate, String? bDate) {
    final aValue = _parseDateValue(aDate);
    final bValue = _parseDateValue(bDate);
    return aValue.compareTo(bValue);
  }

  int _parseDateValue(String? date) {
    if (date == null || date.isEmpty) return 0;
    final parts = date.split(' ');
    if (parts.length != 3) return 0;
    final day = int.tryParse(parts[0]) ?? 0;
    final month = _monthIndex(parts[1]);
    final year = int.tryParse(parts[2]) ?? 0;
    return year * 10000 + month * 100 + day;
  }

  int _monthIndex(String monthName) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months.indexOf(monthName) + 1;
  }

  final List<String> _additionalClients = [];

  List<Map<String, dynamic>> _staffRoster = [];
  List<Map<String, dynamic>> _meetingsToday = [];
  List<Map<String, dynamic>> _recentDocuments = [];
  List<Map<String, dynamic>> _sharedTasks = [];


  Future<void> _loadSharedChecklist() async {
    try {
      final tasks = await TaskService.getTasksForUser(widget.userEmail);
      if (mounted) {
        setState(() {
          _sharedTasks = tasks.map((task) => {
            'id': task.id,
            'title': task.title,
            'isCompleted': task.isCompleted,
            'remark': task.remark ?? '',
            'adjournedTo': task.adjournedTo?.toString() ?? '',
            'adjournReason': task.adjournReason ?? '',
            'deadline': task.deadline?.toIso8601String() ?? '',
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading checklist: $e');
    }
  }

  Future<void> _showTaskDetailsDialog(int index) async {
    final task = _sharedTasks[index];
    final typeController = TextEditingController(text: (task['caseType']?.toString().isEmpty ?? true) ? 'Civil' : task['caseType']);
    final remarkController = TextEditingController(text: task['remark'] ?? '');
    final reasonController = TextEditingController(text: task['adjournReason'] ?? '');
    bool showRemarkError = false;
    String mode = task['isCompleted'] == true
        ? 'completed'
        : (task['adjournedTo'] != null && (task['adjournedTo'] ?? '').isNotEmpty) ? 'adjourned' : 'pending';
    DateTime? selectedDate;
    if (task['adjournedTo'] != null && (task['adjournedTo'] as String).isNotEmpty) {
      try {
        selectedDate = DateTime.parse(task['adjournedTo']);
      } catch (_) {}
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          bool canSave() => remarkController.text.trim().isNotEmpty;
          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.12))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(backgroundColor: AppTheme.accentColor.withValues(alpha: 0.18), child: const Icon(Icons.task_alt, color: AppTheme.accentColor)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(task['title'], style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 16))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: Radio<String>(value: 'completed', groupValue: mode, onChanged: (v) => setState(() => mode = v!)),
                      title: const Text('Mark Completed', style: TextStyle(color: AppTheme.textPrimary)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: Radio<String>(value: 'pending', groupValue: mode, onChanged: (v) => setState(() => mode = v!)),
                      title: const Text('Pending / In Progress', style: TextStyle(color: AppTheme.textPrimary)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: Radio<String>(value: 'adjourned', groupValue: mode, onChanged: (v) => setState(() => mode = v!)),
                      title: const Text('Adjourn / Reschedule', style: TextStyle(color: AppTheme.textPrimary)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarkController,
                    onChanged: (_) {
                      if (showRemarkError && remarkController.text.trim().isNotEmpty) {
                        setState(() => showRemarkError = false);
                      }
                      setState(() {});
                    },
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Remarks',
                      hintText: 'Add notes about work',
                      errorText: showRemarkError && remarkController.text.trim().isEmpty ? 'Remarks required' : null,
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                  if (mode == 'adjourned') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: AppTheme.secondaryColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.06))),
                            child: Text(selectedDate == null ? 'No date selected' : _formatDate(selectedDate!), style: const TextStyle(color: AppTheme.textSecondary)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? now,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 2),
                            );
                            if (picked != null) setState(() => selectedDate = picked);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
                          child: const Text('Pick Date'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        labelText: 'Adjourn Reason',
                        hintText: 'Why was this adjourned?',
                        filled: true,
                        fillColor: AppTheme.secondaryColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.06)), foregroundColor: AppTheme.textSecondary),
                          child: const Text('CANCEL'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 110,
                        child: ElevatedButton(
                          onPressed: canSave() ? () async {
                            final remark = remarkController.text.trim();
                            if (remark.isEmpty) { setState(() => showRemarkError = true); return; }
                            final adjReason = reasonController.text.trim();
                            bool isCompleted = false;
                            String adjTo = '';
                            if (mode == 'completed') {
                              isCompleted = true;
                            } else if (mode == 'adjourned') {
                              adjTo = selectedDate != null ? selectedDate!.toIso8601String() : '';
                            }
                            final dbId = task['id'];
                            if (dbId != null) {
                              await TaskService.updateTaskDetails(dbId, {
                                'is_completed': isCompleted,
                                'remark': remark,
                                'adjourned_to': adjTo,
                                'adjourn_reason': adjReason,
                              });
                            }
                            await _loadSharedChecklist();
                            if (mounted) Navigator.of(context).pop();
                          } : null,
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
                          child: const Text('SAVE'),
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month-1]} ${d.year}';
  }

  String _formatDateTime(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day} ${months[d.month-1]} ${d.year} $hour:$minute $ampm';
  }

  void _showAddSharedTaskDialog() {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();
    final assigneeOptions = _staffRoster.map((staff) => staff['staffName'] as String).toList();
    String selectedAssignee = assigneeOptions.isNotEmpty ? assigneeOptions.first : 'Unassigned';
    String selectedPriority = 'Normal';
    String? selectedCaseId;
    DateTime? selectedDueDate;
    TimeOfDay? selectedDueTime;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          final canSave = titleController.text.trim().isNotEmpty;
          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.16))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.task_alt, color: AppTheme.accentColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Create Shared Task',
                          style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: titleController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Task title',
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      hintText: 'Brief task summary',
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: detailsController,
                    maxLines: 4,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Details',
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      hintText: 'Optional instructions or context',
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: selectedAssignee,
                          decoration: InputDecoration(
                            labelText: 'Assign to',
                            filled: true,
                            fillColor: AppTheme.secondaryColor,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                          items: assigneeOptions.map((name) {
                            return DropdownMenuItem(
                              value: name,
                              child: Text(name, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: AppTheme.textPrimary)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => selectedAssignee = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: selectedPriority,
                          decoration: InputDecoration(
                            labelText: 'Priority',
                            filled: true,
                            fillColor: AppTheme.secondaryColor,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: selectedCaseId,
                    decoration: InputDecoration(
                      labelText: 'Related case',
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                    hint: const Text('No case linked'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No case linked', style: TextStyle(color: AppTheme.textPrimary)),
                      ),
                      ..._clientCaseFiles.map((caseFile) {
                        final caseId = caseFile['caseId'] ?? 'Unknown ID';
                        final title = caseFile['caseTitle'] ?? 'Untitled case';
                        return DropdownMenuItem<String?>(
                          value: caseId,
                          child: Text('$caseId · $title', overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: AppTheme.textPrimary)),
                        );
                      }),
                    ],
                    onChanged: (value) => setState(() => selectedCaseId = value),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedDueDate == null
                                ? 'No due deadline set'
                                : '${_formatDate(selectedDueDate!)} ${selectedDueTime?.format(context) ?? ''}',
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDueDate ?? now,
                              firstDate: DateTime(now.year),
                              lastDate: DateTime(now.year + 2),
                            );
                            if (picked != null) setState(() {
                              selectedDueDate = picked;
                              selectedDueTime ??= const TimeOfDay(hour: 9, minute: 0);
                            });
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: const Text('Due Date'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: BorderSide(color: AppTheme.textSecondary.withOpacity(0.25)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: selectedDueTime ?? const TimeOfDay(hour: 9, minute: 0),
                            );
                            if (picked != null) setState(() {
                              selectedDueTime = picked;
                              selectedDueDate ??= DateTime.now();
                            });
                          },
                          icon: const Icon(Icons.access_time, size: 18),
                          label: const Text('Due Time'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: BorderSide(color: AppTheme.textSecondary.withOpacity(0.25)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.15)),
                          ),
                          child: const Text('CANCEL'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: canSave
                              ? () async {
                                  final deadline = selectedDueDate != null
                                      ? DateTime(
                                          selectedDueDate!.year,
                                          selectedDueDate!.month,
                                          selectedDueDate!.day,
                                          selectedDueTime?.hour ?? 9,
                                          selectedDueTime?.minute ?? 0,
                                        )
                                      : null;
                                  final newTask = Task(
                                    id: Task.generateId(),
                                    title: titleController.text.trim(),
                                    deadline: deadline,
                                    priority: selectedPriority,
                                    assignedTo: selectedAssignee,
                                    caseId: selectedCaseId,
                                    isRelatedToCase: selectedCaseId != null,
                                    createdAt: DateTime.now(),
                                    lastUpdated: DateTime.now(),
                                  );
                                  await TaskService.addTask(newTask);
                                  await _loadSharedChecklist();
                                  if (mounted) Navigator.of(context).pop();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final showSidebar = size.width > 950;

    final filteredRoster = _staffRoster.where((staff) {
      final matchesRole = _selectedRoleFilter == 'All' || 
          (_selectedRoleFilter == 'Checked-in' && staff['status'] == 'Checked-in') ||
          (_selectedRoleFilter == 'Absent' && staff['status'] == 'Absent');
      final matchesSearch = staff['staffName'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          staff['roleTitle'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          staff['activeCase'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesRole && matchesSearch;
    }).toList();

    final Widget dashboardContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDashboardHero(),
          const SizedBox(height: 24),
          _buildDashboardMetrics(),
          const SizedBox(height: 24),
          const PromisedPaymentReminderWidget(),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 1100) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildSharedChecklistCard(minHeight: 420)),
                        const SizedBox(width: 20),
                        Expanded(flex: 1, child: _buildRecentDocumentsCard(minHeight: 420)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildCalendarCard(),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSharedChecklistCard(),
                  const SizedBox(height: 18),
                  _buildRecentDocumentsCard(),
                  const SizedBox(height: 18),
                  _buildCalendarCard(),
                ],
              );
            },
          ),
        ],
      ),
    );

    Widget mainContent;
    if (_activeSidebarIndex == 1) {
      mainContent = SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16), child: _buildClientDirectorySection());
    } else if (_activeSidebarIndex == 2) {
      mainContent = SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16), child: _buildCaseFilesSection());
    } else if (_activeSidebarIndex == 3) {
      mainContent = SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16), child: _buildAttendanceSection(filteredRoster));
    } else {
      mainContent = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [dashboardContent],
      );
    }

    final Widget contentArea = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1420),
        child: mainContent,
      ),
    );

    return Scaffold(
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
                        Expanded(child: contentArea),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  Expanded(child: contentArea),
                ],
              ),
      ),
    );
  }

  Widget _buildDashboardHero() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cochin United Chamber',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Chamber overview for today. Monitor tasks, hearings, and newly created files in one place.',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _navigateToDocumentVault,
                      icon: const Icon(Icons.folder_open_rounded, size: 18, color: Color(0xFFD4AF37)),
                      label: const Text('Document Vault', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFD4AF37))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cochin United Chamber',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Chamber overview for today. Monitor tasks, hearings, and newly created files in one place.',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  ElevatedButton.icon(
                    onPressed: _navigateToDocumentVault,
                    icon: const Icon(Icons.folder_open_rounded, size: 18, color: Color(0xFFD4AF37)),
                    label: const Text('Document Vault', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFD4AF37))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(
                fontFamily: 'Montserrat',
                color: Color(0xFF0F172A),
                fontSize: 13.5,
              ),
              decoration: InputDecoration(
                hintText: 'Search tasks, cases, staff...',
                hintStyle: const TextStyle(
                  fontFamily: 'Montserrat',
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                ),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B), size: 16),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                return Row(
                  children: [
                    Expanded(
                      child: _buildHeroStat(
                        'Today’s Schedule',
                        '${_meetingsToday.where((meeting) => meeting['date'] == 'Today').length} items',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CaseCalendarScreen())),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildHeroStat(
                        'Deadline Tasks',
                        '${_sharedTasks.where((task) => task['isCompleted'] == false).length} open',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen()))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildHeroStat(
                        'New Documents',
                        '${_recentDocuments.length} added',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddedDocumentsScreen())),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _buildHeroStat(
                      'Today’s Schedule',
                      '${_meetingsToday.where((meeting) => meeting['date'] == 'Today').length} items',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CaseCalendarScreen())),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildHeroStat(
                      'Deadline Tasks',
                      '${_sharedTasks.where((task) => task['isCompleted'] == false).length} open',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen()))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildHeroStat(
                      'New Documents',
                      '${_recentDocuments.length} added',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddedDocumentsScreen())),
                    ),
                  ),
                ],
              );
            },
          ),

        ],
      ),
    );
  }

  Widget _buildDashboardMetrics() {
    final totalDocuments = _recentDocuments.length;
    final pendingTasks = _sharedTasks.where((task) => task['isCompleted'] == false).length;
    final upcomingHearings = _meetingsToday.where((meeting) => meeting['date'] == 'Today' || meeting['date'] == 'Tomorrow').length;
    final completedTasks = _sharedTasks.where((task) => task['isCompleted'] == true).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  'Pending tasks',
                  pendingTasks.toString(),
                  accent: const Color(0xFFDC2626),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen(initialStatus: 'Pending')))),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricChip(
                  'Upcoming hearings',
                  upcomingHearings.toString(),
                  accent: const Color(0xFFD97706),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CaseCalendarScreen())),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricChip(
                  'Completed tasks',
                  completedTasks.toString(),
                  accent: const Color(0xFF16A34A),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen(initialStatus: 'Completed')))),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricChip(
                  'New documents',
                  totalDocuments.toString(),
                  accent: const Color(0xFF0F172A),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddedDocumentsScreen())),
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildMetricChip(
                      'Pending tasks',
                      pendingTasks.toString(),
                      accent: const Color(0xFFDC2626),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen(initialStatus: 'Pending')))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricChip(
                      'Upcoming hearings',
                      upcomingHearings.toString(),
                      accent: const Color(0xFFD97706),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CaseCalendarScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricChip(
                      'Completed tasks',
                      completedTasks.toString(),
                      accent: const Color(0xFF16A34A),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen(initialStatus: 'Completed')))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricChip(
                      'New documents',
                      totalDocuments.toString(),
                      accent: const Color(0xFF0F172A),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddedDocumentsScreen())),
                    ),
                  ),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildHeroStat(String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
            ),
            Text(
              value,
              style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClientProfile(String clientName) async {
    final clientService = ClientService();
    final clientRecords = await clientService.searchClients(clientName);
    
    if (clientRecords.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client details not found.')));
      }
      return;
    }

    final clientEmail = clientRecords.first['email'];
    final vaultFiles = clientEmail != null ? await VaultService.getFiles(clientEmail) : <Map<String, dynamic>>[];
    final clientCases = _clientCaseFiles.where((caseFile) => caseFile['clientName'] == clientName).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border(bottom: BorderSide(color: AppTheme.accentColor.withOpacity(0.2))),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.accentColor.withOpacity(0.18),
                          child: Text(
                            clientName.isNotEmpty ? clientName[0].toUpperCase() : 'C',
                            style: const TextStyle(color: AppTheme.accentColor, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(clientName, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontFamily: 'Cinzel', fontWeight: FontWeight.bold)),
                              if (clientEmail != null) Text(clientEmail, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Montserrat')),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
                          children: [
                            const Text('Client Vault', style: TextStyle(color: AppTheme.accentColor, fontSize: 16, fontFamily: 'Cinzel', fontWeight: FontWeight.bold)),
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (clientEmail == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client email is missing, cannot upload to vault.')));
                                  return;
                                }

                                final existingFolders = vaultFiles.map((f) => (f['folder_name'] ?? 'Personal Files') as String).toSet();
                                final caseFolders = clientCases.map((c) => c['caseType'] as String).toSet();
                                final folderOptions = {'Personal Files', ...caseFolders, ...existingFolders}.toList();
                                String? selectedFolder = await showDialog<String>(
                                  context: context,
                                  builder: (context) {
                                    String currentFolder = 'Personal Files';
                                    bool isAddingCustom = false;
                                    TextEditingController customFolderController = TextEditingController();

                                    return StatefulBuilder(
                                      builder: (context, setFolderState) {
                                        return AlertDialog(
                                          backgroundColor: AppTheme.surfaceColor,
                                          title: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
                                            children: [
                                              const Text('Select Destination', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
                                              if (!isAddingCustom)
                                                IconButton(
                                                  icon: const Icon(Icons.add_circle_outline, color: AppTheme.accentColor),
                                                  tooltip: 'New Custom Folder',
                                                  onPressed: () {
                                                    setFolderState(() => isAddingCustom = true);
                                                  },
                                                ),
                                            ],
                                          ),
                                          content: isAddingCustom
                                              ? TextField(
                                                  controller: customFolderController,
                                                  style: const TextStyle(color: AppTheme.textPrimary),
                                                  decoration: InputDecoration(
                                                    hintText: 'e.g. Legal Notices',
                                                    hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.5)),
                                                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentColor.withOpacity(0.5))),
                                                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentColor)),
                                                  ),
                                                  autofocus: true,
                                                )
                                              : DropdownButton<String>(
                                                  value: currentFolder,
                                                  dropdownColor: AppTheme.primaryColor,
                                                  isExpanded: true,
                                                  style: const TextStyle(color: AppTheme.textPrimary),
                                                  items: folderOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                                                  onChanged: (val) {
                                                    if (val != null) setFolderState(() => currentFolder = val);
                                                  },
                                                ),
                                          actions: [
                                            if (isAddingCustom)
                                              TextButton(
                                                onPressed: () => setFolderState(() {
                                                  isAddingCustom = false;
                                                  customFolderController.clear();
                                                }),
                                                child: const Text('BACK', style: TextStyle(color: AppTheme.textSecondary))
                                              )
                                            else
                                              TextButton(
                                                onPressed: () => Navigator.pop(context), 
                                                child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary))
                                              ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
                                              onPressed: () {
                                                if (isAddingCustom) {
                                                  if (customFolderController.text.trim().isNotEmpty) {
                                                    Navigator.pop(context, customFolderController.text.trim());
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folder name cannot be empty.')));
                                                  }
                                                } else {
                                                  Navigator.pop(context, currentFolder);
                                                }
                                              },
                                              child: const Text('SELECT', style: TextStyle(color: AppTheme.primaryColor)),
                                            ),
                                          ],
                                        );
                                      }
                                    );
                                  }
                                );

                                if (selectedFolder == null) return;

                                FilePickerResult? result = await FilePicker.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['pdf', 'docx', 'doc', 'zip', 'jpg', 'png'],
                                  withData: true,
                                );

                                if (result != null) {
                                  PlatformFile pickedFile = result.files.first;
                                  
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading ${pickedFile.name} to $selectedFolder...')));

                                  await Future.delayed(const Duration(milliseconds: 600));
                                  
                                  final dateStr = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
                                  final double sizeInMb = pickedFile.size / (1024 * 1024);
                                  final sizeStr = '${sizeInMb.toStringAsFixed(1)} MB';

                                  await VaultService.addFile(
                                    fileName: pickedFile.name,
                                    uploadDate: dateStr,
                                    fileSize: sizeStr,
                                    ownerEmail: clientEmail,
                                    folderName: selectedFolder,
                                    fileBytes: pickedFile.bytes,
                                  );

                                  final updatedFiles = await VaultService.getFiles(clientEmail);
                                  
                                  setModalState(() {
                                    vaultFiles.clear();
                                    vaultFiles.addAll(updatedFiles);
                                  });
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document uploaded successfully.')));
                                  }
                                }
                              },
                              icon: const Icon(Icons.upload_file, size: 16),
                              label: const Text('UPLOAD'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentColor.withOpacity(0.15),
                                foregroundColor: AppTheme.accentColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (vaultFiles.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
                            ),
                            child: const Text('No documents uploaded for this client yet.', style: TextStyle(color: AppTheme.textSecondary)),
                          )
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final existingFolders = vaultFiles.map((f) => (f['folder_name'] ?? 'Personal Files') as String).toSet();
                              final caseFolders = clientCases.map((c) => c['caseType'] as String).toSet();
                              final allUniqueFolders = {'Personal Files', ...caseFolders, ...existingFolders}.toList();
                              
                              int crossAxisCount = 2;
                              if (constraints.maxWidth > 900) {
                                crossAxisCount = 4;
                              } else if (constraints.maxWidth > 600) {
                                crossAxisCount = 3;
                              }
                              
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 1.1,
                                ),
                                itemCount: allUniqueFolders.length,
                                itemBuilder: (context, index) {
                                  final folder = allUniqueFolders[index];
                                  final folderFiles = vaultFiles.where((f) => (f['folder_name'] ?? 'Personal Files') == folder).toList();
                                  
                                  return InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ClientFolderScreen(
                                            clientName: clientName,
                                            clientEmail: clientEmail ?? '',
                                            folderName: folder,
                                          ),
                                        ),
                                      ).then((_) async {
                                        // Refresh vault files when returning from folder screen
                                        if (clientEmail != null) {
                                          final updatedFiles = await VaultService.getFiles(clientEmail);
                                          setModalState(() {
                                            vaultFiles.clear();
                                            vaultFiles.addAll(updatedFiles);
                                          });
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceColor,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: AppTheme.accentColor.withOpacity(0.2)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.accentColor.withOpacity(0.05),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          )
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            folder == 'Personal Files' ? Icons.folder_shared : Icons.folder,
                                            size: 48,
                                            color: AppTheme.accentColor,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            folder,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${folderFiles.length} files',
                                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            }
                          ),
                        const SizedBox(height: 32),
                        const Text('Registered Cases', style: TextStyle(color: AppTheme.accentColor, fontSize: 16, fontFamily: 'Cinzel', fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        if (clientCases.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1)),
                            ),
                            child: const Text('No cases registered for this client.', style: TextStyle(color: AppTheme.textSecondary)),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: clientCases.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final c = clientCases[index];
                              return Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.accentColor.withOpacity(0.1)),
                                ),
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentColor.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.gavel, color: AppTheme.accentColor, size: 20),
                                  ),
                                  title: Text(c['caseType'] ?? 'Unknown Case', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Status: ${c['status'] ?? 'Draft'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                        const SizedBox(height: 2),
                                        Text('Counsel: ${c['counsel'] ?? 'Unassigned'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(c['date'] ?? '', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 16),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildMetricChip(String label, String value, {Color accent = const Color(0xFF0F172A), VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF475569),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
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
          Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppTheme.accentColor),
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
              );
            }
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
                  'CHAMBER ADMINISTRATOR DASHBOARD',
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


  Widget _buildRosterSection(List<Map<String, dynamic>> rosterList) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline_rounded, color: AppTheme.accentColor, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Chamber Staff check-In Roster',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
                onPressed: () => setState(() => _activeSidebarIndex = 0),
                tooltip: 'Back',
              ),
              _buildRosterFilterDropdown(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSearchField(),
          const SizedBox(height: 20),
          rosterList.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rosterList.length,
                  separatorBuilder: (context, index) => Divider(
                    color: AppTheme.accentColor.withValues(alpha: 0.08),
                    height: 20,
                  ),
                  itemBuilder: (context, index) {
                    final staff = rosterList[index];
                    return _buildRosterItem(staff, index);
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildRosterFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRoleFilter,
          dropdownColor: AppTheme.surfaceColor,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.accentColor),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedRoleFilter = newValue;
              });
            }
          },
          items: <String>['All', 'Checked-in', 'Absent']
              .map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text('Status: $value'),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
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
          hintText: 'Search roster by name, title, or active case assignment...',
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
    );
  }

  Widget _buildRosterItem(Map<String, dynamic> staff, int index) {
    final bool isCheckedIn = staff['status'] == 'Checked-in';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;
          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
                  children: [
                    Text(
                      staff['staffName'],
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    _buildRosterStatusChip(isCheckedIn),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  staff['roleTitle'],
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.accentColor),
                ),
                const SizedBox(height: 6),
                Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('In: ${staff['checkInTime']}', style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.successGreen)),
                        Text('Out: ${staff['checkOutTime']}', style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.errorRed)),
                        Text('Active: ${staff['activeTime']}', style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => _showAssignTaskDialog(staff),
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFF60A5FA).withValues(alpha: 0.1),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text('Assign Task', style: TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA))),
                        ),
                        if (staff['email'] == widget.userEmail) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _toggleCheckInStatus(staff),
                            style: TextButton.styleFrom(
                              backgroundColor: isCheckedIn ? AppTheme.errorRed.withValues(alpha: 0.1) : AppTheme.successGreen.withValues(alpha: 0.1),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: Text(
                              isCheckedIn ? 'Check Out' : 'Check In',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isCheckedIn ? AppTheme.errorRed : AppTheme.successGreen,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff['staffName'],
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      staff['roleTitle'],
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Details',
                      style: TextStyle(fontFamily: 'Montserrat', fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'In: ${staff['checkInTime']}',
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.successGreen),
                    ),
                    Text(
                      'Out: ${staff['checkOutTime']}',
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.errorRed),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Time Today',
                      style: TextStyle(fontFamily: 'Montserrat', fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      staff['activeTime'] ?? '--',
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildRosterStatusChip(isCheckedIn),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: TextButton(
                        onPressed: () => _showAssignTaskDialog(staff),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF60A5FA).withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text(
                          'Assign Task',
                          style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA)),
                        ),
                      ),
                    ),
                    if (staff['email'] == widget.userEmail) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 95,
                        child: TextButton(
                          onPressed: () => _toggleCheckInStatus(staff),
                          style: TextButton.styleFrom(
                            backgroundColor: isCheckedIn ? AppTheme.errorRed.withValues(alpha: 0.1) : AppTheme.successGreen.withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(
                            isCheckedIn ? 'Check Out' : 'Check In',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCheckedIn ? AppTheme.errorRed : AppTheme.successGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRosterStatusChip(bool isCheckedIn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCheckedIn ? AppTheme.successGreen.withValues(alpha: 0.12) : AppTheme.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isCheckedIn ? AppTheme.successGreen.withValues(alpha: 0.4) : AppTheme.textSecondary.withValues(alpha: 0.3)),
      ),
      child: Text(
        isCheckedIn ? 'Checked-in' : 'Absent',
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isCheckedIn ? AppTheme.successGreen : AppTheme.textSecondary,
        ),
      ),
    );
  }

  void _toggleCheckInStatus(Map<String, dynamic> staff) {
    setState(() {
      if (staff['status'] == 'Checked-in') {
        staff['status'] = 'Absent';
        staff['checkInTime'] = '--';
      } else {
        staff['status'] = 'Checked-in';
        final now = DateTime.now();
        staff['checkInTime'] = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} AM';
      }
    });
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(40.0),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: AppTheme.textSecondary, size: 48),
          SizedBox(height: 12),
          Text(
            'No matching staff roster files',
            style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSection(List<Map<String, dynamic>> rosterList) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Attendance header card containing roster
        _buildRosterSection(rosterList),
      ],
    );
  }

  Widget _buildClientDirectorySection() {
    final uniqueClients = {
      ..._allClientsList.map((client) => client['name'].toString()),
      ..._clientCaseFiles.map((caseFile) => caseFile['clientName']),
      ..._additionalClients,
    }.whereType<String>().toList();

    final filteredClients = uniqueClients
        .where((name) => name.toLowerCase().contains(_clientSearchQuery.toLowerCase()))
        .toList();

    final totalCases = _clientCaseFiles.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
              onPressed: () => setState(() => _activeSidebarIndex = 0),
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Clients',
                style: TextStyle(fontFamily: 'Montserrat', fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _showAddClientDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Client', style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, color: AppTheme.accentColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${filteredClients.length} client${filteredClients.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, color: AppTheme.accentColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$totalCases case${totalCases == 1 ? '' : 's'}',
                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          height: 78,
          decoration: BoxDecoration(
            color: AppTheme.secondaryColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.analytics_outlined, color: AppTheme.accentColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Top client insights',
                      style: TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      filteredClients.isEmpty
                          ? 'No clients found. Use the search box or add a new client.'
                          : 'Showing $filteredClients.length of ${uniqueClients.length} clients with their active case counts and latest work status.',
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.12), width: 1),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (value) {
                  setState(() {
                    _clientSearchQuery = value;
                  });
                },
                style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                  hintText: 'Search clients...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat'),
                  filled: true,
                  fillColor: AppTheme.secondaryColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              filteredClients.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: const [
                          Icon(Icons.search_off_rounded, color: AppTheme.textSecondary, size: 40),
                          SizedBox(height: 12),
                          Text(
                            'No clients match your search.',
                            style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredClients.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final clientName = filteredClients[index];
                        final clientCases = _clientCaseFiles.where((caseFile) => caseFile['clientName'] == clientName).toList();
                        final caseCount = clientCases.length;
                        final latestCase = clientCases.isNotEmpty ? clientCases.last : null;
                        final initials = clientName.trim().split(' ').map((part) => part.isNotEmpty ? part[0] : '').take(2).join();
                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.08)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showClientProfile(clientName),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppTheme.accentColor.withValues(alpha: 0.18),
                                    child: Text(
                                      initials.toUpperCase(),
                                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                clientName,
                                                style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.accentColor.withValues(alpha: 0.18),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                '$caseCount case${caseCount == 1 ? '' : 's'}',
                                                style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.accentColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          latestCase != null ? latestCase['caseTitle'] ?? 'Open case' : 'No active case yet',
                                          style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            _buildInfoChip(latestCase != null ? latestCase['caseType'] ?? 'Unknown' : 'No status'),
                                            if (latestCase != null) _buildInfoChip(latestCase['status'] ?? 'Status unknown'),
                                            if (latestCase != null && latestCase['hearingDate'] != null)
                                              _buildInfoChip('Hearing ${latestCase['hearingDate']}'),
                                            if (latestCase != null && latestCase['advocates'] != null)
                                              _buildInfoChip('Advocates: ${latestCase['advocates']}', accent: true),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.accentColor),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(String value, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent ? AppTheme.highlightColor.withValues(alpha: 0.95) : AppTheme.secondaryColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent ? AppTheme.accentColor : AppTheme.accentColor.withValues(alpha: 0.08), width: accent ? 1.2 : 1),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 10,
          color: accent ? AppTheme.primaryColor : AppTheme.textSecondary,
          fontWeight: accent ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAttractiveTextField({required TextEditingController controller, required String hint, required IconData icon}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSecondary.withOpacity(0.1), width: 1),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 12.0),
            child: Icon(icon, color: AppTheme.accentColor.withOpacity(0.8), size: 20),
          ),
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.5), fontSize: 14),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.accentColor.withOpacity(0.5), width: 1)),
        ),
      ),
    );
  }

  void _showAddClientDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final typeController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.accentColor.withOpacity(0.15), width: 1),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 10)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        border: Border(bottom: BorderSide(color: AppTheme.accentColor.withOpacity(0.1))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_add_alt_1, color: AppTheme.accentColor, size: 28),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Add New Client', style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentColor, fontSize: 20, fontWeight: FontWeight.bold)),
                                SizedBox(height: 4),
                                Text('Register a new client profile', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary, fontSize: 13)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    // Form Fields
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildAttractiveTextField(controller: nameController, hint: 'Client Name', icon: Icons.person_outline),
                            const SizedBox(height: 16),
                            _buildAttractiveTextField(controller: emailController, hint: 'Email Address', icon: Icons.email_outlined),
                            const SizedBox(height: 16),
                            _buildAttractiveTextField(controller: phoneController, hint: 'Phone Number', icon: Icons.phone_outlined),
                            const SizedBox(height: 16),
                            _buildAttractiveTextField(controller: addressController, hint: 'Address', icon: Icons.location_on_outlined),
                            const SizedBox(height: 16),
                            _buildAttractiveTextField(controller: typeController, hint: 'Type of Work (Optional)', icon: Icons.work_outline),
                          ],
                        ),
                      ),
                    ),
                    // Footer Actions
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                            child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat', fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: isSaving ? null : () async {
                              final clientName = nameController.text.trim();
                              final clientEmail = emailController.text.trim();
                              
                              if (clientName.isEmpty || clientEmail.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and Email are required.')));
                                return;
                              }
                              
                              setDialogState(() => isSaving = true);
                              
                              final newClient = await ClientService().addClientFull({
                                'name': clientName,
                                'email': clientEmail,
                                'phone': phoneController.text.trim(),
                                'address': addressController.text.trim(),
                                'type_of_work': typeController.text.trim(),
                              });
                              
                              if (newClient != null) {
                                setState(() {
                                  _additionalClients.add(clientName);
                                });
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client created successfully!')));
                                }
                              } else {
                                setDialogState(() => isSaving = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create client.')));
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: isSaving 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)) 
                              : const Text('REGISTER CLIENT', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildCaseFilesSection() {
    final filteredCases = _filteredCaseFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
              onPressed: () => setState(() => _activeSidebarIndex = 0),
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
            const Text(
              'Case Files',
              style: TextStyle(fontFamily: 'Montserrat', fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CaseListScreen()),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              icon: const Icon(Icons.manage_accounts_rounded, size: 16, color: AppTheme.primaryColor),
              label: const Text('Manage Cases', style: TextStyle(color: AppTheme.primaryColor, fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by case type, name, or title',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.secondaryColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                ),
                onChanged: (value) => setState(() => _caseSearchQuery = value),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.12)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCaseType,
                  dropdownColor: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  iconEnabledColor: AppTheme.accentColor,
                  items: _caseTypeOptions.map((type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(type, style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat')),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedCaseType = value);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Sort by:', style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _caseSortField,
                  dropdownColor: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  iconEnabledColor: AppTheme.accentColor,
                  items: const [
                    DropdownMenuItem(value: 'Case Title', child: Text('Case Title', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'))),
                    DropdownMenuItem(value: 'Client', child: Text('Client', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'))),
                    DropdownMenuItem(value: 'Case Type', child: Text('Case Type', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'))),
                    DropdownMenuItem(value: 'Hearing Date', child: Text('Hearing Date', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'))),
                    DropdownMenuItem(value: 'Case ID', child: Text('Case ID', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'))),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _caseSortField = value);
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: Icon(_isSortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: AppTheme.accentColor),
              onPressed: () => setState(() => _isSortAscending = !_isSortAscending),
              tooltip: 'Toggle sort order',
            ),
            const Spacer(),
            if (filteredCases.isNotEmpty)
              Text('${filteredCases.length} results', style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 20),
        if (filteredCases.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'No case files match your search and case type filters.',
              style: TextStyle(fontFamily: 'Montserrat', fontSize: 13, color: AppTheme.textSecondary),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredCases.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final caseFile = filteredCases[index];
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.08)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _navigateToCaseDetails(caseFile),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(Icons.description_outlined, color: AppTheme.accentColor, size: 26),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _navigateToCaseDetails(caseFile),
                                    child: Text(
                                      caseFile['caseTitle'] ?? 'Untitled Case',
                                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    caseFile['caseId'] ?? '',
                                    style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.accentColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              caseFile['clientName'] ?? 'Unknown client',
                              style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _buildInfoChip(caseFile['caseType'] ?? 'Unknown'),
                                _buildInfoChip(caseFile['status'] ?? 'Status unknown'),
                                if (caseFile['hearingDate'] != null)
                                  _buildInfoChip('Hearing ${caseFile['hearingDate']}'),
                                if (caseFile['advocates'] != null)
                                  _buildInfoChip('Advocates: ${caseFile['advocates']}', accent: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.accentColor),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSharedChecklistCard({double minHeight = 0}) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in_outlined, color: AppTheme.accentColor, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Shared Chamber Checklist',
                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_task_rounded, size: 18, color: AppTheme.accentColor),
                onPressed: _showAddSharedTaskDialog,
                style: IconButton.styleFrom(backgroundColor: AppTheme.accentColor.withValues(alpha: 0.1)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sharedTasks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('No shared tasks added.', style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _sharedTasks.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = _sharedTasks[index];
                    final isCompleted = task['isCompleted'] == true;
                    return InkWell(
                      onTap: () => _showTaskDetailsDialog(index),
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
                                onChanged: (_) => _showTaskDetailsDialog(index),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task['title'],
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 11,
                                      color: isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
                                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Builder(builder: (ctx) {
                                    final adj = task['adjournedTo'] ?? '';
                                    final rem = task['remark'] ?? '';
                                    final deadlineStr = task['deadline'] ?? '';
                                    final meta = <Widget>[];
                                    if (adj != null && (adj as String).isNotEmpty) {
                                      String displayDate = '';
                                      try {
                                        displayDate = _formatDate(DateTime.parse(adj));
                                      } catch (_) {
                                        displayDate = adj;
                                      }
                                      meta.add(Text('Adjourned to $displayDate • ${task['adjournReason'] ?? ''}', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)));
                                    }
                                    if (deadlineStr != null && (deadlineStr as String).isNotEmpty) {
                                      String deadlineLabel = '';
                                      try {
                                        deadlineLabel = _formatDateTime(DateTime.parse(deadlineStr));
                                      } catch (_) {
                                        deadlineLabel = deadlineStr;
                                      }
                                      meta.add(Text('Due: $deadlineLabel', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)));
                                    }
                                    if (rem != null && (rem as String).isNotEmpty) {
                                      meta.add(Text('Remarks: $rem', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)));
                                    }
                                    if (meta.isEmpty) return const SizedBox.shrink();
                                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: meta);
                                  }),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 14, color: AppTheme.errorRed),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                final taskId = _sharedTasks[index]['id']?.toString();
                                if (taskId != null) {
                                  await TaskService.deleteTask(taskId);
                                }
                                await _loadSharedChecklist();
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

  void _showCaseManagementDialog() {
    final titleController = TextEditingController();
    final clientController = TextEditingController();
    final typeController = TextEditingController();
    DateTime? selectedHearing;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          Future<void> _addCase() async {
            final title = titleController.text.trim();
            final client = clientController.text.trim();
            final type = typeController.text.trim().isEmpty ? 'General' : typeController.text.trim();
            if (title.isEmpty || client.isEmpty) return;
            
            final newCase = {
              'client_name': client,
              'case_id': 'CU-2026-${100 + _clientCaseFiles.length + 1}',
              'case_title': title,
              'case_type': type,
              'status': 'Registered',
              'assigned_to': '',
              'hearing_date': selectedHearing == null ? '' : _formatDate(selectedHearing!),
              'advocates': '',
              'notes': '',
            };
            
            await CaseService.addCase(newCase);
            await _loadCases();
            
            titleController.clear();
            clientController.clear();
            typeController.clear();
            setState(() {});
          }

          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: SizedBox(
              width: 680,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Case Management', style: TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CLOSE'))
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Registration form
                  Row(
                    children: [
                      Expanded(
                        child: TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Case title', filled: true),),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(controller: clientController, decoration: const InputDecoration(labelText: 'Client name', filled: true),),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: ['Civil', 'Criminal', 'General', 'Other'].contains(typeController.text) ? typeController.text : (typeController.text.isEmpty ? 'Civil' : null),
                          decoration: const InputDecoration(labelText: 'Case type', filled: true),
                          items: ['Civil', 'Criminal', 'General', 'Other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) {
                            if (val != null) typeController.text = val;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(selectedHearing == null ? 'No hearing date' : _formatDate(selectedHearing!), style: const TextStyle(color: AppTheme.textSecondary))),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(context: context, initialDate: selectedHearing ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
                        if (picked != null) setState(() => selectedHearing = picked);
                      }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor), child: const Text('Pick Hearing Date')),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _addCase, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor), child: const Text('Register Case')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Case list with management actions
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _clientCaseFiles.length,
                      separatorBuilder: (context, i) => const Divider(color: Colors.transparent, height: 8),
                      itemBuilder: (context, i) {
                        final c = _clientCaseFiles[i];
                        String status = c['status'] ?? 'Registered';
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppTheme.secondaryColor, borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c['caseTitle'] ?? '', style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                  const SizedBox(height: 6),
                                  Text('${c['clientName'] ?? ''} • ${c['caseId'] ?? ''}', style: const TextStyle(color: AppTheme.textSecondary)),
                                  const SizedBox(height: 6),
                                  Text('Type: ${c['caseType'] ?? ''} • Hear: ${c['hearingDate'] ?? 'TBA'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                ]),
                              ),
                              const SizedBox(width: 12),
                              DropdownButton<String>(
                                value: const ['Registered', 'In Progress', 'Court Ordered', 'Completed'].contains(status) ? status : 'Registered',
                                items: const [
                                  DropdownMenuItem(value: 'Registered', child: Text('Registered')),
                                  DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                                  DropdownMenuItem(value: 'Court Ordered', child: Text('Court Ordered')),
                                  DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                                ],
                                onChanged: (val) async {
                                  if (val != null) {
                                    final dbId = _clientCaseFiles[i]['db_id'];
                                    if (dbId != null) {
                                      await CaseService.updateCase(dbId, {'status': val});
                                      await _loadCases();
                                      setState(() {});
                                    }
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.successGreen),
                                onPressed: () async {
                                  final dbId = _clientCaseFiles[i]['db_id'];
                                  if (dbId != null) {
                                    await CaseService.updateCase(dbId, {'status': 'Completed'});
                                    await _loadCases();
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _navigateToCaseDetails(Map<String, String> caseFile) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CaseDetailScreen(caseFile: caseFile),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  void _navigateToDocumentVault() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const DocumentListScreen(userEmail: 'manager@cochin.com'),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }


  Widget _buildCalendarCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: AppTheme.accentColor, size: 18),
              SizedBox(width: 8),
              Text(
                'Court & Consultation Scheduler',
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
              return InkWell(
                onTap: () => _showMeetingDetails(meeting),
                child: Padding(
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
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecentDocumentsCard({double minHeight = 0}) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: AppTheme.accentColor, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Newly Created Documents',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: _navigateToDocumentVault,
                style: TextButton.styleFrom(foregroundColor: AppTheme.accentColor),
                child: const Text('View all', style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _recentDocuments.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('No new documents created yet.', style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentDocuments.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final document = _recentDocuments[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.accentColor, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  document['title'] ?? 'Untitled Document',
                                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Created by ${document['createdBy']} • ${document['date']}',
                                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, color: AppTheme.textSecondary),
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

  void _showMeetingDetails(Map<String, dynamic> meeting) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.25)),
          ),
          title: Text(meeting['title']!, style: const TextStyle(fontFamily: 'Montserrat', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailField('Scheduled Time', meeting['time']!),
              const SizedBox(height: 10),
              _buildDetailField('Location / Venue', meeting['location']!),
              const SizedBox(height: 10),
              _buildDetailField('Advocate & Counsel Attendees', meeting['attendees']!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CLOSE', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showApprovalsDialog() {
    _loadPendingApprovals();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.25)),
            ),
            title: const Text('Chamber Roster Approvals', style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.textPrimary)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Approve timesheet hours and daily chamber billing slips.',
                    style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  // Type filter
                  Row(
                    children: [
                      const Text('Filter:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: 'All',
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All')),
                            DropdownMenuItem(value: 'draft', child: Text('Drafts')),
                            DropdownMenuItem(value: 'work', child: Text('Works')),
                            DropdownMenuItem(value: 'bill', child: Text('Bills')),
                          ],
                          onChanged: (v) {
                            final sel = v ?? 'All';
                            // filter _pendingApprovals locally by rebuilding the state
                            setState(() {
                              if (sel == 'All') {
                                // reload full list
                                _loadPendingApprovals();
                              } else {
                                _pendingApprovals = _pendingApprovals.where((a) => (a['type'] ?? '').toString().toLowerCase() == sel).toList();
                              }
                              });
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppTheme.secondaryColor,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_pendingApprovals.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No pending approvals', style: TextStyle(color: AppTheme.textSecondary))),
                    )
                  else
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Select all + bulk actions
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: _approvalSelected.isNotEmpty && _approvalSelected.values.every((v) => v),
                                      onChanged: (v) => _toggleSelectAll(v ?? false),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('Select all', style: TextStyle(color: AppTheme.textSecondary)),
                                  ],
                                ),
                                ElevatedButton(
                                  onPressed: _approvalSelected.values.any((v) => v) ? () async {
                                    await _approveSelected();
                                    setState(() {});
                                  } : null,
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                                  child: const Text('Approve Selected', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                                ),
                                OutlinedButton(
                                  onPressed: _pendingApprovals.isEmpty ? null : () async {
                                    final ok = await ApprovalService.approveAll();
                                    if (ok && mounted) {
                                      setState(() => _pendingApprovals.clear());
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.25))),
                                  child: const Text('Approve All', style: TextStyle(color: AppTheme.textPrimary)),
                                ),
                              ],
                            ),
                          ),
                          // Items
                          ..._pendingApprovals.map((item) {
                            final id = item['id'] ?? '';
                            final type = (item['type'] ?? '').toString();
                            final amount = item['amount'];
                            return Card(
                              color: AppTheme.surfaceColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.05))),
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _approvalSelected[id] ?? false,
                                      onChanged: (v) => setState(() => _approvalSelected[id] = v ?? false),
                                    ),
                                    const SizedBox(width: 8),
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: AppTheme.secondaryColor,
                                      child: Text(
                                        (item['title'] ?? '').toString().trim().split(' ').map((s) => s.isNotEmpty ? s[0] : '').take(2).join(),
                                        style: const TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['title'] ?? '', style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Expanded(child: Text(item['description'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
                                              const SizedBox(width: 8),
                                              if (amount != null)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                  decoration: BoxDecoration(color: AppTheme.secondaryColor, borderRadius: BorderRadius.circular(8)),
                                                  child: Text('₹${amount.toString()}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Chip(label: Text(type.isEmpty ? 'Unknown' : '${type[0].toUpperCase()}${type.substring(1)}', style: const TextStyle(color: AppTheme.textPrimary))),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      children: [
                                        ElevatedButton(
                                          onPressed: () async {
                                            await _approveApproval(id);
                                            setState(() {});
                                          },
                                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                          child: const Text('Approve', style: TextStyle(color: Colors.white)),
                                        ),
                                        const SizedBox(height: 6),
                                        OutlinedButton(
                                          onPressed: () async {
                                            await _rejectApproval(id);
                                            setState(() {});
                                          },
                                          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.redAccent.withOpacity(0.9))),
                                          child: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CLOSE', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: _pendingApprovals.isEmpty
                    ? null
                    : () async {
                        final ok = await ApprovalService.approveAll();
                        if (ok && mounted) {
                          setState(() => _pendingApprovals.clear());
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppTheme.successGreen,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              content: const Text(
                                'All outstanding chamber requests approved successfully.',
                                style: TextStyle(fontFamily: 'Montserrat', color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
                child: const Text('APPROVE ALL', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  

  Widget _buildDetailField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context, {bool isDrawer = false}) {
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
                Image.asset('assets/CUnitedGold.png', width: 32, height: 32),
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
                        'CHAMBER ADMINISTRATOR',
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
              child: const Row(
                children: [
                  Icon(Icons.admin_panel_settings_outlined, color: AppTheme.accentColor, size: 20),
                  SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'manager',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Chamber Administrator',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 9,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
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
                _buildSidebarLink(icon: Icons.grid_view_rounded, label: 'Dashboard', isActive: _activeSidebarIndex == 0, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  setState(() => _activeSidebarIndex = 0);
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.cases_rounded, label: 'Case Management', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CaseListScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.people_alt_rounded, label: 'Client Data', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ClientManagementScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.playlist_add_check_rounded, label: 'Today\'s Task', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ResponsiveScaffold(body: TaskManagementScreen())));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.calendar_month_rounded, label: 'Reminder Calendar', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CaseCalendarScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.folder_shared_rounded, label: 'Work File', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const WorkfileScreen()));
                }),
                
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text('FINANCE & DOCS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5)),
                ),
                _buildSidebarLink(icon: Icons.receipt_long_rounded, label: 'Billing', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const BillingScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.account_balance_wallet_rounded, label: 'Accounting & Pay', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const ExpenseScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.folder_shared_rounded, label: 'Added Documents', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddedDocumentsScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.cloud_sync, label: 'Google Docs Vault', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => DocumentListScreen(userEmail: widget.userEmail)));
                }),

                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text('MANAGEMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5)),
                ),
                _buildSidebarLink(icon: Icons.group_add_rounded, label: 'Staff Management', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const StaffManagementScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.rate_review_rounded, label: 'Verification', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const WorkManagementScreen(showOnlyVerification: true)));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.history_rounded, label: 'Verification History', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AuditHistoryScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.task_alt_rounded, label: 'Deliveries and Pickup', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const FileDeliveryScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.mark_email_unread_rounded, label: 'Post Register', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const InwardPostScreen(currentUserRole: 'Manager', currentUserName: 'Manager User')));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.handshake_rounded, label: 'File Acknowledgement', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const FileAcknowledgementScreen(currentUserRole: 'Manager', currentUserName: 'Manager User')));
                }),
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
                _buildSidebarLink(icon: Icons.chat_bubble_outline_rounded, label: 'Internal Chat', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const InternalStaffChatScreen(userEmail: 'manager@cochinunited.com')));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.table_view_rounded, label: 'Upload Table', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddedDocumentsScreen()));
                }),
                const SizedBox(height: 8),
                _buildSidebarLink(icon: Icons.settings_rounded, label: 'Settings', isActive: false, onTap: () {
                  if (isDrawer) Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AutomationSettingsScreen()));
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

  void _showAssignTaskDialog(Map<String, dynamic> staff) {
    final TextEditingController taskController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: Text(
            'Assign Checklist Task to ${staff['staffName']}',
            style: const TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: TextField(
            controller: taskController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Enter task description...',
              hintStyle: TextStyle(color: AppTheme.textSecondary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.textSecondary)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat')),
            ),
            ElevatedButton(
              onPressed: () async {
                final taskTitle = taskController.text.trim();
                if (taskTitle.isNotEmpty) {
                  final newTask = Task(
                    id: Task.generateId(),
                    title: taskTitle,
                    assignedTo: staff['staffName'],
                    createdAt: DateTime.now(),
                    lastUpdated: DateTime.now(),
                  );
                  await TaskService.addTask(newTask);
                  await _loadSharedChecklist();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Task assigned to ${staff['staffName']}')),
                    );
                    Navigator.pop(context);
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
              child: const Text('ASSIGN', style: TextStyle(color: AppTheme.primaryColor, fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebarLink({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    Color? color,
  }) {
    final displayColor = color ?? (isActive ? const Color(0xFF0F172A) : const Color(0xFF475569));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0F172A).withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: const Color(0xFF0F172A).withValues(alpha: 0.12), width: 1.2)
              : null,
        ),
        child: Row(
          children: [
            if (isActive)
              Container(
                width: 3.5,
                height: 18,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Icon(
              icon,
              color: isActive ? const Color(0xFF0F172A) : displayColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: displayColor,
                  letterSpacing: isActive ? 0.2 : 0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


