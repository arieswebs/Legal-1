import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/case_service.dart';
import '../services/user_service.dart';
import '../services/task_service.dart';
import '../models/task_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/role_service.dart';
import '../models/expense_model.dart';
import '../services/expense_service.dart';
import '../screens/expense_screen.dart';
import '../services/auth_service.dart';
import 'package:intl/intl.dart';
import 'workfile_wizard_screen.dart';

class WorkfileDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> workfile;

  const WorkfileDetailsDialog({super.key, required this.workfile});

  @override
  State<WorkfileDetailsDialog> createState() => _WorkfileDetailsDialogState();
}

class _WorkfileDetailsDialogState extends State<WorkfileDetailsDialog> {
  List<dynamic> _connectedFiles = [];
  Map<String, String> _userEmailToName = {};
  bool _isLoadingUsers = true;
  List<ExpenseModel> _caseExpenses = [];
  bool _isLoadingExpenses = true;
  String _currentUserRole = 'Staff';

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    _parseFiles();
    _fetchUsers();
    _fetchExpenses();
  }

  Future<void> _fetchUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currentUserRole = prefs.getString('user_role') ?? 'Staff';
      });
    }
  }

  Future<void> _fetchExpenses() async {
    final caseId = widget.workfile['id']?.toString() ?? widget.workfile['case_id']?.toString() ?? '';
    if (caseId.isEmpty) {
      if (mounted) setState(() => _isLoadingExpenses = false);
      return;
    }
    try {
      final allExpenses = await ExpenseService.getExpenses();
      final caseExpenses = allExpenses.where((e) => e.linkedCaseId == caseId).toList();
      if (mounted) {
        setState(() {
          _caseExpenses = caseExpenses;
          _isLoadingExpenses = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingExpenses = false);
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final users = await UserService.getAllUsers();
      final Map<String, String> map = {};
      for (var u in users) {
        if (u['email'] != null) {
          map[u['email'].toString().toLowerCase().trim()] = u['name'] ?? u['email'];
        }
      }
      if (mounted) {
        setState(() {
          _userEmailToName = map;
          _isLoadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  void _parseFiles() {
    if (widget.workfile['case_description'] != null) {
      try {
        final map = jsonDecode(widget.workfile['case_description']);
        if (map['vault_documents'] != null) {
          _connectedFiles = map['vault_documents'];
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    String workfileNo = '';
    String year = '';
    String court = '';
    String clientStatus = '';
    if (widget.workfile['case_description'] != null) {
      try {
        final map = jsonDecode(widget.workfile['case_description']);
        workfileNo = map['workfile_no']?.toString() ?? '';
        year = map['year']?.toString() ?? map['case_year']?.toString() ?? '';
        court = map['court']?.toString() ?? map['court_name']?.toString() ?? '';
        clientStatus = map['client_status']?.toString() ?? '';
      } catch (_) {}
    }
    if (year.isEmpty) {
      year = (widget.workfile['year'] ?? widget.workfile['case_year'] ?? '').toString();
    }
    if (court.isEmpty) {
      court = (widget.workfile['court_details'] ?? widget.workfile['court_name'] ?? widget.workfile['court'] ?? '').toString();
    }
    if (clientStatus.isEmpty) {
      clientStatus = (widget.workfile['client_status'] ?? '').toString();
    }

    final title = widget.workfile['case_title'] ?? widget.workfile['title'] ?? 'Untitled Workfile';
    final caseId = widget.workfile['id']?.toString() ?? widget.workfile['case_id']?.toString() ?? '';
    final clientName = widget.workfile['client_name'] ?? 'Unknown';
    final type = widget.workfile['case_type'] ?? 'N/A';
    final status = widget.workfile['case_status'] ?? 'Open';
    
    String staff = 'Unknown';
    if (widget.workfile['responsible_staff'] != null) {
      final staffList = List<String>.from(widget.workfile['responsible_staff']);
      if (_isLoadingUsers) {
        staff = 'Loading...';
      } else {
        staff = staffList.map((email) {
          final cleanEmail = email.toLowerCase().trim();
          return _userEmailToName[cleanEmail] ?? email;
        }).join(', ');
      }
    }
    
    final bool isOpen = status.toString().toLowerCase() == 'open';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 650,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              spreadRadius: 10,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(bottom: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.1))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primaryColor.withValues(alpha: 0.2),
                                    AppTheme.accentColor.withValues(alpha: 0.1),
                                  ],
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                              ),
                              child: const Icon(Icons.folder_open_rounded, color: AppTheme.primaryColor, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontFamily: 'Cinzel',
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          '#${workfileNo.isNotEmpty ? workfileNo : 'N/A'}',
                                          style: const TextStyle(
                                            fontFamily: 'Montserrat',
                                            color: AppTheme.primaryColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildStatusBadge(status, isOpen),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, color: AppTheme.primaryColor),
                            tooltip: 'Edit Case',
                            onPressed: () {
                              Navigator.pop(context);
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: const EdgeInsets.all(24),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 800),
                                    child: WorkfileWizardScreen(existingWorkfile: widget.workfile),
                                  ),
                                ),
                              );
                            },
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          if (RoleService.canDeleteCases(_currentUserRole))
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
                              tooltip: 'Delete Case',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Case', style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold, fontFamily: 'Montserrat')),
                                    content: const Text('Are you sure you want to delete this case? This action cannot be undone.', style: TextStyle(fontFamily: 'Montserrat')),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat')),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
                                        child: const Text('Delete', style: TextStyle(color: Colors.white, fontFamily: 'Montserrat')),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  try {
                                    final caseId = widget.workfile['id']?.toString() ?? widget.workfile['case_id']?.toString() ?? '';
                                    if (caseId.isNotEmpty) {
                                      await CaseService.deleteCase(caseId);
                                      if (mounted) {
                                        Navigator.pop(context);
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete case: $e'), backgroundColor: AppTheme.errorRed));
                                    }
                                  }
                                }
                              },
                              hoverColor: AppTheme.errorRed.withValues(alpha: 0.1),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                            onPressed: () => Navigator.pop(context),
                            hoverColor: AppTheme.errorRed.withValues(alpha: 0.1),
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Content Section
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info Grid
                    Row(
                      children: [
                        Expanded(child: _buildInfoCard(Icons.person_outline_rounded, 'Client', clientName)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildInfoCard(Icons.category_outlined, 'Type', type)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildInfoCard(Icons.calendar_month_rounded, 'Filing Year', year.isNotEmpty ? year : 'N/A')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildInfoCard(Icons.account_balance_rounded, 'Court', court.isNotEmpty ? court : 'N/A')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildInfoCard(Icons.verified_user_outlined, 'Client Status', clientStatus.isNotEmpty ? clientStatus : status)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildInfoCard(Icons.badge_outlined, 'Handled By', staff.isEmpty ? 'Unknown' : staff)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildInfoCard(Icons.account_circle_outlined, 'Created By', widget.workfile['created_by'] ?? 'Unknown')),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.history_rounded,
                            label: 'History',
                            color: AppTheme.accentColor,
                            onTap: () {
                              _showHistoryDialog(context, caseId);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildActionButton(
                            icon: staff == 'Unknown' || staff.isEmpty ? Icons.person_add_alt_1_rounded : Icons.swap_horiz_rounded,
                            label: staff == 'Unknown' || staff.isEmpty ? 'Assign Staff' : 'Handover',
                            color: staff == 'Unknown' || staff.isEmpty ? Colors.blueAccent : Colors.deepOrangeAccent,
                            onTap: () {
                              _showHandoverDialog(context, caseId, widget.workfile['responsible_staff']);
                            },
                          ),
                        ),
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(color: Colors.white10),
                    ),

                    // Sub Works Section
                    _buildSectionHeader(
                      title: 'Sub Works',
                      icon: Icons.account_tree_rounded,
                      actionLabel: 'Add Sub Work',
                      onAction: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Coming Soon'),
                            content: const Text('Add Sub Work feature is currently under development.'),
                            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: const Center(
                        child: Text(
                          'No sub works found.',
                          style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Connected Files Section
                    _buildSectionHeader(
                      title: 'Connected Files',
                      icon: Icons.attach_file_rounded,
                      actionLabel: 'Add File',
                      onAction: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Coming Soon'),
                            content: const Text('Add File feature is currently under development.'),
                            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_connectedFiles.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: const Center(
                          child: Text(
                            'No connected files.',
                            style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _connectedFiles.length,
                        itemBuilder: (context, index) {
                          final file = _connectedFiles[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.cloud_done_rounded, color: AppTheme.primaryColor, size: 20),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        file['file_name'] ?? 'Unknown File',
                                        style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 14),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Work Document',
                                        style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.download_rounded, color: AppTheme.accentColor, size: 20),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Coming Soon'),
                                        content: const Text('Download feature is currently under development.'),
                                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                      ),
                                    );
                                  },
                                  tooltip: 'Download',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed, size: 20),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Coming Soon'),
                                        content: const Text('Remove feature is currently under development.'),
                                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                      ),
                                    );
                                  },
                                  tooltip: 'Remove',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    
                    const SizedBox(height: 32),

                    // Expenses Section
                    _buildSectionHeader(
                      title: 'Expenses',
                      icon: Icons.receipt_long_rounded,
                      actionLabel: 'Add Expense',
                      onAction: () async {
                        final userName = await AuthService().getUserName();
                        final caseId = widget.workfile['id']?.toString() ?? widget.workfile['case_id']?.toString() ?? '';
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (context) => AddTransactionDialog(
                            currentUserName: (userName != null && userName.isNotEmpty) ? userName : 'Staff',
                            initialCaseId: caseId.isNotEmpty ? caseId : null,
                            lockCaseSelection: true,
                            onAdded: () {
                              _fetchExpenses();
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingExpenses)
                      const Center(child: CircularProgressIndicator())
                    else if (_caseExpenses.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: const Center(
                          child: Text(
                            'No expenses recorded.',
                            style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _caseExpenses.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final expense = _caseExpenses[index];
                          final bool isIncome = expense.type == TransactionType.income;
                          final color = isIncome ? AppTheme.successGreen : AppTheme.errorRed;
                          final icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
                          final sign = isIncome ? '+' : '-';
                          final fmt = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
                          
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon, color: color, size: 20),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        expense.title,
                                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${expense.category} • ${DateFormat('MMM dd, yyyy').format(expense.date)}',
                                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '$sign${fmt.format(expense.amount)}',
                                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.bold, color: color),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, String caseId) {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<Task>>(
          future: TaskService.getTasksByCase(caseId),
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? [];
            return AlertDialog(
              backgroundColor: AppTheme.backgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.2))),
              title: const Text('Workfile History', style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                    : tasks.isEmpty
                        ? const Center(child: Text('No works found for this case.', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary)))
                        : ListView.builder(
                            itemCount: tasks.length,
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              return ListTile(
                                leading: Icon(task.isCompleted ? Icons.check_circle : Icons.pending, color: task.isCompleted ? AppTheme.successGreen : AppTheme.accentColor),
                                title: Text(task.title, style: const TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                                subtitle: Text('Assigned to: ${task.assignedTo}\nStatus: ${task.isCompleted ? "Completed" : "Pending"}', style: const TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary, fontSize: 12)),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHandoverDialog(BuildContext context, String caseId, dynamic currentStaffData) {
    List<String> currentStaffEmails = [];
    if (currentStaffData is List) {
      currentStaffEmails = List<String>.from(currentStaffData.map((e) => e.toString()));
    }
    
    final staffFuture = UserService.getAllUsers();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: staffFuture,
              builder: (context, snapshot) {
                final staffList = snapshot.data ?? [];
                
                return AlertDialog(
                  backgroundColor: AppTheme.backgroundColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.2))),
                  title: Text(currentStaffEmails.isEmpty ? 'Assign Staff' : 'Handover Workfile', style: const TextStyle(fontFamily: 'Cinzel', color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                        : staffList.isEmpty
                            ? const Center(child: Text('No staff found.', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary)))
                            : SingleChildScrollView(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: staffList.map((staff) {
                                    final email = staff['email'] as String? ?? '';
                                    final name = staff['name'] as String? ?? email;
                                    final isSelected = currentStaffEmails.contains(email);
                                    
                                    return FilterChip(
                                      label: Text(name, style: TextStyle(fontFamily: 'Montserrat', color: isSelected ? Colors.black : AppTheme.textPrimary)),
                                      selected: isSelected,
                                      selectedColor: AppTheme.primaryColor,
                                      backgroundColor: AppTheme.surfaceColor,
                                      checkmarkColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: isSelected ? AppTheme.primaryColor : Colors.white24),
                                      ),
                                      onSelected: (bool selected) {
                                        setStateDialog(() {
                                          if (selected) {
                                            currentStaffEmails.add(email);
                                          } else {
                                            currentStaffEmails.remove(email);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        await CaseService.updateCase(caseId, {'responsible_staff': currentStaffEmails});
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(currentStaffEmails.isEmpty ? 'Staff updated successfully' : 'Workfile handed over successfully')));
                        }
                      },
                      child: Text(currentStaffEmails.isEmpty ? 'Save' : 'Save Handover', style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              },
            );
          }
        );
      },
    );
  }

  Widget _buildStatusBadge(String status, bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOpen ? AppTheme.successGreen.withValues(alpha: 0.1) : AppTheme.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isOpen ? AppTheme.successGreen.withValues(alpha: 0.3) : AppTheme.textSecondary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOpen ? AppTheme.successGreen : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              fontFamily: 'Montserrat',
              color: isOpen ? AppTheme.successGreen : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.8), fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Tooltip(
                  message: value,
                  child: Text(
                    value,
                    style: const TextStyle(fontFamily: 'Montserrat', fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required IconData icon, required String actionLabel, required VoidCallback onAction}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.textPrimary),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(fontFamily: 'Montserrat', fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add_rounded, size: 18, color: AppTheme.primaryColor),
          label: Text(actionLabel, style: const TextStyle(color: AppTheme.primaryColor, fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}
