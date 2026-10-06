import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/case_service.dart';
import '../utils/display_name_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/client_service.dart';
import 'billing_screen.dart';
import 'document_list_screen.dart';
import 'client_folder_screen.dart';
import 'client_files_dialog.dart';
import '../models/client.dart';
import 'task_management_screen.dart';
import 'audit_history_screen.dart';
import 'client_dashboard.dart';
import 'expense_screen.dart';

class CaseManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? existingCase;

  const CaseManagementScreen({super.key, this.existingCase});

  @override
  State<CaseManagementScreen> createState() => _CaseManagementScreenState();
}

class _CaseManagementScreenState extends State<CaseManagementScreen> {
  // Primary Case Status ('Pending' or 'Disposed')
  String _primaryCaseStatus = 'Pending';

  // Case Basic Info Controllers
  final _caseIdController = TextEditingController();
  final _caseTitleController = TextEditingController();
  final _courtCaseNumberController = TextEditingController();
  final _courtNameController = TextEditingController();
  final _clientController = TextEditingController();
  final _opposingPartyController = TextEditingController();
  final _opposingCounselController = TextEditingController();
  final _caseTypeController = TextEditingController();
  final _feeController = TextEditingController();
  final _judgeNameController = TextEditingController();
  final _careOfController = TextEditingController();
  final _handlingController = TextEditingController();

  // Pending Update Log Form State
  final _stageInputController = TextEditingController(text: 'Doc Collection');
  final _proceedingsInputController = TextEditingController();
  
  List<String> _selectedHandlingStaffList = [];
  List<Map<String, dynamic>> _allStaff = [];
  
  DateTime? _selectedNextHearingDate;
  final List<PlatformFile> _pendingAttachedFiles = [];

  // Disposed Case State
  DateTime? _disposalDate;
  String _disposalReason = 'Final Judgement';
  final _disposalNotesController = TextEditingController();
  final List<PlatformFile> _disposalAttachedFiles = [];

  // Timeline Flow History (Chronological logs of status updates & proceedings)
  List<Map<String, dynamic>> _caseFlowHistory = [];

  // Metadata & User state
  bool _isBasicInfoExpanded = false;
  String _currentUserEmail = '';
  String? _caseId;

  static const List<String> _disposalReasons = [
    'Final Judgement',
    'Mutual Settlement / Out of Court',
    'Withdrawn by Petitioner',
    'Dismissed for Default',
    'Transferred to Other Court',
    'Acquitted',
    'Convicted',
    'Custom Reason',
  ];

  @override
  void initState() {
    super.initState();
    _initUser();
    _populateInitialCaseData();
  }

  @override
  void dispose() {
    _caseIdController.dispose();
    _caseTitleController.dispose();
    _courtCaseNumberController.dispose();
    _courtNameController.dispose();
    _clientController.dispose();
    _opposingPartyController.dispose();
    _opposingCounselController.dispose();
    _caseTypeController.dispose();
    _feeController.dispose();
    _judgeNameController.dispose();
    _careOfController.dispose();
    _handlingController.dispose();
    _stageInputController.dispose();
    _proceedingsInputController.dispose();
    _disposalNotesController.dispose();
    super.dispose();
  }

  Future<void> _initUser() async {
    final prefs = await SharedPreferences.getInstance();
    final users = await UserService.getAllUsers();
    
    // Ensure uniqueness by email to prevent Dropdown duplicate value assertions
    final uniqueUsersMap = <String, Map<String, dynamic>>{};
    for (var u in users) {
      final email = u['email']?.toString();
      if (email != null && email.isNotEmpty) {
        uniqueUsersMap[email] = u;
      }
    }
    
    if (mounted) {
      setState(() {
        _allStaff = uniqueUsersMap.values.toList();
        _currentUserEmail = prefs.getString('user_email') ?? '';
      });
    }
  }

