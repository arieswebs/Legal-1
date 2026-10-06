import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../services/auth_service.dart';
import '../services/case_service.dart';
import 'task_detail_screen.dart';
import '../services/user_service.dart';
import '../utils/display_name_helper.dart';
import '../widgets/responsive.dart';

class TaskManagementScreen extends StatefulWidget {
  final String? initialStatus;
  final String? linkedCaseId;
  const TaskManagementScreen({super.key, this.initialStatus, this.linkedCaseId});

  @override
  State<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends State<TaskManagementScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _currentUserEmail;
  String _searchQuery = '';
  String _statusFilter = 'All'; // 'All', 'Pending', 'Completed', 'High Priority', 'Overdue'
  
  List<Task> _myTasks = [];
  List<Task> _delegatedTasks = [];
  List<Task> _allTasks = [];
  
  List<Map<String, dynamic>> _allUsers = [];
  Map<String, String> _staffMap = {};
  List<Map<String, dynamic>> _registeredCases = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null) {
      _statusFilter = widget.initialStatus!;
    }
    _tabController = TabController(length: 2, vsync: this);
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final auth = AuthService();
    final role = await auth.getUserRole();
    final email = await auth.getUserEmail();
    
    final bool isAdminRole = role == 'admin' || role == 'manager';
    
    if (mounted) {
      setState(() {
        _isAdmin = isAdminRole;
        _currentUserEmail = email;
        _tabController.dispose();
        _tabController = TabController(length: _isAdmin ? 3 : 2, vsync: this);
        _tabController.addListener(() {
          if (mounted) setState(() {});
        });
      });
    }
    
    try {
      final realUsers = await UserService.getAllUsers();
      final Map<String, String> staffMap = {};
      for (var u in realUsers) {
        final uEmail = (u['email'] ?? '').toString().toLowerCase().trim();
        final username = (u['username'] ?? '').toString().toLowerCase().trim();
        final name = (u['name'] ?? u['username'] ?? u['email'] ?? '').toString().trim();

        if (name.isNotEmpty) {
          if (uEmail.isNotEmpty) {
            staffMap[uEmail] = name;
            final prefix = uEmail.split('@')[0];
            if (prefix.isNotEmpty) staffMap[prefix] = name;
          }
          if (username.isNotEmpty) staffMap[username] = name;
        }
      }

      if (mounted) {
        setState(() {
          _staffMap = staffMap;
          _allUsers = realUsers.isNotEmpty 
              ? realUsers.where((u) => u['is_active'] != false).toList()
              : [
                  {'email': 'admin@cochinunited.com', 'name': 'Admin'},
                  {'email': 'manager@cochinunited.com', 'name': 'Manager'},
                ];
        });
      }
    } catch (e) {
      debugPrint('Error fetching users for tasks: $e');
    }
    
    await _fetchRegisteredCases();
    await _fetchTasks();
  }

  Future<void> _fetchRegisteredCases() async {
    try {
      final cases = await CaseService.getCases();
      if (mounted) {
        setState(() {
          _registeredCases = cases;
        });
      }
    } catch (e) {
      debugPrint('Error fetching registered cases for picker: $e');
    }
  }

  void _showCasePickerModal(void Function(Map<String, dynamic>?) onSelectCase) {
    String searchQ = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setPickerState) {
          final q = searchQ.toLowerCase().trim();
          final filteredCases = _registeredCases.where((c) {
            if (q.isEmpty) return true;
            final title = (c['case_title'] ?? c['title'] ?? '').toString().toLowerCase();
            final caseNo = (c['court_case_number'] ?? c['case_number'] ?? c['id'] ?? '').toString().toLowerCase();
            final client = (c['client_name'] ?? '').toString().toLowerCase();
            return title.contains(q) || caseNo.contains(q) || client.contains(q);
          }).toList();

          final recentCases = _registeredCases.take(5).toList();

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 600),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Icon(Icons.folder_open_rounded, color: Color(0xFF0F172A), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Linked Case',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const Text(
                              'Recent & registered matter files',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      onChanged: (v) => setPickerState(() => searchQ = v),
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13.5, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Search cases by title, CNR, client name...',
                        hintStyle: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                        suffixIcon: searchQ.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF64748B)),
                                onPressed: () => setPickerState(() => searchQ = ''),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: () {
                      onSelectCase(null);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.remove_circle_outline_rounded, size: 16, color: Color(0xFF64748B)),
                          SizedBox(width: 10),
                          Text(
                            'No Linked Case (Unlink)',
                            style: TextStyle(fontFamily: 'Montserrat', fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (searchQ.isEmpty && recentCases.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'RECENT CASES',
                                style: TextStyle(fontFamily: 'Montserrat', fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.6),
                              ),
                            ),
                            ...recentCases.map((c) => _buildCaseTile(c, isRecent: true, onSelect: (c) {
                              onSelectCase(c);
                              Navigator.pop(context);
                            })),
                            const SizedBox(height: 8),
                          ],

                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              searchQ.isEmpty ? 'ALL CASES' : 'RESULTS (${filteredCases.length})',
                              style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.6),
                            ),
                          ),
                          if (filteredCases.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  'No matching cases found',
                                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 13, color: Color(0xFF94A3B8)),
                                ),
                              ),
                            )
                          else
                            ...filteredCases.map((c) => _buildCaseTile(c, isRecent: false, onSelect: (c) {
                              onSelectCase(c);
                              Navigator.pop(context);
                            })),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaseTile(Map<String, dynamic> c, {required bool isRecent, required void Function(Map<String, dynamic>) onSelect}) {
    final title = c['case_title'] ?? c['title'] ?? 'Untitled Case';
    final caseNo = c['court_case_number'] ?? c['case_number'] ?? c['id'] ?? 'CU-REG';
    final client = c['client_name'] ?? 'Direct Client';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => onSelect(c),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    title.toString().isNotEmpty ? title.toString()[0].toUpperCase() : 'C',
                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toString(),
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: $caseNo • Client: $client',
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: Color(0xFF64748B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  String _getStaffName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return DisplayNameHelper.overrideName('Unassigned');
    String clean = raw.trim().replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').replaceAll("'", '');
    if (clean.contains(',')) {
      return clean.split(',').map((e) => _getSingleStaffName(e)).join(', ');
    }
    return _getSingleStaffName(clean);
  }

  String _getSingleStaffName(String clean) {
    clean = clean.trim();
    final cleanLower = clean.toLowerCase();
    if (_staffMap.containsKey(cleanLower)) return DisplayNameHelper.overrideName(_staffMap[cleanLower]!);
    if (cleanLower.contains('@')) {
      final p = cleanLower.split('@')[0];
      return DisplayNameHelper.overrideName(p[0].toUpperCase() + p.substring(1));
    }
    final parts = clean.split(RegExp(r'[._\-]'));
    return DisplayNameHelper.overrideName(parts.where((p) => p.isNotEmpty).map((p) => p[0].toUpperCase() + p.substring(1)).join(' '));
  }

  Future<void> _fetchTasks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final tasks = await TaskService.getTasks();
      
      if (mounted) {
        setState(() {
          _allTasks = tasks;
          if (_currentUserEmail != null) {
            final emailLower = _currentUserEmail!.toLowerCase();
            final staffName = emailLower.split('@')[0];
            
            _myTasks = tasks.where((t) {
              final assignedTo = (t.assignedTo ?? '').toLowerCase().trim();
              return assignedTo == emailLower ||
                     assignedTo == staffName ||
                     assignedTo.contains('all') ||
                     assignedTo.contains(staffName) ||
                     (staffName.contains(assignedTo) && assignedTo.isNotEmpty);
            }).toList();

            _delegatedTasks = tasks.where((t) {
              final createdBy = (t.createdBy ?? '').toLowerCase().trim();
              return createdBy == emailLower ||
                     createdBy == staffName ||
                     createdBy.contains(staffName) ||
                     (staffName.contains(createdBy) && createdBy.isNotEmpty);
            }).toList();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Task> _applyFilters(List<Task> rawTasks) {
    return rawTasks.where((t) {
      if (widget.linkedCaseId != null && t.caseId != widget.linkedCaseId) return false;
      final q = _searchQuery.toLowerCase();
      final title = t.title.toLowerCase();
      final remark = (t.remark ?? '').toLowerCase();
      final caseId = (t.caseId ?? '').toLowerCase();
      final assignee = _getStaffName(t.assignedTo).toLowerCase();
      
      final matchesSearch = q.isEmpty ||
          title.contains(q) ||
          remark.contains(q) ||
          caseId.contains(q) ||
          assignee.contains(q);
      
      if (!matchesSearch) return false;
      
      if (_statusFilter == 'Pending') return !t.isCompleted;
      if (_statusFilter == 'Completed') return t.isCompleted;
      if (_statusFilter == 'High Priority') {
        final p = t.priority.toLowerCase();
        return p == 'high' || p == 'critical';
      }
      if (_statusFilter == 'Overdue') return t.isOverdue();
      
      return true;
    }).toList();
  }

  Future<void> _deleteTask(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Task', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
        content: const Text('Are you sure you want to delete this task assignment?', style: TextStyle(fontFamily: 'Montserrat', color: Color(0xFF475569))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      )
    );
    if (ok == true) {
      await TaskService.deleteTask(id);
      _fetchTasks();
    }
  }

  void _showAssigneePickerModal(List<String> currentSelected, void Function(List<String>) onApply) {
    List<String> tempSelected = List.from(currentSelected);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setPickerState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Select Assignees', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 16)),
            content: SizedBox(
              width: 300,
              height: 400,
              child: ListView(
                children: _allUsers.map((u) {
                  final email = u['email'] as String;
                  final name = u['name'].toString();
                  return CheckboxListTile(
                    title: Text(name, style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13.5)),
                    value: tempSelected.contains(email),
                    onChanged: (bool? checked) {
                      setPickerState(() {
                        if (checked == true) {
                          tempSelected.add(email);
                        } else {
                          tempSelected.remove(email);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL', style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () {
                  onApply(tempSelected);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('APPLY', style: TextStyle(color: Color(0xFFB8860B), fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTaskDialog([Task? task]) {
    final titleCtrl = TextEditingController(text: task?.title);
    final remarkCtrl = TextEditingController(text: task?.remark);
    final caseIdCtrl = TextEditingController(text: task?.caseId ?? widget.linkedCaseId);
    String priority = task?.priority ?? 'Medium';
    List<String> assignedToList = task?.assignedTo?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? [];
    DateTime? deadline = task?.deadline ?? DateTime.now().add(const Duration(days: 1));

    Widget buildStyledTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1}) {
      return TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Montserrat', fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontSize: 12.5),
          prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 18),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
    }

    Widget buildStyledDropdown<T>({required T? value, required String label, required IconData icon, required List<DropdownMenuItem<T>> items, required void Function(T?) onChanged}) {
      return DropdownButtonFormField<T>(
        initialValue: value,
        dropdownColor: Colors.white,
        style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Montserrat', fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontSize: 12.5),
          prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 18),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        items: items,
        onChanged: onChanged,
      );
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: 560,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            task == null ? Icons.add_task_rounded : Icons.edit_note_rounded,
                            color: const Color(0xFFD4AF37),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          task == null ? 'Assign New Task' : 'Edit Task Details',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    buildStyledTextField(titleCtrl, 'Task Title', Icons.title_rounded),
                    const SizedBox(height: 12),
                    buildStyledTextField(remarkCtrl, 'Instructions / Remarks', Icons.notes_rounded, maxLines: 3),
                    const SizedBox(height: 12),
                    
                    InkWell(
                      onTap: () {
                        _showCasePickerModal((selectedCase) {
                          setModalState(() {
                            if (selectedCase == null) {
                              caseIdCtrl.clear();
                            } else {
                              final cTitle = (selectedCase['case_title'] ?? selectedCase['title'] ?? '').toString();
                              final cId = (selectedCase['court_case_number'] ?? selectedCase['case_number'] ?? selectedCase['id'] ?? '').toString();
                              caseIdCtrl.text = cTitle.isNotEmpty ? '$cTitle ($cId)' : cId;
                            }
                          });
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: caseIdCtrl.text.isNotEmpty ? const Color(0xFFF8FAFC) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: caseIdCtrl.text.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              color: caseIdCtrl.text.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                caseIdCtrl.text.isNotEmpty
                                    ? 'Case: ${caseIdCtrl.text}'
                                    : 'Link Case File (Optional)',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 13,
                                  fontWeight: caseIdCtrl.text.isNotEmpty ? FontWeight.w600 : FontWeight.w500,
                                  color: caseIdCtrl.text.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (caseIdCtrl.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                                onPressed: () {
                                  setModalState(() {
                                    caseIdCtrl.clear();
                                  });
                                },
                              )
                            else
                              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B), size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    buildStyledDropdown<String>(
                      value: priority,
                      label: 'Priority Level',
                      icon: Icons.priority_high_rounded,
                      items: ['Low', 'Medium', 'High', 'Critical'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setModalState(() => priority = v!),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        _showAssigneePickerModal(assignedToList, (newList) {
                          setModalState(() {
                            assignedToList = newList;
                          });
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.group_add_rounded, color: Color(0xFF64748B), size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                assignedToList.isNotEmpty
                                    ? 'Assigned: ${assignedToList.map((e) => _getStaffName(e)).join(', ')}'
                                    : 'Select Assignees (Required)',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 13,
                                  fontWeight: assignedToList.isNotEmpty ? FontWeight.w600 : FontWeight.w500,
                                  color: assignedToList.isNotEmpty ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (assignedToList.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                                onPressed: () {
                                  setModalState(() {
                                    assignedToList.clear();
                                  });
                                },
                              )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: deadline!,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null && context.mounted) {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(deadline!),
                          );
                          if (t != null) {
                            setModalState(() => deadline = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_rounded, color: Color(0xFF64748B), size: 18),
                            const SizedBox(width: 12),
                            Text(
                              'Due: ${deadline != null ? DateFormat('dd MMM yyyy, hh:mm a').format(deadline!) : 'Not Set'}',
                              style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                            ),
                            const Spacer(),
                            const Icon(Icons.edit_calendar_rounded, color: Color(0xFF64748B), size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(fontFamily: 'Montserrat', color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            if (titleCtrl.text.isEmpty || assignedToList.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide task title and select at least one assignee')));
                              return;
                            }
                            
                            final assignedTo = assignedToList.join(', ');
                            
                            if (task == null) {
                              final newTask = Task(
                                id: Task.generateId(),
                                title: titleCtrl.text,
                                remark: remarkCtrl.text,
                                caseId: caseIdCtrl.text.isEmpty ? null : caseIdCtrl.text,
                                isRelatedToCase: caseIdCtrl.text.isNotEmpty,
                                priority: priority,
                                assignedTo: assignedTo,
                                deadline: deadline,
                                createdAt: DateTime.now(),
                                lastUpdated: DateTime.now(),
                                createdBy: _currentUserEmail,
                                isCompleted: false
                              );
                              await TaskService.addTask(newTask);
                            } else {
                              final updatedTask = task.copyWith(
                                title: titleCtrl.text,
                                remark: remarkCtrl.text,
                                caseId: caseIdCtrl.text.isEmpty ? null : caseIdCtrl.text,
                                isRelatedToCase: caseIdCtrl.text.isNotEmpty,
                                priority: priority,
                                assignedTo: assignedTo,
                                deadline: deadline,
                              );
                              await TaskService.updateTask(task.id, updatedTask);
                            }
                            
                            if (context.mounted) Navigator.pop(context);
                            _fetchTasks();
                          },
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Save Task'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: const Color(0xFFD4AF37),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            _buildTopCommandHeader(),

            // Main View Area
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchTasks,
                color: const Color(0xFF0F172A),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Analytics Bar
                      if (!_isLoading) ...[
                        _buildAnalyticsGrid(),
                        const SizedBox(height: 24),
                      ],

                      // Controls Bar (Search + Segmented Tabs + Filter Chips)
                      _buildControlsRow(),
                      const SizedBox(height: 20),

                      // Task Content List View Area
                      if (_isLoading)
                        _buildLoadingState()
                      else
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.60,
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildTaskList(_myTasks, isMyTask: true),
                              _buildTaskList(_delegatedTasks, isMyTask: false),
                              if (_isAdmin) _buildTaskList(_allTasks, isMyTask: false),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 1. Elegant Header Bar ───
  Widget _buildTopCommandHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Back Button
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 18),
            ),
          ),
          const SizedBox(width: 16),

          // Title & Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Task Management',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Cochin United Legal LLP • Assignments & Delegation',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Refresh Button
          IconButton(
            onPressed: _fetchTasks,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 20),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),

          // Primary Assign Task Button
          ElevatedButton.icon(
            onPressed: () => _showTaskDialog(),
            icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xFFD4AF37)),
            label: const Text(
              'Assign Task',
              style: TextStyle(
                fontFamily: 'Montserrat',
                color: Color(0xFFD4AF37),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2. Clean Analytics Grid ───
  Widget _buildAnalyticsGrid() {
    final pendingCount = _myTasks.where((t) => !t.isCompleted).length;
    final delegatedCount = _delegatedTasks.length;
    final overdueCount = _myTasks.where((t) => t.isOverdue()).length;

    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'My Pending Tasks',
            count: '$pendingCount',
            subtitle: 'Assignments awaiting action',
            icon: Icons.pending_actions_rounded,
            accentColor: const Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'Delegated Tasks',
            count: '$delegatedCount',
            subtitle: 'Assigned out to staff',
            icon: Icons.assignment_ind_rounded,
            accentColor: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'Overdue Tasks',
            count: '$overdueCount',
            subtitle: 'Past scheduled deadline',
            icon: Icons.error_outline_rounded,
            accentColor: const Color(0xFFDC2626),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String count,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 3. Controls Row (Search, Tabs, Status Filter) ───
  Widget _buildControlsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Search Input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Montserrat', fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search tasks by title, remark, case ID, or staff...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Montserrat', fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF64748B)),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Tab Switcher
            _buildSegmentedTabBar(),
          ],
        ),
        const SizedBox(height: 14),
        
        // Status Filters Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text(
                'Filter:',
                style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              ...['All', 'Pending', 'Completed', 'High Priority', 'Overdue'].map((f) {
                final isSelected = _statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _statusFilter = f),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedTabBar() {
    final tabs = [
      'My Tasks',
      'Delegated Tasks',
      if (_isAdmin) 'All Tasks',
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(tabs.length, (index) {
          final isSelected = _tabController.index == index;
          return InkWell(
            onTap: () {
              _tabController.animateTo(index);
              setState(() {});
            },
            borderRadius: BorderRadius.circular(9),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                tabs[index],
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── 4. Task List Renderer ───
  Widget _buildTaskList(List<Task> rawTasks, {required bool isMyTask}) {
    final tasks = _applyFilters(rawTasks);

    if (tasks.isEmpty) {
      return _buildEmptyState(isMyTask);
    }

    return ListView.separated(
      itemCount: tasks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final t = tasks[index];
        final isCompleted = t.isCompleted;
        final assignedName = _getStaffName(t.assignedTo);

        Color priorityBg = const Color(0xFFF8FAFC);
        Color priorityText = const Color(0xFF475569);
        Color priorityBorder = const Color(0xFFE2E8F0);

        final pLower = t.priority.toLowerCase();
        if (pLower == 'critical') {
          priorityBg = const Color(0xFFFEF2F2);
          priorityText = const Color(0xFFDC2626);
          priorityBorder = const Color(0xFFFCA5A5);
        } else if (pLower == 'high') {
          priorityBg = const Color(0xFFFEF3C7);
          priorityText = const Color(0xFFB45309);
          priorityBorder = const Color(0xFFF59E0B);
        } else if (pLower == 'medium') {
          priorityBg = const Color(0xFFF8FAFC);
          priorityText = const Color(0xFF475569);
          priorityBorder = const Color(0xFFE2E8F0);
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TaskDetailScreen(
                      task: t,
                      onStatusUpdate: _fetchTasks,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Check Ring
                    GestureDetector(
                      onTap: () async {
                        await TaskService.updateTaskStatus(t.id, !t.isCompleted);
                        _fetchTasks();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: isCompleted ? const Color(0xFF16A34A) : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                            width: 1.5,
                          ),
                        ),
                        child: isCompleted
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isCompleted ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (t.remark != null && t.remark!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              t.remark!,
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 12.5,
                                color: Color(0xFF64748B),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 10),

                          // Badges Row
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Priority
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: priorityBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: priorityBorder),
                                ),
                                child: Text(
                                  t.priority.toUpperCase(),
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: priorityText,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),

                              // Linked Case
                              if (t.caseId != null && t.caseId!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.folder_open_rounded, size: 12, color: Color(0xFF64748B)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Case: ${t.caseId}',
                                        style: const TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // Assignee
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person_outline_rounded, size: 13, color: Color(0xFF64748B)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Assigned: $assignedName',
                                    style: const TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),

                              // Due Date
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 11,
                                    color: t.isOverdue() ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Due: ${t.deadline != null ? DateFormat('dd MMM yyyy, hh:mm a').format(t.deadline!) : 'N/A'}',
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 11,
                                      fontWeight: t.isOverdue() ? FontWeight.w700 : FontWeight.w500,
                                      color: t.isOverdue() ? const Color(0xFFDC2626) : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)),
                          onPressed: () => _showTaskDialog(t),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                          onPressed: () => _deleteTask(t.id),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).animate().fadeIn(delay: (index * 20).ms);
      },
    );
  }

  // ─── 5. Minimalist Empty State ───
  Widget _buildEmptyState(bool isMyTask) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.task_alt_rounded,
                size: 36,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isMyTask ? 'You\'re all caught up' : 'No tasks found',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isMyTask
                  ? 'No pending task assignments right now. Enjoy your day or check back later.'
                  : 'Assign a new task to your team to get started.',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showTaskDialog(),
              icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xFFD4AF37)),
              label: const Text(
                'Assign New Task',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Color(0xFFD4AF37),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 2.5),
      ),
    );
  }
}
