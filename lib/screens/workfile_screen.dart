import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/case_service.dart';
import 'workfile_wizard_screen.dart';
import 'workfile_details_dialog.dart';
import '../widgets/responsive.dart';
import '../widgets/excel_import_dialog.dart';

class WorkfileScreen extends StatefulWidget {
  const WorkfileScreen({super.key});

  @override
  State<WorkfileScreen> createState() => _WorkfileScreenState();
}

class _WorkfileScreenState extends State<WorkfileScreen> {
  List<Map<String, dynamic>> _workfiles = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Open', 'Closed'

  @override
  void initState() {
    super.initState();
    _fetchWorkfiles();
  }

  Future<void> _fetchWorkfiles() async {
    setState(() => _isLoading = true);
    try {
      final allCases = await CaseService.getCases();
      final List<Map<String, dynamic>> workfiles = [];
      for (var c in allCases) {
        if (c['case_description'] != null && c['case_description'].toString().isNotEmpty) {
          try {
            final dataMap = jsonDecode(c['case_description']);
            if (dataMap['workfile_no'] != null) {
              workfiles.add(c);
            }
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _workfiles = workfiles;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading workfiles: $e')));
      }
    }
  }

  bool _isWorkfileClosed(Map<String, dynamic> w) {
    final status = (w['case_status'] ?? w['status'] ?? '').toString().trim().toLowerCase();
    return status == 'closed' || status == 'completed' || status == 'disposed';
  }

  List<Map<String, dynamic>> get _filteredWorkfiles {
    return _workfiles.where((w) {
      // 1. Filter by status filter tab
      final isClosed = _isWorkfileClosed(w);
      if (_selectedFilter == 'Open' && isClosed) return false;
      if (_selectedFilter == 'Closed' && !isClosed) return false;

      // 2. Filter by search query
      if (_searchQuery.isNotEmpty) {
        final title = (w['case_title'] ?? w['title'] ?? '').toString().toLowerCase();
        final client = (w['client_name'] ?? '').toString().toLowerCase();
        final caseType = (w['case_type'] ?? '').toString().toLowerCase();
        String workfileNo = '';
        String year = (w['year'] ?? w['case_year'] ?? '').toString().toLowerCase();
        String court = (w['court_details'] ?? w['court_name'] ?? w['court'] ?? '').toString().toLowerCase();
        if (w['case_description'] != null) {
          try {
            final map = jsonDecode(w['case_description']);
            workfileNo = (map['workfile_no'] ?? '').toString().toLowerCase();
            if (year.isEmpty) year = (map['year'] ?? map['case_year'] ?? '').toString().toLowerCase();
            if (court.isEmpty) court = (map['court'] ?? map['court_name'] ?? '').toString().toLowerCase();
          } catch (_) {}
        }
        final q = _searchQuery.toLowerCase();
        return title.contains(q) || client.contains(q) || caseType.contains(q) || workfileNo.contains(q) || year.contains(q) || court.contains(q);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Executive Pristine Canvas
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Executive Glass Header ───
            _buildHeader(),

            // ─── Filter Tabs & Search Bar ───
            if (!_isLoading && _workfiles.isNotEmpty) ...[
              _buildFilterAndSearchSection(),
            ],

            // ─── Content ───
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _workfiles.isEmpty
                      ? _buildEmptyState()
                      : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 650;
      return Container(
        padding: EdgeInsets.fromLTRB(
          isNarrow ? 20 : 36,
          isNarrow ? 20 : 24,
          isNarrow ? 20 : 36,
          isNarrow ? 20 : 24,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildBackButton(),
                      const SizedBox(width: 14),
                      Expanded(child: _buildHeaderTitleText(isNarrow: true)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildImportButton(),
                      const SizedBox(width: 10),
                      _buildNewWorkfileButton(),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  _buildBackButton(),
                  const SizedBox(width: 18),
                  Expanded(child: _buildHeaderTitleText(isNarrow: false)),
                  _buildImportButton(),
                  const SizedBox(width: 10),
                  _buildNewWorkfileButton(),
                ],
              ),
      ).animate().fadeIn(duration: 250.ms);
    });
  }

  Widget _buildBackButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF334155),
            size: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderTitleText({required bool isNarrow}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Workfiles',
              style: GoogleFonts.montserrat(
                color: const Color(0xFF0F172A),
                fontSize: isNarrow ? 20 : 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'Vault',
                style: GoogleFonts.montserrat(
                  color: const Color(0xFF475569),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Manage active case workfiles and legal document vaults',
          style: GoogleFonts.montserrat(
            color: const Color(0xFF64748B),
            fontSize: isNarrow ? 12 : 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildImportButton() {
    return _HoverableButton(
      onTap: _openExcelImport,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFC5A059),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC5A059).withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              'Import Excel',
              style: GoogleFonts.montserrat(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewWorkfileButton() {
    return _HoverableButton(
      onTap: _openWizard,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              'New Workfile',
              style: GoogleFonts.montserrat(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterAndSearchSection() {
    final totalCount = _workfiles.length;
    final closedCount = _workfiles.where(_isWorkfileClosed).length;
    final openCount = totalCount - closedCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilterTabs(totalCount, openCount, closedCount),
                const SizedBox(height: 12),
                _buildSearchBarInput(),
              ],
            );
          }
          return Row(
            children: [
              _buildFilterTabs(totalCount, openCount, closedCount),
              const SizedBox(width: 16),
              Expanded(child: _buildSearchBarInput()),
            ],
          );
        },
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildFilterTabs(int total, int open, int closed) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilterChip('All', 'Total', total),
          const SizedBox(width: 4),
          _buildFilterChip('Open', 'Open', open),
          const SizedBox(width: 4),
          _buildFilterChip('Closed', 'Closed', closed),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, int count) {
    final isSelected = _selectedFilter == filterKey;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = filterKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.montserrat(
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: GoogleFonts.montserrat(
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBarInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.montserrat(
          color: const Color(0xFF0F172A),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search workfiles by title, client, type, or #ID...',
          hintStyle: GoogleFonts.montserrat(
            color: const Color(0xFF94A3B8),
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF64748B),
            size: 18,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF64748B)),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: Color(0xFF0F172A),
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading workfiles...',
            style: GoogleFonts.montserrat(
              color: const Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _openWizard() async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: const SizedBox(
          width: 880,
          height: 680,
          child: WorkfileWizardScreen(),
        ),
      ),
    );
    _fetchWorkfiles();
  }

  void _openExcelImport() async {
    final updated = await ExcelImportDialog.show(context);
    if (updated == true) {
      _fetchWorkfiles();
    }
  }

  Widget _buildEmptyState() {
    final hasFilters = _searchQuery.isNotEmpty || _selectedFilter != 'All';
    String emptyTitle = 'No Workfiles Found';
    String emptySubtitle = 'Create your first workfile to organize cases and legal document vaults.';

    if (_searchQuery.isNotEmpty) {
      emptyTitle = 'No Matching Workfiles';
      emptySubtitle = 'Try adjusting your search terms or filters.';
    } else if (_selectedFilter != 'All') {
      emptyTitle = 'No $_selectedFilter Workfiles';
      emptySubtitle = 'There are currently no ${_selectedFilter.toLowerCase()} workfiles available.';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              size: 40,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            emptyTitle,
            style: GoogleFonts.montserrat(
              color: const Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            emptySubtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: const Color(0xFF64748B),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (!hasFilters) ...[
            const SizedBox(height: 24),
            _HoverableButton(
              onTap: _openWizard,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Create First Workfile',
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    final filtered = _filteredWorkfiles;
    if (filtered.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(36, 12, 36, 36),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final workfile = filtered[index];
        return _WorkfileCardItem(
          key: ValueKey(workfile['id'] ?? index),
          workfile: workfile,
          index: index,
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.3),
              builder: (_) => WorkfileDetailsDialog(workfile: workfile),
            ).then((_) => _fetchWorkfiles());
          },
        );
      },
    );
  }
}

class _WorkfileCardItem extends StatefulWidget {
  final Map<String, dynamic> workfile;
  final int index;
  final VoidCallback onTap;

  const _WorkfileCardItem({
    super.key,
    required this.workfile,
    required this.index,
    required this.onTap,
  });

  @override
  State<_WorkfileCardItem> createState() => _WorkfileCardItemState();
}

class _WorkfileCardItemState extends State<_WorkfileCardItem> {
  bool _isHovered = false;

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
    final clientName = widget.workfile['client_name'] ?? '';
    final caseType = widget.workfile['case_type'] ?? '';
    final statusRaw = (widget.workfile['case_status'] ?? widget.workfile['status'] ?? 'Open').toString();
    final statusLower = statusRaw.trim().toLowerCase();
    final isClosed = statusLower == 'closed' || statusLower == 'completed' || statusLower == 'disposed';
    final isOpen = !isClosed;
    final status = statusRaw.isNotEmpty ? statusRaw : (isOpen ? 'Open' : 'Closed');
    final createdAt = widget.workfile['created_at']?.toString() ?? '';
    String dateLabel = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        dateLabel = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {}
    }

    final String initialChar = title.isNotEmpty ? title[0].toUpperCase() : 'W';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _isHovered ? 1.01 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isHovered ? const Color(0xFFD4AF37) : const Color(0xFFE2E8F0),
                width: _isHovered ? 1.2 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.08 : 0.015),
                  blurRadius: _isHovered ? 16 : 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Sleek Monogram Badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Center(
                    child: Text(
                      initialChar,
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Middle Content Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: GoogleFonts.montserrat(
                                color: const Color(0xFF0F172A),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (workfileNo.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                '#$workfileNo',
                                style: GoogleFonts.montserrat(
                                  color: const Color(0xFF475569),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Detail Metadata Chips Row
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          if (clientName.isNotEmpty)
                            _buildDetailChip(Icons.person_outline_rounded, clientName),
                          if (caseType.isNotEmpty)
                            _buildDetailChip(Icons.gavel_rounded, caseType),
                          if (year.isNotEmpty)
                            _buildDetailChip(Icons.calendar_month_rounded, 'Year: $year'),
                          if (court.isNotEmpty)
                            _buildDetailChip(Icons.account_balance_rounded, court),
                          if (clientStatus.isNotEmpty)
                            _buildDetailChip(Icons.verified_user_outlined, 'Status: $clientStatus'),
                          if (dateLabel.isNotEmpty)
                            _buildDetailChip(Icons.calendar_today_rounded, dateLabel),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Right Status Badge & Arrow
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOpen ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isOpen ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOpen ? const Color(0xFF10B981) : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status,
                            style: GoogleFonts.montserrat(
                              color: isOpen ? const Color(0xFF047857) : const Color(0xFF475569),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isHovered ? const Color(0xFFD4AF37) : const Color(0xFFF8FAFC),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isHovered ? const Color(0xFFD4AF37) : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: _isHovered ? [
                          BoxShadow(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ] : [],
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: _isHovered ? Colors.white : const Color(0xFF64748B),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildDetailChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.montserrat(
              color: const Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _HoverableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _HoverableButton({required this.child, required this.onTap});

  @override
  State<_HoverableButton> createState() => _HoverableButtonState();
}

class _HoverableButtonState extends State<_HoverableButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _isHovered ? 1.02 : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}

