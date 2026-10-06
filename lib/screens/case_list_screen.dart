import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../services/case_service.dart';
import '../services/user_service.dart';
import '../utils/display_name_helper.dart';
import 'case_management_screen.dart';

class CaseListScreen extends StatefulWidget {
  const CaseListScreen({super.key});

  @override
  State<CaseListScreen> createState() => _CaseListScreenState();
}

class _CaseListScreenState extends State<CaseListScreen> {
  List<Map<String, dynamic>> _cases = [];
  Map<String, String> _staffMap = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedStatusFilter = 'All'; // 'All', 'Active', 'Pending', 'Closed'
  bool _isGridView = true; // Toggle between Grid View and Table Ledger View

  @override
  void initState() {
    super.initState();
    _fetchCases();
  }

  Future<void> _fetchCases() async {
    setState(() => _isLoading = true);
    try {
      final cases = await CaseService.getCases();
      final users = await UserService.getAllUsers();
      final Map<String, String> staffMap = {};
      for (var u in users) {
        final email = (u['email'] ?? '').toString().toLowerCase().trim();
        final username = (u['username'] ?? '').toString().toLowerCase().trim();
        final name = (u['name'] ?? u['username'] ?? u['email'] ?? '').toString().trim();

        if (name.isNotEmpty) {
          if (email.isNotEmpty) {
            staffMap[email] = name;
            final prefix = email.split('@')[0];
            if (prefix.isNotEmpty) {
              staffMap[prefix] = name;
            }
          }
          if (username.isNotEmpty) {
            staffMap[username] = name;
          }
        }
      }

      // Sort cases by Year descending, then by Workfile Number descending
      Map<String, dynamic> parseDesc(dynamic desc) {
        if (desc == null) return {};
        if (desc is Map) return Map<String, dynamic>.from(desc);
        if (desc is String) {
          if (desc.isEmpty) return {};
          try {
            final decoded = jsonDecode(desc);
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
          } catch (_) {}
        }
        return {};
      }

      for (var c in cases) {
        final dataMap = parseDesc(c['case_description']);
        String y = (c['year'] ?? c['case_year'] ?? '').toString();
        String mapYear = (dataMap['year'] ?? dataMap['case_year'] ?? '').toString();
        if (mapYear.isNotEmpty) y = mapYear;
        c['_sort_year'] = int.tryParse(y) ?? 0;

        String no = (dataMap['workfile_no'] ?? c['workfile_no'] ?? c['case_number'] ?? '').toString();
        final match = RegExp(r'\d+').firstMatch(no);
        c['_sort_num'] = match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
      }

      cases.sort((a, b) {
        final yearA = a['_sort_year'] as int? ?? 0;
        final yearB = b['_sort_year'] as int? ?? 0;
        if (yearA != yearB) return yearB.compareTo(yearA);

        final numA = a['_sort_num'] as int? ?? 0;
        final numB = b['_sort_num'] as int? ?? 0;
        if (numA != numB) return numB.compareTo(numA);

        final timeA = DateTime.tryParse((a['createdAt'] ?? a['created_at'] ?? '').toString()) ?? DateTime(2000);
        final timeB = DateTime.tryParse((b['createdAt'] ?? b['created_at'] ?? '').toString()) ?? DateTime(2000);
        return timeB.compareTo(timeA);
      });

      if (mounted) {
        setState(() {
          _cases = cases;
          _staffMap = staffMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading cases: $e')));
      }
    }
  }

  String _formatHandlerName(dynamic raw) {
    if (raw == null) return 'Unassigned';
    
    List<String> items = [];
    if (raw is List) {
      items = raw.map((e) => e.toString()).toList();
    } else {
      String str = raw.toString().trim();
      if (str.isEmpty || str == 'Unassigned') return 'Unassigned';
      
      if (str.startsWith('[') && str.endsWith(']')) {
        try {
          final decoded = jsonDecode(str);
          if (decoded is List) {
            items = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {
          str = str.substring(1, str.length - 1).replaceAll('"', '').replaceAll("'", '');
          items = str.split(',').map((e) => e.trim()).toList();
        }
      } else {
        items = [str];
      }
    }

    List<String> formattedNames = [];
    for (var item in items) {
      String clean = item.trim().replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').replaceAll("'", '');
      if (clean.isEmpty) continue;
      
      final cleanLower = clean.toLowerCase();
      
      if (_staffMap.containsKey(cleanLower)) {
        formattedNames.add(_staffMap[cleanLower]!);
        continue;
      }
      
      if (cleanLower.contains('@')) {
        final prefix = cleanLower.split('@')[0];
        if (_staffMap.containsKey(prefix)) {
          formattedNames.add(_staffMap[prefix]!);
          continue;
        }
        final parts = prefix.split(RegExp(r'[._\-]'));
        clean = parts
            .where((p) => p.isNotEmpty)
            .map((p) => p[0].toUpperCase() + p.substring(1))
            .join(' ');
      } else {
        final parts = clean.split(RegExp(r'[._\-]'));
        clean = parts
            .where((p) => p.isNotEmpty)
            .map((p) => p[0].toUpperCase() + p.substring(1))
            .join(' ');
      }
      
      formattedNames.add(clean);
    }

    return DisplayNameHelper.overrideName(formattedNames.isNotEmpty ? formattedNames.join(', ') : 'Unassigned');
  }

  List<Map<String, dynamic>> get _filteredCases {
    return _cases.where((c) {
      final title = (c['case_title'] ?? c['title'] ?? '').toString().toLowerCase();
      final court = (c['court_name'] ?? '').toString().toLowerCase();
      final caseNo = (c['court_case_number'] ?? '').toString().toLowerCase();
      final client = (c['client_name'] ?? '').toString().toLowerCase();
      final status = (c['case_status'] ?? 'Pending').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      final matchesSearch = _searchQuery.isEmpty || 
          title.contains(q) || court.contains(q) || caseNo.contains(q) || client.contains(q);

      if (!matchesSearch) return false;

      if (_selectedStatusFilter == 'Active') {
        return status == 'active' || status == 'open' || status == 'ongoing';
      } else if (_selectedStatusFilter == 'Pending') {
        return status == 'pending' || status == 'draft';
      } else if (_selectedStatusFilter == 'Closed') {
        return status == 'closed' || status == 'completed';
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7), // Executive Canvas Background
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── 1. Executive Command Top Header ───
            _buildTopCommandHeader(),

            // ─── 2. Main Scrollable Body ───
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchCases,
                color: const Color(0xFF0F172A),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ─── Analytics Summary Cards ───
                      if (!_isLoading && _cases.isNotEmpty) ...[
                        _buildAnalyticsGrid(),
                        const SizedBox(height: 24),
                      ],

                      // ─── Controls Bar (Search, Status Tabs, View Switcher) ───
                      if (!_isLoading && _cases.isNotEmpty) ...[
                        _buildControlsRow(),
                        const SizedBox(height: 20),
                      ],

                      // ─── Roster Display Area ───
                      if (_isLoading)
                        _buildLoadingState()
                      else if (_cases.isEmpty)
                        _buildEmptyState()
                      else if (_filteredCases.isEmpty)
                        _buildNoResultsState()
                      else if (_isGridView)
                        _buildGridView()
                      else
                        _buildTableLedgerView(),
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

  // ─── 1. Top Command Header ───
  Widget _buildTopCommandHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 650;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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

                  // Title Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Case Management',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF0F172A),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_cases.length} Matters',
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Cochin United Legal LLP • Litigation & Case Files',
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

                  ],
                ),
            ],
          );
        },
      ),
    );
  }


  // ─── 2. Executive Analytics Metric Cards Grid ───
  Widget _buildAnalyticsGrid() {
    final total = _cases.length;
    final activeCount = _cases.where((c) {
      final status = (c['case_status'] ?? '').toString().toLowerCase();
      return status == 'active' || status == 'open' || status == 'ongoing';
    }).length;
    final pendingCount = _cases.where((c) {
      final status = (c['case_status'] ?? '').toString().toLowerCase();
      return status == 'pending' || status == 'draft';
    }).length;
    final closedCount = total - activeCount - pendingCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final cardWidth = isWide ? (constraints.maxWidth - 32) / 3 : constraints.maxWidth;
        
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'Active Litigation',
                count: activeCount.toString(),
                subtitle: 'Ongoing court proceedings & hearings',
                icon: Icons.gavel_rounded,
                accentColor: const Color(0xFF16A34A),
                bgColor: const Color(0xFFF0FDF4),
                borderColor: const Color(0xFFBBF7D0),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'Pending & Registration',
                count: pendingCount.toString(),
                subtitle: 'Drafting, filing & document collection',
                icon: Icons.pending_actions_rounded,
                accentColor: const Color(0xFFD4AF37),
                bgColor: const Color(0xFFFFFBEB),
                borderColor: const Color(0xFFFDE68A),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: 'Decreed & Closed',
                count: closedCount < 0 ? '0' : closedCount.toString(),
                subtitle: 'Final judgments & archived matters',
                icon: Icons.verified_rounded,
                accentColor: const Color(0xFF0F172A),
                bgColor: Colors.white,
                borderColor: const Color(0xFFE2E8F0),
              ),
            ),
          ],
        );
      },
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05);
  }

  Widget _buildMetricCard({
    required String title,
    required String count,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
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

  // ─── 3. Controls Row (Search, Filters, View Switcher) ───
  Widget _buildControlsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 750;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Search Input Bar
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Montserrat', fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'Search by case title, court, CNR, client name...',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Montserrat', fontSize: 13),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF0F172A), size: 18),
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
                  if (!isMobile) ...[
                    const SizedBox(width: 16),
                    _buildStatusFilterPills(),
                    const SizedBox(width: 16),
                    _buildViewSwitcher(),
                  ],
                ],
              ),
              if (isMobile) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatusFilterPills(),
                    _buildViewSwitcher(),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusFilterPills() {
    final filters = ['All', 'Active', 'Pending', 'Closed'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: filters.map((f) {
        final isSelected = _selectedStatusFilter == f;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() => _selectedStatusFilter = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
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
          ),
        );
      }).toList(),
    );
  }

  Widget _buildViewSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.grid_view_rounded, size: 18, color: _isGridView ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)),
            onPressed: () => setState(() => _isGridView = true),
            tooltip: 'Grid Cards View',
          ),
          Container(width: 1, height: 20, color: const Color(0xFFE2E8F0)),
          IconButton(
            icon: Icon(Icons.table_rows_rounded, size: 18, color: !_isGridView ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)),
            onPressed: () => setState(() => _isGridView = false),
            tooltip: 'Ledger Table View',
          ),
        ],
      ),
    );
  }

  // ─── 4. Grid View ───
  Widget _buildGridView() {
    final filtered = _filteredCases;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 220,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final caseData = filtered[index];
            return _buildExecutiveCaseCard(caseData, index);
          },
        );
      },
    );
  }

  Widget _buildExecutiveCaseCard(Map<String, dynamic> caseData, int index) {
    final title = caseData['case_title'] ?? caseData['title'] ?? 'Untitled Case';
    final status = caseData['case_status'] ?? caseData['status'] ?? 'Pending';
    final court = caseData['court_name'] ?? caseData['court_details'] ?? 'High Court of Kerala';
    final caseNo = caseData['court_case_number'] ?? caseData['case_number'] ?? 'CU-2026-REG';
    final clientName = caseData['client_name'] ?? 'Direct Client';
    
    int activeStep = 0;
    try {
      if (caseData['notes'] != null) {
        final notesData = jsonDecode(caseData['notes'].toString());
        activeStep = notesData['active_step'] ?? 0;
      }
    } catch (_) {}

    final stepTitles = [
      'Consultation', 'Doc Collection', 'Drafting', 'Filing',
      'Admission', 'Pleadings', 'Issues', 'Evidence',
      'Arguments', 'Judgment', 'Billing', 'Closed'
    ];
    final calculatedStage = activeStep >= 0 && activeStep < stepTitles.length ? stepTitles[activeStep] : 'In Progress';
    final currentStage = caseData['current_stage'] ?? calculatedStage;
    final bool isActive = ['open', 'active', 'ongoing', 'pending'].contains(status.toString().toLowerCase());

    // Format Created Date
    final rawCreated = caseData['createdAt'] ?? caseData['created_at'];
    String createdStr = 'Recent';
    if (rawCreated != null && rawCreated.toString().isNotEmpty) {
      try {
        final dt = DateTime.parse(rawCreated.toString());
        createdStr = DateFormat('dd MMM yyyy').format(dt);
      } catch (_) {}
    }

    // Format Next Hearing Date
    final rawNextHearing = caseData['next_hearing_date'] ?? caseData['nextHearingDate'];
    String hearingStr = 'Not Scheduled';
    if (rawNextHearing != null && rawNextHearing.toString().trim().isNotEmpty) {
      try {
        final dt = DateTime.parse(rawNextHearing.toString());
        hearingStr = DateFormat('dd MMM yyyy').format(dt);
      } catch (_) {
        hearingStr = rawNextHearing.toString();
      }
    }

    // Format Handler / Staff (Care Of)
    final rawHandler = caseData['assigned_counsel'] ??
        caseData['created_by'] ??
        caseData['assignee_email'] ??
        caseData['lawyer_name'] ??
        'Unassigned';

    final String handlerDisplay = _formatHandlerName(rawHandler);

    // Format Handling Lawyer
    final rawHandling = caseData['handling_lawyer'] ??
        caseData['handling_staff'] ??
        caseData['responsible_staff'] ??
        '';
    final String handlingDisplay = _formatHandlerName(rawHandling);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => CaseManagementScreen(existingCase: caseData)),
          ).then((_) => _fetchCases());
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Top Row
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
                    ),
                    child: Center(
                      child: Text(
                        title.isNotEmpty ? title[0].toUpperCase() : 'C',
                        style: GoogleFonts.cormorantGaramond(
                          color: const Color(0xFFD4AF37),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$clientName • $court',
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFFFEF3C7) : const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isActive ? const Color(0xFFF59E0B) : const Color(0xFF8B5CF6)),
                    ),
                    child: Text(
                      status.toString().toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isActive ? const Color(0xFFB45309) : const Color(0xFF6D28D9),
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Case Info Pills Row
              Row(
                children: [
                  _buildTagPill(Icons.tag_rounded, caseNo),
                  const SizedBox(width: 8),
                  _buildTagPill(Icons.balance_rounded, court),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),

              // Basic Details Rows (Handling, Care Of, Created Date)
              if (handlingDisplay.isNotEmpty && handlingDisplay != 'Unassigned') ...[
                Row(
                  children: [
                    const Icon(Icons.gavel_rounded, size: 13, color: Color(0xFF0F172A)),
                    const SizedBox(width: 4),
                    Text(
                      'Handled By: $handlingDisplay',
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 13, color: Color(0xFF0F172A)),
                      const SizedBox(width: 4),
                      Text(
                        'Care Of: $handlerDisplay',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        'Created: $createdStr',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Next Hearing Date & Stage Badge Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_available_rounded, size: 13, color: Color(0xFFB45309)),
                      const SizedBox(width: 4),
                      Text(
                        'Next Hearing: $hearingStr',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: hearingStr != 'Not Scheduled' ? const Color(0xFFB45309) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'STAGE: ${currentStage.toString().toUpperCase()}',
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 40 * index), duration: 300.ms).slideY(begin: 0.05);
  }

  Widget _buildTagPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 5. Ledger Table View ───
  Widget _buildTableLedgerView() {
    final filtered = _filteredCases;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
            headingTextStyle: GoogleFonts.cormorantGaramond(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
            dataRowMaxHeight: 65,
            columns: const [
              DataColumn(label: Text('CASE TITLE & ID')),
              DataColumn(label: Text('CLIENT')),
              DataColumn(label: Text('COURT NAME')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: filtered.map((c) {
              final title = c['case_title'] ?? c['title'] ?? 'Untitled';
              final client = c['client_name'] ?? 'N/A';
              final court = c['court_name'] ?? 'High Court';
              final status = c['case_status'] ?? 'Pending';
              final bool isActive = ['open', 'active', 'ongoing'].contains(status.toString().toLowerCase());

              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              title[0].toUpperCase(),
                              style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      client,
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, color: Color(0xFF334155)),
                    ),
                  ),
                  DataCell(
                    Text(
                      court,
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, color: Color(0xFF334155)),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFF0FDF4) : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive ? const Color(0xFF16A34A) : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF0F172A)),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => CaseManagementScreen(existingCase: c)),
                        ).then((_) => _fetchCases());
                      },
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFF0F172A)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.folder_open_rounded, size: 64, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            const Text(
              'No active cases found for this criteria.',
              style: TextStyle(fontFamily: 'Montserrat', color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text(
              'Create a new Workfile to register a case.',
              style: TextStyle(fontFamily: 'Montserrat', color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 56, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              'No Matching Cases Found',
              style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try clearing your search query or changing filters.',
              style: TextStyle(fontFamily: 'Montserrat', color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