  void _populateInitialCaseData() {
    if (widget.existingCase != null) {
      final data = widget.existingCase!;
      
      String _safeString(dynamic value) {
        if (value == null) return '';
        if (value is List) return value.join(', ');
        return value.toString();
      }

      _caseId = data['id']?.toString();
      _caseIdController.text = _safeString(data['case_number'] ?? data['case_id'] ?? data['workfile_no']);
      _caseTitleController.text = _safeString(data['case_title'] ?? data['title']);
      _clientController.text = _safeString(data['client_name']);
      _courtNameController.text = _safeString(data['court_name'] ?? data['court_details']);
      _courtCaseNumberController.text = _safeString(data['court_case_number'] ?? data['case_number']);
      _opposingPartyController.text = _safeString(data['opposing_party']);
      _opposingCounselController.text = _safeString(data['opposing_counsel']);
      _caseTypeController.text = _safeString(data['case_type']);
      _feeController.text = _safeString(data['total_fees'] ?? data['fee']);
      _judgeNameController.text = _safeString(data['judge_name']);
      _careOfController.text = _safeString(data['assigned_counsel'] ?? data['created_by'] ?? data['lawyer_name']);
      
      dynamic handlingData = data['handling_lawyer'] ?? data['handling_staff'] ?? data['responsible_staff'];
      if (handlingData is List) {
        _selectedHandlingStaffList = handlingData.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        _handlingController.text = _selectedHandlingStaffList.join(', ');
      } else {
        _handlingController.text = _safeString(handlingData);
        if (_handlingController.text.trim().isNotEmpty) {
          _selectedHandlingStaffList = _handlingController.text.split(',').map((e) => e.trim().replaceAll('[', '').replaceAll(']', '')).where((e) => e.isNotEmpty).toList();
        }
      }

      if (data['current_stage'] != null && data['current_stage'].toString().trim().isNotEmpty) {
        _stageInputController.text = data['current_stage'].toString();
      }

      // Status
      final rawStatus = (data['status'] ?? 'Pending').toString();
      if (rawStatus.toLowerCase().contains('dispose') || rawStatus.toLowerCase().contains('closed')) {
        _primaryCaseStatus = 'Disposed';
      } else {
        _primaryCaseStatus = 'Pending';
      }

      // Next Hearing Date
      if (data['next_hearing_date'] != null) {
        try {
          _selectedNextHearingDate = DateTime.tryParse(data['next_hearing_date'].toString());
        } catch (_) {}
      }

      // Timeline Flow History
      try {
        final rawFlow = data['flow_history'] ?? data['data']?['flow_history'] ?? data['notes'];
        if (rawFlow != null) {
          if (rawFlow is String) {
            final decoded = jsonDecode(rawFlow);
            if (decoded is List) {
              _caseFlowHistory = List<Map<String, dynamic>>.from(decoded);
            } else if (decoded is Map && decoded['flow_history'] != null) {
              _caseFlowHistory = List<Map<String, dynamic>>.from(decoded['flow_history']);
            }
          } else if (rawFlow is List) {
            _caseFlowHistory = List<Map<String, dynamic>>.from(rawFlow);
          }
        }
      } catch (_) {}

      // If initial flow history is empty, populate starting record
      if (_caseFlowHistory.isEmpty) {
        _caseFlowHistory.add({
          'id': 'init_${DateTime.now().millisecondsSinceEpoch}',
          'status': _primaryCaseStatus,
          'stage': data['current_stage'] ?? 'Case Registration',
          'proceedings': data['initial_facts'] ?? 'Initial case created and registered.',
          'next_hearing_date': _selectedNextHearingDate?.toIso8601String(),
          'attachments': [],
          'timestamp': DateTime.now().toIso8601String(),
          'updated_by': 'System',
        });
      }
    } else {
      // New Case Defaults
      _isBasicInfoExpanded = true;
      _caseIdController.text = "CU-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    }
  }

  // File Picker for Pending Update
  Future<void> _pickPendingFiles() async {
    try {
      final result = await FilePicker.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pendingAttachedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting files: $e')),
        );
      }
    }
  }

  // File Picker for Disposal
  Future<void> _pickDisposalFiles() async {
    try {
      final result = await FilePicker.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _disposalAttachedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting disposal files: $e')),
        );
      }
    }
  }

  // Action: Log Status Update & Add to Timeline Flow
  Future<void> _logStatusUpdate() async {
    final title = _caseTitleController.text.trim();
    final client = _clientController.text.trim();
    if (title.isEmpty || client.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide Case Title and Client Name in Basic Info.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      setState(() => _isBasicInfoExpanded = true);
      return;
    }

    final stageName = _stageInputController.text.trim().isNotEmpty
        ? _stageInputController.text.trim()
        : 'Doc Collection';

    if (stageName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the Stage of Case.')),
      );
      return;
    }

    final proceedingsText = _proceedingsInputController.text.trim();
    if (proceedingsText.isEmpty && _selectedNextHearingDate == null && _pendingAttachedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter proceedings details, next hearing date, or attach files.'),
        ),
      );
      return;
    }

    final attachmentsList = _pendingAttachedFiles.map((file) => {
      'name': file.name,
      'size': '${(file.size / 1024).toStringAsFixed(1)} KB',
      'path': file.path ?? '',
    }).toList();

    final newEntry = {
      'id': 'flow_${DateTime.now().millisecondsSinceEpoch}',
      'status': _primaryCaseStatus,
      'stage': stageName,
      'proceedings': proceedingsText.isNotEmpty ? proceedingsText : 'Stage updated to $stageName.',
      'next_hearing_date': _selectedNextHearingDate?.toIso8601String(),
      'attachments': attachmentsList,
      'timestamp': DateTime.now().toIso8601String(),
      'updated_by': _currentUserEmail.isNotEmpty ? _currentUserEmail : 'Staff User',
    };

    _handlingController.text = _selectedHandlingStaffList.join(', ');

    setState(() {
      _caseFlowHistory.insert(0, newEntry); // Add to timeline flow (newest first)
      _proceedingsInputController.clear();
      _pendingAttachedFiles.clear();
    });

    final success = await _saveCaseToBackend();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Status update logged to case timeline flow!'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Action: Log Case Disposal
  Future<void> _logCaseDisposal() async {
    final notes = _disposalNotesController.text.trim();
    final attachmentsList = _disposalAttachedFiles.map((file) => {
      'name': file.name,
      'size': '${(file.size / 1024).toStringAsFixed(1)} KB',
      'path': file.path ?? '',
    }).toList();

    final disposalEntry = {
      'id': 'flow_${DateTime.now().millisecondsSinceEpoch}',
      'status': 'Disposed',
      'stage': 'CASE DISPOSED',
      'proceedings': 'CASE DISPOSED ($formatReason): ${notes.isNotEmpty ? notes : "Case concluded."}',
      'disposal_date': (_disposalDate ?? DateTime.now()).toIso8601String(),
      'disposal_reason': _disposalReason,
      'attachments': attachmentsList,
      'timestamp': DateTime.now().toIso8601String(),
      'updated_by': _currentUserEmail.isNotEmpty ? _currentUserEmail : 'Staff User',
    };

    setState(() {
      _primaryCaseStatus = 'Disposed';
      _caseFlowHistory.insert(0, disposalEntry);
    });

    final success = await _saveCaseToBackend();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.gavel_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Workfile successfully marked as DISPOSED.'),
            ],
          ),
          backgroundColor: const Color(0xFF8B5CF6),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String get formatReason => _disposalReason;

  // Persist Case to Database via CaseService
  Future<bool> _saveCaseToBackend() async {
    try {
      final title = _caseTitleController.text.trim();
      final client = _clientController.text.trim();
      final caseNum = _caseIdController.text.trim().isNotEmpty
          ? _caseIdController.text.trim()
          : "CU-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

      _handlingController.text = _selectedHandlingStaffList.join(', ');

      final currentStageName = _caseFlowHistory.isNotEmpty
          ? _caseFlowHistory.first['stage']
          : (_stageInputController.text.trim().isNotEmpty ? _stageInputController.text.trim() : 'Doc Collection');

      final casePayload = {
        'case_title': title,
        'client_name': client,
        'case_number': caseNum,
        'status': _primaryCaseStatus,
        'court_name': _courtNameController.text.trim(),
        'court_details': _courtNameController.text.trim(),
        'court_case_number': _courtCaseNumberController.text.trim(),
        'opposing_party': _opposingPartyController.text.trim(),
        'opposing_counsel': _opposingCounselController.text.trim(),
        'case_type': _caseTypeController.text.trim(),
        'total_fees': _feeController.text.trim(),
        'judge_name': _judgeNameController.text.trim(),
        'assigned_counsel': _careOfController.text.trim(),
        'handling_lawyer': _handlingController.text.trim(),
        'current_stage': currentStageName,
        'next_hearing_date': _selectedNextHearingDate?.toIso8601String(),
        'flow_history': jsonEncode(_caseFlowHistory),
        'notes': jsonEncode({'flow_history': _caseFlowHistory}),
        'data': {
          'flow_history': _caseFlowHistory,
        },
      };

      if (_caseId != null) {
        await CaseService.updateCase(_caseId!, casePayload);
      } else {
        await CaseService.addCase(casePayload);
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving case record: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _onDeleteCase() async {
    if (_caseId == null) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Workfile Record', style: GoogleFonts.cinzel(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to permanently delete this case and its proceedings history?', style: GoogleFonts.montserrat(color: const Color(0xFF475569))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await CaseService.deleteCase(_caseId!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Workfile deleted successfully')));
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete case: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF334155), size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _caseId != null ? 'WORKFILE MANAGEMENT' : 'REGISTER NEW WORKFILE',
              style: GoogleFonts.cinzel(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: const Color(0xFF0F172A),
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _primaryCaseStatus == 'Pending'
                    ? const Color(0xFFFEF3C7)
                    : const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _primaryCaseStatus == 'Pending'
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF8B5CF6),
                ),
              ),
              child: Text(
                _primaryCaseStatus.toUpperCase(),
                style: GoogleFonts.montserrat(
                  color: _primaryCaseStatus == 'Pending'
                      ? const Color(0xFFB45309)
                      : const Color(0xFF6D28D9),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_caseId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed, size: 20),
              onPressed: _onDeleteCase,
              tooltip: 'Delete Case',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 20.0, top: 8, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: () async {
                final success = await _saveCaseToBackend();
                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: const [
                          Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text('Workfile record saved successfully!'),
                        ],
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('SAVE RECORD'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: AppTheme.accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_caseId != null) ...[
                _buildTopActionMenu(),
                const SizedBox(height: 16),
              ],
              // 1. Basic Info Collapsible Header Card
              _buildBasicInfoCard(),
              const SizedBox(height: 20),

              // 2. Main Workspace (Form + Timeline Flow)
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _primaryCaseStatus == 'Disposed'
                                ? _buildDisposalFormCard()
                                : _buildLogUpdateFormCard(),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 6,
                            child: SingleChildScrollView(
                              child: _buildTimelineFlowCard(),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _primaryCaseStatus == 'Disposed'
                                ? _buildDisposalFormCard()
                                : _buildLogUpdateFormCard(),
                            const SizedBox(height: 24),
                            _buildTimelineFlowCard(),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET: TOP ACTION MENU ---
  Widget _buildTopActionMenu() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildPremiumActionButton(Icons.info_outline_rounded, 'Workfile Details', 'View full info', () {
              _showCaseDetailsDialog();
            }),
            _buildPremiumDivider(),
            _buildPremiumActionButton(Icons.person_search_rounded, 'Client Profile', 'View & edit details', () {
              _showClientDetailsDialog();
            }),
            _buildPremiumDivider(),
            _buildPremiumActionButton(Icons.account_balance_wallet_rounded, 'Accounts', 'Expenses & ledgers', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ExpenseScreen(
                initialCaseId: _caseId
              )));
            }),
            _buildPremiumDivider(),
            _buildPremiumActionButton(Icons.receipt_long_rounded, 'Billing', 'Invoices', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => BillingScreen(
                initialClientName: _clientController.text, 
                linkedCaseId: _caseId
              )));
            }),
            _buildPremiumDivider(),
            _buildPremiumActionButton(Icons.folder_open_rounded, 'Client Documents', 'Manage case files', () async {
              final cName = _clientController.text.trim().toLowerCase();
              if (cName.isEmpty) return;
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );
              
              final clientsData = await ClientService().getAllClients();
              Client? matchedClient;
              for (var cData in clientsData) {
                final c = Client.fromMap(cData);
                if (c.name?.toLowerCase().trim() == cName) {
                  matchedClient = c;
                  break;
                }
              }
              
              if (mounted) Navigator.pop(context); // remove loading
              
              if (matchedClient != null && mounted) {
                showDialog(
                  context: context,
                  barrierColor: Colors.black.withValues(alpha: 0.75),
                  builder: (context) => ClientFilesDialog(client: matchedClient!),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Client not found in Client Management. Please verify client name.'))
                );
              }
            }),
            _buildPremiumDivider(),
            _buildPremiumActionButton(Icons.checklist_rtl_rounded, 'Workfile Tasks', 'Deadlines & todos', () {
              final cTitle = _caseTitleController.text.trim();
              final cId = _courtCaseNumberController.text.trim();
              
              String displayCaseId = _caseId ?? '';
              if (cTitle.isNotEmpty && cId.isNotEmpty) {
                displayCaseId = '$cTitle ($cId)';
              } else if (cTitle.isNotEmpty) {
                displayCaseId = cTitle;
              } else if (cId.isNotEmpty) {
                displayCaseId = cId;
              }
              
              Navigator.push(context, MaterialPageRoute(builder: (_) => TaskManagementScreen(linkedCaseId: displayCaseId)));
            }),
            _buildPremiumDivider(),
            _buildPremiumActionButton(Icons.history_rounded, 'Activity Log', 'Audit & history', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditHistoryScreen()));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        width: 1.5,
        height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFE2E8F0).withValues(alpha: 0.1),
              const Color(0xFFE2E8F0),
              const Color(0xFFE2E8F0).withValues(alpha: 0.1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumActionButton(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: AppTheme.accentColor.withValues(alpha: 0.1),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF1F5F9)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Icon(icon, size: 18, color: AppTheme.accentColor),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title.toUpperCase(),
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.montserrat(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClientDetailsDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    final clients = await ClientService().getAllClients();
    final clientName = _clientController.text.trim();
    final clientData = clients.firstWhere(
      (c) => c['name'] == clientName || c['email'] == clientName, 
      orElse: () => <String, dynamic>{},
    );
    
    if (mounted) Navigator.pop(context);
    
    if (clientData.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client details not found.')));
      return;
    }
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: 600,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.15), blurRadius: 32, offset: const Offset(0, 16)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.person_rounded, color: AppTheme.accentColor, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Client Details',
                              style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              clientData['name']?.toString() ?? 'Overview',
                              style: GoogleFonts.montserrat(fontSize: 12, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        splashRadius: 24,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPremiumSectionTitle('1. Contact Info'),
                        _buildPremiumDetailGrid([
                          {'icon': Icons.person_rounded, 'label': 'Name', 'value': clientData['name']?.toString() ?? 'N/A'},
                          {'icon': Icons.email_rounded, 'label': 'Email', 'value': clientData['email']?.toString() ?? 'N/A'},
                          {'icon': Icons.phone_rounded, 'label': 'Phone', 'value': clientData['phone']?.toString() ?? 'N/A'},
                          {'icon': Icons.location_on_rounded, 'label': 'Address', 'value': clientData['address']?.toString() ?? 'N/A'},
                        ]),
                        
                        if ((clientData['company'] != null && clientData['company'].toString().trim().isNotEmpty) ||
                            (clientData['gst'] != null && clientData['gst'].toString().trim().isNotEmpty)) ...[
                          const SizedBox(height: 24),
                          _buildPremiumSectionTitle('2. Business Info'),
                          _buildPremiumDetailGrid([
                            if (clientData['company'] != null && clientData['company'].toString().trim().isNotEmpty)
                              {'icon': Icons.business_rounded, 'label': 'Company', 'value': clientData['company'].toString()},
                            if (clientData['gst'] != null && clientData['gst'].toString().trim().isNotEmpty)
                              {'icon': Icons.receipt_long_rounded, 'label': 'GST Number', 'value': clientData['gst'].toString()},
                          ]),
                        ],
                        
                        if ((clientData['type_of_work'] != null && clientData['type_of_work'].toString().trim().isNotEmpty) ||
                            (clientData['balance_due'] != null && clientData['balance_due'].toString().trim().isNotEmpty) ||
                            (clientData['notes'] != null && clientData['notes'].toString().trim().isNotEmpty)) ...[
                          const SizedBox(height: 24),
                          _buildPremiumSectionTitle('3. Additional Details'),
                          _buildPremiumDetailGrid([
                            if (clientData['type_of_work'] != null && clientData['type_of_work'].toString().trim().isNotEmpty)
                              {'icon': Icons.work_rounded, 'label': 'Type of Work', 'value': clientData['type_of_work'].toString()},
                            if (clientData['balance_due'] != null && clientData['balance_due'].toString().trim().isNotEmpty)
                              {'icon': Icons.account_balance_wallet_rounded, 'label': 'Balance Due', 'value': '₹${clientData['balance_due']}'},
                            if (clientData['notes'] != null && clientData['notes'].toString().trim().isNotEmpty)
                              {'icon': Icons.notes_rounded, 'label': 'Notes', 'value': clientData['notes'].toString()},
                          ], crossAxisCount: 1),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showCaseDetailsDialog() {
    String handledByNames = _selectedHandlingStaffList.isNotEmpty 
      ? _selectedHandlingStaffList.map((email) {
          final staff = _allStaff.firstWhere((s) => s['email'] == email, orElse: () => <String, dynamic>{});
          return staff.isNotEmpty ? (staff['name']?.toString() ?? staff['username']?.toString() ?? email) : email;
        }).join(', ')
      : 'N/A';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: 600,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.15), blurRadius: 32, offset: const Offset(0, 16)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.description_rounded, color: AppTheme.accentColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Workfile Details',
                            style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            _caseIdController.text.trim().isNotEmpty ? _caseIdController.text : 'Complete Overview',
                            style: GoogleFonts.montserrat(fontSize: 12, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPremiumSectionTitle('1. Workfile Overview'),
                      _buildPremiumDetailGrid([
                        {'icon': Icons.title_rounded, 'label': 'Workfile Title', 'value': _caseTitleController.text.trim().isNotEmpty ? _caseTitleController.text : 'N/A'},
                        {'icon': Icons.folder_open_rounded, 'label': 'File No', 'value': _caseIdController.text.trim().isNotEmpty ? _caseIdController.text : 'N/A'},
                        {'icon': Icons.tag_rounded, 'label': 'Court Workfile No', 'value': _courtCaseNumberController.text.trim().isNotEmpty ? _courtCaseNumberController.text : 'N/A'},
                        {'icon': Icons.category_rounded, 'label': 'Workfile Type', 'value': _caseTypeController.text.trim().isNotEmpty ? _caseTypeController.text : 'N/A'},
                      ]),
                      const SizedBox(height: 24),
                      
                      _buildPremiumSectionTitle('2. Court & Bench'),
                      _buildPremiumDetailGrid([
                        {'icon': Icons.account_balance_rounded, 'label': 'Court Name', 'value': _courtNameController.text.trim().isNotEmpty ? _courtNameController.text : 'N/A'},
                        {'icon': Icons.gavel_rounded, 'label': 'Judge Name', 'value': _judgeNameController.text.trim().isNotEmpty ? _judgeNameController.text : 'N/A'},
                      ]),
                      const SizedBox(height: 24),
                      
                      _buildPremiumSectionTitle('3. Client & Representation'),
                      _buildPremiumDetailGrid([
                        {'icon': Icons.person_rounded, 'label': 'Client Name', 'value': _clientController.text.trim().isNotEmpty ? _clientController.text : 'N/A'},
                        {'icon': Icons.supervisor_account_rounded, 'label': 'Care Of (C/O)', 'value': _careOfController.text.trim().isNotEmpty ? _careOfController.text : 'N/A'},
                        {'icon': Icons.group_work_rounded, 'label': 'Handled By', 'value': handledByNames},
                      ], crossAxisCount: 1), 
                      const SizedBox(height: 24),

                      _buildPremiumSectionTitle('4. Status'),
                      _buildPremiumDetailGrid([
                        {'icon': Icons.stairs_rounded, 'label': 'Current Stage', 'value': _primaryCaseStatus},
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF64748B),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildPremiumDetailGrid(List<Map<String, dynamic>> items, {int crossAxisCount = 2}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 400;
        final actualCrossAxisCount = isMobile ? 1 : crossAxisCount;
        
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: actualCrossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 72,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(item['icon'] as IconData, size: 18, color: AppTheme.accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item['label'] as String,
                          style: GoogleFonts.montserrat(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['value'] as String,
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1, // Only 1 line because Grid sets a fixed height, preventing huge overflows. If we need multiple lines we can adjust. Actually Handled By might be long, let's allow 2 lines. Wait, GridView has mainAxisExtent: 72. So maxLines 2 is fine.
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- WIDGET 1: BASIC CASE INFO CARD ---
  Widget _buildBasicInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isBasicInfoExpanded = !_isBasicInfoExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.gavel_rounded, color: Color(0xFFB8860B), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _caseTitleController.text.isNotEmpty
                              ? _caseTitleController.text
                              : 'Untitled Workfile (Click to fill workfile metadata)',
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Client: ${_clientController.text.isNotEmpty ? _clientController.text : "N/A"} • Case #: ${_caseIdController.text} • Court: ${_courtNameController.text.isNotEmpty ? _courtNameController.text : "N/A"}',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isBasicInfoExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
          ),
          if (_isBasicInfoExpanded) ...[
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildCompactInput(_caseTitleController, 'Workfile Title', Icons.title)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildCompactInput(_clientController, 'Client Name', Icons.person)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildCompactInput(_courtNameController, 'Court Name', Icons.account_balance)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildCompactInput(_courtCaseNumberController, 'Court Workfile / Filing #', Icons.numbers)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildCompactInput(_opposingPartyController, 'Opposing Party', Icons.people_outline)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildCompactInput(_opposingCounselController, 'Opposing Counsel', Icons.gavel)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildCompactInput(_caseTypeController, 'Workfile Type / Category', Icons.category)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildCompactInput(_feeController, 'Total Agreed Fee (₹)', Icons.currency_rupee)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildCompactInput(_careOfController, 'Care Of', Icons.person)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildCompactInput(_handlingController, 'Handling', Icons.work_outline)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }



  // --- WIDGET 3: LOG UPDATE FORM CARD (PENDING) ---
  Widget _buildLogUpdateFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Color(0xFFB8860B), size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'LOG STAGE & PROCEEDINGS',
                  style: GoogleFonts.montserrat(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 1. Case Status Input (Pending / Disposed)
            _buildFieldHeader('1. WORKFILE STATUS'),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _primaryCaseStatus,
                  isExpanded: true,
                  style: GoogleFonts.montserrat(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13.5),
                  items: const [
                    DropdownMenuItem(
                      value: 'Pending',
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_top_rounded, color: Color(0xFFB45309), size: 18),
                          SizedBox(width: 10),
                          Text('Pending Case'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Disposed',
                      child: Row(
                        children: [
                          Icon(Icons.task_alt_rounded, color: Color(0xFF7C3AED), size: 18),
                          SizedBox(width: 10),
                          Text('Disposed Case'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _primaryCaseStatus = val);
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 2. Stage of Case Input Field
            _buildFieldHeader('2. STAGE OF WORKFILE'),
            const SizedBox(height: 5),
            TextField(
              controller: _stageInputController,
              style: GoogleFonts.montserrat(fontSize: 13.5, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Enter stage of case (e.g. Doc Collection, Pleadings, Evidence)...',
                hintStyle: GoogleFonts.montserrat(fontSize: 13, color: const Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.bookmark_outline_rounded, color: AppTheme.accentColor, size: 18),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 14),

            // 3. Proceedings Input
            _buildFieldHeader('3. PROCEEDINGS / HEARING NOTES'),
            const SizedBox(height: 5),
            TextField(
              controller: _proceedingsInputController,
              maxLines: 3,
              style: GoogleFonts.montserrat(fontSize: 13.5, color: const Color(0xFF0F172A), fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Enter detailed court proceedings, arguments presented, orders passed, or daily work notes...',
                hintStyle: GoogleFonts.montserrat(fontSize: 13, color: const Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 14),

            // 4. Assign Staff Fields
            _buildFieldHeader('4. UPDATE STAFF (OPTIONAL)'),
            const SizedBox(height: 5),
            if (_selectedHandlingStaffList.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedHandlingStaffList.map((email) {
                  final staffName = _allStaff.firstWhere((s) => s['email'] == email, orElse: () => {'name': email})['name'] ?? email;
                  return Chip(
                    label: Text(staffName, style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w600)),
                    backgroundColor: const Color(0xFFEDE9FE),
                    deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF6D28D9)),
                    onDeleted: () {
                      setState(() {
                        _selectedHandlingStaffList.remove(email);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
            DropdownButtonFormField<String>(
              value: null,
              decoration: InputDecoration(
                hintText: 'Add Handled By (Multiple allowed)',
                hintStyle: GoogleFonts.montserrat(fontSize: 13, color: const Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.gavel_rounded, color: AppTheme.accentColor, size: 18),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: _allStaff.where((s) => !_selectedHandlingStaffList.contains(s['email'])).map((staff) {
                final email = staff['email']?.toString() ?? '';
                final name = staff['name']?.toString() ?? staff['username']?.toString() ?? email;
                return DropdownMenuItem<String>(
                  value: email,
                  child: Text(name, style: GoogleFonts.montserrat(fontSize: 13.5, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedHandlingStaffList.add(val);
                  });
                }
              },
            ),

            const SizedBox(height: 14),

            // 5. Next Hearing Date
            _buildFieldHeader('5. NEXT HEARING DATE'),
            const SizedBox(height: 5),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedNextHearingDate ?? DateTime.now().add(const Duration(days: 14)),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2035),
                );
                if (picked != null) {
                  setState(() => _selectedNextHearingDate = picked);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedNextHearingDate != null ? AppTheme.accentColor : const Color(0xFFCBD5E1),
                    width: _selectedNextHearingDate != null ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_rounded,
                      color: _selectedNextHearingDate != null ? const Color(0xFFB8860B) : const Color(0xFF64748B),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedNextHearingDate != null
                          ? DateFormat('EEEE, dd MMMM yyyy').format(_selectedNextHearingDate!)
                          : 'Select Next Hearing Date',
                      style: GoogleFonts.montserrat(
                        color: _selectedNextHearingDate != null ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                        fontWeight: _selectedNextHearingDate != null ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedNextHearingDate != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                        onPressed: () => setState(() => _selectedNextHearingDate = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 6. File Upload Section
            _buildFieldHeader('6. UPLOAD PROCEEDING FILES / DOCUMENTS'),
            const SizedBox(height: 5),
            OutlinedButton.icon(
              onPressed: _pickPendingFiles,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('ATTACH FILES FROM COMPUTER'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),

            if (_pendingAttachedFiles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _pendingAttachedFiles.map((file) {
                  return Chip(
                    avatar: const Icon(Icons.insert_drive_file_rounded, size: 14, color: AppTheme.accentColor),
                    label: Text(file.name, style: GoogleFonts.montserrat(fontSize: 11.5, color: const Color(0xFF0F172A))),
                    backgroundColor: const Color(0xFFFEF3C7),
                    deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                    onDeleted: () {
                      setState(() => _pendingAttachedFiles.remove(file));
                    },
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 18),

            // Submit Log Button
            ElevatedButton.icon(
              onPressed: _logStatusUpdate,
              icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
              label: const Text('LOG UPDATE & SAVE PROCEEDING'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                minimumSize: const Size(double.infinity, 48),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET 4: TIMELINE FLOW CARD (PENDING) ---
  Widget _buildTimelineFlowCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.timeline_rounded, color: Color(0xFF059669), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'WORKFILE PROCEEDINGS TIMELINE FLOW',
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_caseFlowHistory.length} UPDATES',
                  style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_caseFlowHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.history_toggle_off_rounded, color: Color(0xFF94A3B8), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'No proceedings logged yet.',
                      style: GoogleFonts.montserrat(fontSize: 14, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Use the form to log your first case update.',
                      style: GoogleFonts.montserrat(fontSize: 12, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _caseFlowHistory.length,
              separatorBuilder: (context, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final entry = _caseFlowHistory[index];
                return _buildTimelineItemCard(entry, isLatest: index == 0);
              },
            ),
        ],
      ),
    );
  }

  // Individual Timeline Item Entry
  Widget _buildTimelineItemCard(Map<String, dynamic> entry, {required bool isLatest}) {
    final stage = entry['stage']?.toString() ?? 'Update';
    final proceedings = entry['proceedings']?.toString() ?? '';
    final nextHearing = entry['next_hearing_date']?.toString();
    final timestamp = entry['timestamp']?.toString();
    String updatedBy = entry['updated_by']?.toString() ?? 'Staff';
    if (updatedBy.contains('@')) {
      updatedBy = DisplayNameHelper.fromEmail(updatedBy);
    } else if (updatedBy.isNotEmpty && updatedBy != 'Staff' && updatedBy != 'System') {
      final parts = updatedBy.split(RegExp(r'[._\-]'));
      updatedBy = parts
          .where((p) => p.isNotEmpty)
          .map((p) => p[0].toUpperCase() + p.substring(1))
          .join(' ');
    }
    final attachments = entry['attachments'] as List?;

    DateTime? hearingDate;
    if (nextHearing != null) {
      try {
        hearingDate = DateTime.tryParse(nextHearing);
      } catch (_) {}
    }

    DateTime? entryDate;
    if (timestamp != null) {
      try {
        entryDate = DateTime.tryParse(timestamp);
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLatest ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLatest ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
          width: isLatest ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLatest ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  stage.toUpperCase(),
                  style: GoogleFonts.montserrat(
                    color: isLatest ? AppTheme.accentColor : const Color(0xFF334155),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (entryDate != null)
                Text(
                  DateFormat('dd MMM yyyy • hh:mm a').format(entryDate),
                  style: GoogleFonts.montserrat(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Proceedings Body Text
          Text(
            proceedings,
            style: GoogleFonts.montserrat(
              fontSize: 13.5,
              color: const Color(0xFF0F172A),
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),

          if (hearingDate != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_available_rounded, size: 15, color: Color(0xFFB45309)),
                  const SizedBox(width: 6),
                  Text(
                    'Next Hearing: ${DateFormat('dd MMMM yyyy').format(hearingDate)}',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (attachments != null && attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: attachments.map((att) {
                final name = att['name'] ?? 'Attachment';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_file_rounded, size: 14, color: AppTheme.accentColor),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: GoogleFonts.montserrat(fontSize: 11.5, color: const Color(0xFF334155), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Logged by $updatedBy',
              style: GoogleFonts.montserrat(fontSize: 10.5, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET 5: DISPOSAL FORM CARD (DISPOSED) ---
  Widget _buildDisposalFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.gavel_rounded, color: Color(0xFF7C3AED), size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'WORKFILE DISPOSAL & FINAL ORDER DETAILS',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 1. Case Status Input (Pending / Disposed)
          _buildFieldHeader('1. WORKFILE STATUS'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _primaryCaseStatus,
                isExpanded: true,
                style: GoogleFonts.montserrat(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13.5),
                items: const [
                  DropdownMenuItem(
                    value: 'Pending',
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded, color: Color(0xFFB45309), size: 18),
                        SizedBox(width: 10),
                        Text('Pending Case'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Disposed',
                    child: Row(
                      children: [
                        Icon(Icons.task_alt_rounded, color: Color(0xFF7C3AED), size: 18),
                        SizedBox(width: 10),
                        Text('Disposed Case'),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _primaryCaseStatus = val);
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 18),

          // 2. Disposal Reason / Outcome
          _buildFieldHeader('2. DISPOSAL TYPE / REASON'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _disposalReasons.contains(_disposalReason) ? _disposalReason : 'Final Judgement',
                isExpanded: true,
                style: GoogleFonts.montserrat(color: const Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 14),
                items: _disposalReasons.map((r) {
                  return DropdownMenuItem(value: r, child: Text(r));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _disposalReason = val);
                },
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Disposal Date
          _buildFieldHeader('DISPOSAL DATE'),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _disposalDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2035),
              );
              if (picked != null) setState(() => _disposalDate = picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_rounded, color: Color(0xFF7C3AED), size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _disposalDate != null
                        ? DateFormat('EEEE, dd MMMM yyyy').format(_disposalDate!)
                        : DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now()),
                    style: GoogleFonts.montserrat(color: const Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Final Order Notes
          _buildFieldHeader('FINAL ORDER SUMMARY / NOTES'),
          const SizedBox(height: 6),
          TextField(
            controller: _disposalNotesController,
            maxLines: 4,
            style: GoogleFonts.montserrat(fontSize: 14, color: const Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: 'Enter final judgement summary, decree details, or disposal remarks...',
              hintStyle: GoogleFonts.montserrat(fontSize: 13, color: const Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            ),
          ),

          const SizedBox(height: 18),

          // Upload Judgement File
          _buildFieldHeader('ATTACH FINAL JUDGEMENT / ORDER COPY'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickDisposalFiles,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('ATTACH FINAL JUDGEMENT PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7C3AED),
              side: const BorderSide(color: Color(0xFFC4B5FD)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 46),
            ),
          ),

          if (_disposalAttachedFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _disposalAttachedFiles.map((file) {
                return Chip(
                  avatar: const Icon(Icons.picture_as_pdf_rounded, size: 14, color: Color(0xFF7C3AED)),
                  label: Text(file.name, style: GoogleFonts.montserrat(fontSize: 12, color: const Color(0xFF0F172A))),
                  backgroundColor: const Color(0xFFEDE9FE),
                  deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                  onDeleted: () {
                    setState(() => _disposalAttachedFiles.remove(file));
                  },
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 24),

          // Save Disposal Record Button
          ElevatedButton.icon(
            onPressed: _logCaseDisposal,
            icon: const Icon(Icons.task_alt_rounded, size: 18),
            label: const Text('LOG DISPOSAL RECORD'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              minimumSize: const Size(double.infinity, 50),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  // --- UTILITY COMPONENT HELPERS ---
  Widget _buildFieldHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF475569),
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildCompactInput(TextEditingController controller, String label, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.montserrat(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF64748B), letterSpacing: 0.8),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: controller,
            style: GoogleFonts.montserrat(fontSize: 13, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 16, color: AppTheme.accentColor),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
