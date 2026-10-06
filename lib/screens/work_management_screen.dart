import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../models/deal.dart';
import '../models/deal_activity.dart';
import '../services/deal_service.dart';
import 'deal_detail_screen.dart';
import 'word_webview_screen.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive.dart';

class WorkManagementScreen extends StatefulWidget {
  final bool showOnlyVerification;
  const WorkManagementScreen({super.key, this.showOnlyVerification = false});

  @override
  State<WorkManagementScreen> createState() => _WorkManagementScreenState();
}

class _WorkManagementScreenState extends State<WorkManagementScreen> {
  final _dealService = DealService();
  List<Deal> _allDeals = [];
  bool _isLoading = true;

  String _searchQuery = '';
  bool _showOnlyMyWorks = false;
  int? _currentUserId;
  StreamSubscription? _dealsSubscription;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _subscribeToDeals();
  }

  void _subscribeToDeals() {
    setState(() => _isLoading = true);
    _dealsSubscription = _dealService.getDealsStream().listen((deals) {
      if (mounted) {
        setState(() {
          _allDeals = deals;
          _isLoading = false;
        });
      }
    }, onError: (e) {
      debugPrint('Error loading deals: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _dealsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currentUserId = prefs.getInt('current_user_id');
      });
    }
  }

  Future<void> _refreshDeals() async {
    try {
      final deals = await _dealService.getAllDeals();
      if (mounted) {
        setState(() {
          _allDeals = deals;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing deals: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openDealDetail([Deal? deal]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DealDetailScreen(deal: deal),
      ),
    ).then((_) => _refreshDeals());
  }

  Future<void> _deleteDeal(Deal deal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Work'),
        content: Text('Are you sure you want to delete "${deal.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dealService.deleteDeal(deal.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Work deleted successfully'), backgroundColor: Colors.green),
          );
          _refreshDeals();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting work: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _handleVerification(Deal deal, bool isVerified) async {
    if (isVerified) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Verification'),
          content: const Text('Are you sure you want to verify this work and move it to the next stage?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('VERIFY')
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        await _dealService.addActivity(DealActivity(
          dealId: deal.id!,
          type: 'note',
          title: 'Work Verified',
          description: 'Work verified by manager/admin.',
          createdBy: _currentUserId ?? 1,
        ));
        await _dealService.moveDealToStage(deal.id!, 'Verification', 'Invoice');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Work Verified! Moved to Invoice stage.'), backgroundColor: Colors.green));
          _refreshDeals();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } else {
      final remarkController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not Verified'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please provide remarks for reverification:'),
              const SizedBox(height: 12),
              TextField(
                controller: remarkController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter remarks...',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('SUBMIT')
            ),
          ],
        ),
      );

      if (confirmed == true && remarkController.text.trim().isNotEmpty) {
        try {
          await _dealService.addActivity(DealActivity(
            dealId: deal.id!,
            type: 'note',
            title: 'Reverification Needed',
            description: 'Returned for reverification. Remarks: ${remarkController.text.trim()}',
            createdBy: _currentUserId ?? 1,
          ));
          await _dealService.moveDealToStage(deal.id!, 'Verification', 'In Progress');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent for reverification'), backgroundColor: Colors.orange));
            _refreshDeals();
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      } else if (confirmed == true && remarkController.text.trim().isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remarks are required'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width > 900;
    
    return ResponsiveScaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.all(isWide ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPremiumHeader(),
            const SizedBox(height: 24),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshDeals,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : () {
                        var list = _allDeals;
                        if (widget.showOnlyVerification) {
                          list = list.where((d) => d.stage.toLowerCase() == 'verification').toList();
                        }
                        if (_showOnlyMyWorks && _currentUserId != null) {
                          list = list.where((d) => d.responsibleId?.toString() == _currentUserId.toString()).toList();
                        }
                        return list.isEmpty
                            ? _buildEmptyState()
                            : _buildPremiumListView(MediaQuery.of(context).size.width > 1100);
                      }(),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildPremiumHeader() {
    final bool isWide = MediaQuery.of(context).size.width > 600;
    final isVerification = widget.showOnlyVerification;
    
    return Container(
      padding: EdgeInsets.all(isWide ? 32 : 20),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVerification ? 'Verification Workspace' : 'Work Management',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVerification ? 'Review and verify peer draft completions' : 'Manage project pipelines',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (isWide && !isVerification) _buildCreateButton(),
            ],
          ),
          if (!isWide && !isVerification) ...[
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: _buildCreateButton()),
          ],
          const SizedBox(height: 16),
          _buildMyWorksToggle(),
          const SizedBox(height: 16),
          _buildSearchAndFilter(isWide),
        ],
      ),
    );
  }

  Widget _buildCreateButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.goldGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ElevatedButton.icon(
        onPressed: () => _openDealDetail(),
        icon: const Icon(Icons.add_rounded, color: AppTheme.surfaceColor),
        label: const Text('CREATE NEW WORK', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(bool isWide) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.secondaryColor),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: const InputDecoration(
                    hintText: 'Search deals...',
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
            if (isWide) ...[
              const SizedBox(width: 16),
              _filterIconButton(Icons.filter_list_rounded, 'Filter'),
            ],
          ],
        ),
        if (!isWide) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _filterIconButton(Icons.filter_list_rounded, 'Filter', showLabel: true)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _filterIconButton(IconData icon, String label, {bool showLabel = false}) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.secondaryColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppTheme.textSecondary),
              if (showLabel) ...[
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyWorksToggle() {
    return Row(
      children: [
        FilterChip(
          selected: _showOnlyMyWorks,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showOnlyMyWorks ? Icons.person : Icons.person_outline,
                size: 16,
                color: _showOnlyMyWorks ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'My Works Only',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _showOnlyMyWorks ? Colors.white : AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          selectedColor: AppTheme.primaryColor,
          backgroundColor: AppTheme.surfaceColor,
          side: BorderSide(color: _showOnlyMyWorks ? AppTheme.primaryColor : Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          showCheckmark: false,
          onSelected: (val) => setState(() => _showOnlyMyWorks = val),
        ),
        if (_showOnlyMyWorks) ...[
          const SizedBox(width: 12),
          Text(
            'Showing works assigned to you',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _buildPremiumListView(bool isWide) {
    var deals = _allDeals;
    if (widget.showOnlyVerification) {
      deals = deals.where((d) => d.stage.toLowerCase() == 'verification').toList();
    }
    if (_showOnlyMyWorks && _currentUserId != null) {
      deals = deals.where((d) => d.responsibleId?.toString() == _currentUserId.toString()).toList();
    }
    
    final filteredDeals = deals.where((d) => 
      d.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
      (d.clientName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
    ).toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 16),
      child: Column(
        children: [
          if (isWide) _buildTableHeader(isWide),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              itemCount: filteredDeals.length,
              itemBuilder: (context, index) {
                return _buildDealRow(filteredDeals[index], index, isWide);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isWide) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(widget.showOnlyVerification ? 'DOCUMENT' : 'DEAL NAME', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1))),
          if (widget.showOnlyVerification) ...[
            const Expanded(flex: 2, child: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1))),
          ],
          if (!widget.showOnlyVerification) ...[
            Expanded(flex: 2, child: Text(isWide ? 'PIPELINE STAGE' : 'STAGE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1))),
            Expanded(flex: 2, child: Text(isWide ? 'CLIENT' : 'INFO', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1))),
            if (isWide) ...[
              const Expanded(flex: 1, child: Text('DAYS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1))),
              const Expanded(flex: 1, child: Text('AMOUNT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1))),
              const Expanded(flex: 1, child: Text('LEAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1))),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDealRow(Deal deal, int index, bool isWide) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
      ),
      child: InkWell(
        onTap: () => _openDealDetail(deal),
        child: isWide 
          ? Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: widget.showOnlyVerification 
                              ? _buildVerificationDocInfo(deal)
                              : Text(
                                  deal.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.black,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                          ),
                          if (deal.isAdjourned) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Text(
                                'ADJOURNED',
                                style: TextStyle(
                                  color: Colors.amber.shade900,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!widget.showOnlyVerification) ...[
                        const SizedBox(height: 4),
                        Text(deal.workType ?? 'General Work', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                if (widget.showOnlyVerification) ...[
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          onPressed: () => _handleVerification(deal, true),
                          child: const Text('Verified', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          onPressed: () => _handleVerification(deal, false),
                          child: const Text('Not Verified', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!widget.showOnlyVerification) ...[
                  Expanded(
                    flex: 2,
                    child: _buildStageProgress(deal.stage),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(child: Text(deal.clientName ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  if (isWide) ...[
                    Expanded(
                      flex: 1,
                      child: _buildDaysColumn(deal),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        '₹${NumberFormat('#,##,###').format(deal.amount)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: AppTheme.accentColor.withValues(alpha: 0.1),
                            child: Text(deal.responsibleName?[0].toUpperCase() ?? '?', style: const TextStyle(fontSize: 10, color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(deal.responsibleName?.split(' ')[0] ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () => _deleteDeal(deal),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        deal.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _deleteDeal(deal),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                if (deal.isAdjourned)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Text(
                      'ADJOURNED',
                      style: TextStyle(color: Colors.amber.shade900, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                if (!widget.showOnlyVerification) ...[
                  Text(deal.workType ?? 'General Work', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(deal.clientName ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStageProgress(deal.stage),
                ] else ...[
                  const SizedBox(height: 12),
                  _buildVerificationDocInfo(deal),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                          onPressed: () => _handleVerification(deal, true),
                          child: const Text('Verified', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          onPressed: () => _handleVerification(deal, false),
                          child: const Text('Not Verified', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ]
              ],
            ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1);
  }

  Widget _buildVerificationDocInfo(Deal deal) {
    List<Map<String, String>> docs = [];
    if (deal.driveLink != null && deal.driveLink!.isNotEmpty) {
      try {
        final List<dynamic> parsed = jsonDecode(deal.driveLink!);
        for (var item in parsed) {
          docs.add({"name": item["name"].toString(), "url": item["url"].toString()});
        }
      } catch (e) {
        docs.add({"name": "Connected Document", "url": deal.driveLink!});
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (docs.isEmpty)
          const Text('No Document Linked', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: docs.map((doc) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => WordWebviewScreen(url: doc['url']!, title: doc['name'] ?? 'Document')));
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.description_outlined, size: 16, color: AppTheme.accentColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        doc['name'] ?? 'Document',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.accentColor, decoration: TextDecoration.underline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )).toList(),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.person_pin_circle_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              'Assigned by: ${deal.responsibleName?.split(' ')[0] ?? 'Unknown'}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDaysColumn(Deal deal) {
    if (deal.createdAt == null) {
      return Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13));
    }
    final days = DateTime.now().difference(deal.createdAt!).inDays;
    final Color bgColor;
    final Color textColor;
    if (days <= 7) {
      bgColor = const Color(0xFF10B981).withValues(alpha: 0.2);
      textColor = const Color(0xFF10B981);
    } else if (days <= 30) {
      bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.2);
      textColor = const Color(0xFFF59E0B);
    } else {
      bgColor = const Color(0xFFEF4444).withValues(alpha: 0.2);
      textColor = const Color(0xFFEF4444);
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            days == 0 ? 'Today' : days == 1 ? '1 day' : '$days days',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
          ),
        ),
      ],
    );
  }

  Widget _buildStageProgress(String stage) {
    final idx = stage == 'Completed' ? Deal.stages.length : Deal.stages.indexOf(stage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(stage.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(Deal.stages.length, (i) {
            final isPast = i < idx;
            final isCurrent = i == idx;
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: isPast || isCurrent ? AppTheme.accentColor : AppTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final isVerification = widget.showOnlyVerification;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 40)],
              ),
              child: Icon(
                isVerification ? Icons.verified_user_rounded : Icons.work_history_outlined,
                size: 80,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              isVerification ? 'No drafts pending verification' : 'No projects found',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isVerification
                  ? 'All peer work drafts are verified and up to date!'
                  : 'Start your first deal to see it in the pipeline tracker',
              style: const TextStyle(color: Colors.grey),
            ),
            if (!isVerification) ...[
              const SizedBox(height: 40),
              _buildCreateButton(),
            ],
          ],
        ).animate().fadeIn(duration: 600.ms).scale(begin: const Offset(0.9, 0.9)),
      ),
    );
  }
}

