import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../theme/app_theme.dart';
import '../models/billing.dart';
import '../services/billing_service.dart';
import '../services/client_service.dart';
import '../services/excel_service.dart';
import '../services/logging_service.dart';
import '../services/invoice_pdf_service.dart';
import '../services/user_service.dart';
import 'dart:convert';
import '../utils/number_to_words.dart';
import '../utils/display_name_helper.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/role_service.dart';
import '../widgets/responsive.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class BillingScreen extends StatefulWidget {
  final String? initialClientName;
  final String? linkedCaseId;

  const BillingScreen({super.key, this.initialClientName, this.linkedCaseId});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _billingService = BillingService();
  final _clientService = ClientService();
  final _excel = ExcelService();
  final _log = LoggingService();

  List<Billing> _billings = [];
  bool _isLoading = true;
  int _limit = 50;
  int _offset = 0;
  bool _hasMore = true;
  String _searchTerm = '';
  final FocusNode _searchFocusNode = FocusNode();
  String _statusFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;

  int _totalInvoices = 0;
  int _totalPaid = 0;
  int _totalPending = 0;
  String _userRole = 'Staff';

  static const staffMapping = {
    'Sarath': 'A',
    'Jesna': 'B',
    'Soumya': 'C',
    'Nithya': 'D',
    'Irshad': 'E',
    'Construction & Supervising': 'F',
    'Aswini': 'G',
    'Ashwini': 'G',
    'Jitha': 'J',
    'Darshana': 'I',
    'Jayan & Midhun': 'VP',
  };

  @override
  void initState() { 
    super.initState(); 
    _initRole();
    _fetchBillings(refresh: true); 
  }

  Future<void> _initRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userRole = prefs.getString('user_role') ?? 'Staff';
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _getFullAuthorityName(String? auth, [String? invNo]) {
    if (auth == null || auth.isEmpty) {
      if (invNo != null) {
        auth = invNo.split(RegExp(r'[ \-]')).first;
      } else {
        return '-';
      }
    }
    if (auth == 'CUC') return 'Cochin United Legal LLP';
    
    // Check if it's a shorthand prefix and try to match with a staff name
    final prefix = auth.split(RegExp(r'[ \-]')).first.toUpperCase();
    
    final match = staffMapping.keys.firstWhere(
      (k) => staffMapping[k] == prefix || k.toUpperCase() == prefix || k.toUpperCase().contains(prefix) || prefix.contains(k.toUpperCase()), 
      orElse: () => ''
    );
    if (match.isNotEmpty) return '${staffMapping[match] ?? prefix} - $match';
    
    return auth;
  }

  Future<void> _fetchStats() async {
    try {
      final stats = await _billingService.fetchStats();
      if (mounted) {
        setState(() {
          _totalInvoices = stats['total']!;
          _totalPaid = stats['paid']!;
          _totalPending = stats['pending']!;
        });
      }
    } catch (_) {}
  }

  Future<void> _syncClientBalance(String clientName) async {
    await _billingService.syncClientBalance(clientName);
  }

  Future<void> _fetchBillings({bool refresh = false}) async {
    if (refresh) {
      _offset = 0;
      _hasMore = true;
      _billings.clear();
      _fetchStats();
    }
    if (!_hasMore) return;
    
    setState(() => _isLoading = true);
    try {
      final fetched = await _billingService.fetchBillings(
        limit: _limit,
        offset: _offset,
        statusFilter: _statusFilter,
        startDate: _startDate,
        endDate: _endDate,
        caseIdFilter: widget.linkedCaseId,
      );
      
      if (mounted) {
        setState(() { 
          if (refresh) {
            _billings = fetched;
          } else {
            _billings.addAll(fetched);
          }
          _offset += fetched.length;
          if (fetched.length < _limit) _hasMore = false;
        });
      }
    } catch (e) { _msg('Failed: $e', false); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _markPaid(Billing b) async {
    double grandTotal = NumberToWords.parseCurrency(b.grandTotal > 0 ? b.grandTotal.toString() : (b.amount ?? '0'));
    double previouslyReceived = NumberToWords.parseCurrency(b.data?['advance_received']?.toString() ?? '0');
    double currentBalance = grandTotal - previouslyReceived;
    
    if (currentBalance <= 0) {
      _msg('This invoice is already fully paid.', true);
      return;
    }

    bool isFullPayment = true;
    final receivedController = TextEditingController(text: currentBalance.toStringAsFixed(0));
    double newBalance = 0;

    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
      builder: (context, setState) {
        double receivedAmount = double.tryParse(receivedController.text) ?? 0;
        newBalance = currentBalance - receivedAmount;
        if (newBalance < 0) newBalance = 0;

        return AlertDialog(
          title: const Text('Confirm Payment', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Outstanding Balance: ₹${NumberToWords.formatIndianCurrency(currentBalance).replaceAll('/-', '')}'),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Full Payment Received?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                value: isFullPayment,
                activeColor: Colors.green,
                onChanged: (val) {
                  setState(() {
                    isFullPayment = val;
                    if (val) {
                      receivedController.text = currentBalance.toStringAsFixed(0);
                    } else {
                      receivedController.clear();
                    }
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
              if (!isFullPayment) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: receivedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount Received (₹)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text('Remaining Balance: ₹${NumberToWords.formatIndianCurrency(newBalance).replaceAll('/-', '')}', style: TextStyle(color: newBalance > 0 ? Colors.orange.shade700 : Colors.green.shade700, fontWeight: FontWeight.bold)),
              ]
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
          ],
        );
      }
    ));

    if (ok == true) {
      try {
        double newlyReceived = double.tryParse(receivedController.text) ?? 0;
        if (newlyReceived <= 0) return;

        double totalReceived = previouslyReceived + newlyReceived;
        double updatedBalance = grandTotal - totalReceived;
        if (updatedBalance < 0) updatedBalance = 0;

        bool isPaid = updatedBalance <= 0;

        final d = Map<String, dynamic>.from(b.data ?? {});
        d['payment_received'] = isPaid;
        d['advance_received'] = NumberToWords.formatIndianCurrency(totalReceived);
        d['balance_due'] = updatedBalance > 0 ? NumberToWords.formatIndianCurrency(updatedBalance) : '0/-';
        if (isPaid) d['payment_date'] = DateTime.now().toIso8601String();

        await BillingService.updateBilling(b.id!, {
          'status': isPaid ? 'Received' : 'Pending',
          'data': d,
        });
        
        // Update Client balance in database
        if (b.clientName != null && b.clientName!.isNotEmpty) {
           await _syncClientBalance(b.clientName!);
        }

        _fetchBillings(refresh: true); 
        _msg('Payment recorded successfully', true);
        await _log.logAction(action: 'INVOICE_PAYMENT', targetType: 'Invoice', targetId: b.invoiceNo ?? '', details: 'Recorded payment of ₹$newlyReceived');
      } catch (e) { 
        _msg('Failed: $e', false); 
      }
    }
  }

  Future<void> _updateStatus(Billing b, String status) async {
    try {
      await BillingService.updateBilling(b.id!, {'status': status});
      _fetchBillings(refresh: true);
      _msg('Status updated to $status', true);
      await _log.logAction(action: 'INVOICE_STATUS_UPDATED', targetType: 'Invoice', targetId: b.invoiceNo ?? '', details: 'Status changed to $status');
    } catch (e) {
      _msg('Failed: $e', false);
    }
  }

  Future<void> _deleteBilling(Billing b) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Confirm Delete', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
      content: Text('Are you sure you want to delete invoice ${b.invoiceNo}?\nThis action cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(c, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: AppTheme.textPrimary),
          child: const Text('Delete'),
        ),
      ],
    ));
    if (ok == true) {
      try {
        await _billingService.deleteBilling(b.id!);
        if (b.clientName != null && b.clientName!.isNotEmpty) {
           await _syncClientBalance(b.clientName!);
        }
        _fetchBillings(refresh: true); _msg('Invoice deleted', true);
        await _log.logAction(action: 'INVOICE_DELETED', targetType: 'Invoice', targetId: b.invoiceNo ?? '', details: 'Deleted invoice');
      } catch (e) { _msg('Failed: $e', false); }
    }
  }

  Future<void> _duplicateBilling(Billing b) async {
    String nextNo = '';
    final prefix = (b.type == 'QUOTATION') ? 'CC' : 'AA';
    final next = await _billingService.getNextInvoiceNo(prefix);
    if (next != null) nextNo = next;

    final duplicated = Billing(
      clientName: b.clientName,
      invoiceNo: nextNo,
      date: DateFormat('dd/MM/yyyy').format(DateTime.now()),
      amount: b.amount,
      type: b.type,
      category: b.category,
      authorities: b.authorities,
      status: 'Pending',
      data: Map<String, dynamic>.from(b.data ?? {})
        ..remove('payment_received')
        ..remove('advance_received')
        ..remove('payment_date')
        ..remove('balance_due'),
    );

    _openCreator(duplicated);
  }

  Future<void> _convertToInvoice(Billing b) async {
    String nextNo = '';
    const prefix = 'AA';
    final next = await _billingService.getNextInvoiceNo(prefix);
    if (next != null) nextNo = next;

    final converted = Billing(
      clientName: b.clientName,
      invoiceNo: nextNo,
      date: DateFormat('dd/MM/yyyy').format(DateTime.now()),
      amount: b.amount,
      type: 'INVOICE',
      category: b.category,
      authorities: b.authorities,
      status: 'Pending',
      data: Map<String, dynamic>.from(b.data ?? {})
        ..remove('payment_received')
        ..remove('advance_received')
        ..remove('payment_date')
        ..remove('balance_due')
        ..remove('quotation_terms'),
    );

    _openCreator(converted);
  }

  Future<void> _shareViaWhatsApp(Billing b) async {
    if (b.clientName == null || b.clientName!.isEmpty) return;
    try {
      final phone = await _billingService.getClientPhone(b.clientName!);
      if (phone == null || phone.isEmpty) {
        _msg('No phone number found for ${b.clientName}.', false);
        return;
      }
      final typeStr = b.type == 'QUOTATION' ? 'Quotation' : 'Invoice';
      final text = "Hello ${b.clientName},\n\nPlease find your $typeStr (${b.invoiceNo}) for ₹${b.amount} attached.\n\nThank you,\nCochin United Legal LLP";
      final url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(text)}");
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        _msg('Could not launch WhatsApp.', false);
      }
    } catch (e) {
      _msg('Failed to open WhatsApp: $e', false);
    }
  }

  Future<void> _showClientLedger(String clientName) async {
    try {
      final items = await _billingService.getClientLedger(clientName);
      final clients = await _clientService.searchClients(clientName);
      final clientRes = clients.isNotEmpty ? clients.firstWhere((c) => c['name'] == clientName, orElse: () => {}) : {};
      
      String totalBal = '0/-';
      if (clientRes.isNotEmpty && clientRes['balance_due'] != null) {
         totalBal = clientRes['balance_due'].toString();
      }

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200))
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(clientName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        const SizedBox(height: 4),
                        const Text('Billing Ledger & History', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Total Outstanding', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(totalBal, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orange)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final b = items[index];
                    final isPaid = b.data?['payment_received'] == true;
                    return ListTile(
                      title: Text('${b.invoiceNo ?? '-'}  •  ₹${b.amount ?? '0'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${b.date ?? '-'}  •  ${b.type ?? 'INVOICE'}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isPaid ? Colors.green : (b.status == 'Interested' ? Colors.teal : (b.status == 'Not Interested' ? Colors.blueGrey : Colors.orange))).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: Text(isPaid ? 'PAID' : (b.status == 'Interested' ? 'INTERESTED' : (b.status == 'Not Interested' ? 'NOT INT' : 'PENDING')), 
                          style: TextStyle(color: isPaid ? Colors.green : (b.status == 'Interested' ? Colors.teal : (b.status == 'Not Interested' ? Colors.blueGrey : Colors.orange)), fontWeight: FontWeight.bold, fontSize: 10))
                      ),
                    );
                  },
                ),
              ),
            ],
          )
        )
      );
    } catch (e) {
      _msg('Failed to load ledger: $e', false);
    }
  }

  Future<void> _generateReceipt(Billing b) async {
    final auths = b.authorities ?? '';
    final category = b.category ?? 'Legal';
    final items = List<Map<String, dynamic>>.from(b.items ?? []);
    final d = b.data ?? {};
    final amtInWords = b.amountInWords.isEmpty ? NumberToWords.convert(NumberToWords.parseCurrency(b.amount ?? '0').round()) : b.amountInWords;
    
    await InvoicePdfService.printInvoice(
      type: b.type ?? 'INVOICE',
      category: category,
      clientName: b.clientName ?? '',
      clientAddress: d['client_address'] ?? '',
          date: b.date ?? '',
          invoiceNo: b.invoiceNo ?? '',
          authorities: auths,
          items: items,
          totalAmount: b.amount ?? '0/-',
          amountInWords: amtInWords,
          outstandingAmount: '0/-',
          advanceReceived: b.amount ?? '0/-',
          grandTotal: b.amount ?? '0/-',
          balanceDue: '0/-',
          quotationTerms: d['quotation_terms'] != null ? List<String>.from(d['quotation_terms']) : null,
          isReceipt: true,
        );
      }

  void _msg(String t, bool ok) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(t), behavior: SnackBarBehavior.floating, backgroundColor: ok ? Colors.green.shade600 : Colors.redAccent,
  ));

  void _openCreator([Billing? b]) => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => InvoiceCreatorPage(
      billing: b, 
      linkedCaseId: widget.linkedCaseId,
      initialClientName: widget.initialClientName,
      onSaved: (dynamic id) { _fetchBillings(refresh: true); Navigator.pop(context); }
    ),
  ));

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
        backgroundColor: AppTheme.backgroundColor, // Light slate background
        body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): _openCreator,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocusNode.requestFocus(),
        },
        child: Focus(
          autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth > 900;
        final filtered = _billings.where((b) =>
          (b.clientName?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false) ||
          (b.invoiceNo?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false)
        ).toList();
        
        final paidCount = _billings.where((b) => b.data?['payment_received'] == true).length;
        final pendingCount = _billings.length - paidCount;

        return Padding(
          padding: EdgeInsets.all(isWide ? 24 : 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Responsive Header
            if (isWide)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      children: [
                        if (Navigator.canPop(context))
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back_rounded),
                              onPressed: () => Navigator.pop(context),
                              style: IconButton.styleFrom(backgroundColor: AppTheme.surfaceColor, elevation: 2, shadowColor: Colors.black12),
                            ),
                          ),
                        const Text('Invoicing & Billing', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.2, color: AppTheme.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      _statBadge('$_totalInvoices Total', Colors.blue),
                      _statBadge('$_totalPaid Paid', Colors.green),
                      _statBadge('$_totalPending Pending', Colors.orange),
                    ]),
                  ]),
                    Row(children: [
                      Container(
                        height: 45,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _statusFilter,
                            items: ['All', 'Paid', 'Pending', 'Overdue', 'Interested', 'Not Interested'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _statusFilter = v);
                                _fetchBillings(refresh: true);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(Icons.date_range_rounded, 'Filter by Date', _startDate != null ? Colors.blue : Colors.grey, () async {
                         final picked = await showDateRangePicker(
                           context: context,
                           firstDate: DateTime(2020),
                           lastDate: DateTime.now(),
                           initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
                         );
                         if (picked != null) {
                           setState(() { _startDate = picked.start; _endDate = picked.end; });
                           _fetchBillings(refresh: true);
                         } else if (_startDate != null) {
                           setState(() { _startDate = null; _endDate = null; });
                           _fetchBillings(refresh: true);
                         }
                      }),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 240,
                        height: 45,
                        child: Container(
                          decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
                          child: TextField(
                            focusNode: _searchFocusNode,
                            onChanged: (v) => setState(() => _searchTerm = v),
                            decoration: const InputDecoration(hintText: 'Search (Ctrl+F)', prefixIcon: Icon(Icons.search_rounded, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.refresh_rounded, 'Refresh', Colors.blue, _fetchBillings),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.file_download_rounded, 'Export', Colors.green, () async { 
                      try { final p = await _excel.exportBillings(_billings); if (p != null) _msg('Exported to $p', true); } catch (e) { _msg('$e', false); }
                    }),
                    const SizedBox(width: 16),
                    if (RoleService.canManageBilling(_userRole))
                      ElevatedButton.icon(
                        onPressed: () => _openCreator(),
                        icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
                        label: const Text('Create Invoice', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                      ),
                  ]),
                ],
              )
            else ...[
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(backgroundColor: AppTheme.surfaceColor, elevation: 2, shadowColor: Colors.black12),
                        ),
                      ),
                    const Text('Invoicing & Billing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -1.2, color: AppTheme.textPrimary)),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  _statBadge('$_totalInvoices Total', Colors.blue),
                  _statBadge('$_totalPaid Paid', Colors.green),
                  _statBadge('$_totalPending Pending', Colors.orange),
                ]),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Container(
                    height: 45,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _statusFilter,
                        isExpanded: true,
                        items: ['All', 'Paid', 'Pending', 'Overdue', 'Interested', 'Not Interested'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _statusFilter = v);
                            _fetchBillings(refresh: true);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _actionBtn(Icons.date_range_rounded, 'Filter by Date', _startDate != null ? Colors.blue : Colors.grey, () async {
                   final picked = await showDateRangePicker(
                     context: context,
                     firstDate: DateTime(2020),
                     lastDate: DateTime.now(),
                     initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
                   );
                   if (picked != null) {
                     setState(() { _startDate = picked.start; _endDate = picked.end; });
                     _fetchBillings(refresh: true);
                   } else if (_startDate != null) {
                     setState(() { _startDate = null; _endDate = null; });
                     _fetchBillings(refresh: true);
                   }
                }),
                const SizedBox(width: 8),
                _actionBtn(Icons.refresh_rounded, 'Refresh', Colors.blue, () => _fetchBillings(refresh: true)),
                const SizedBox(width: 8),
                _actionBtn(Icons.file_download_rounded, 'Export', Colors.green, () async { 
                  try { final p = await _excel.exportBillings(_billings); if (p != null) _msg('Exported to $p', true); } catch (e) { _msg('$e', false); }
                }),
              ]),
              const SizedBox(height: 12),
              Container(
                height: 45,
                decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
                child: TextField(
                  focusNode: _searchFocusNode,
                  onChanged: (v) => setState(() => _searchTerm = v),
                  decoration: const InputDecoration(hintText: 'Search...', prefixIcon: Icon(Icons.search_rounded, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(height: 12),
              if (RoleService.canManageBilling(_userRole))
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openCreator(),
                    icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
                    label: const Text('CREATE INVOICE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                  ),
                ),
            ],
          const SizedBox(height: 24),
          // List
          Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_rounded, size: 80, color: Colors.grey.shade200),
                const SizedBox(height: 16),
                Text('No records found', style: TextStyle(color: Colors.grey.shade400, fontSize: 18, fontWeight: FontWeight.w500)),
              ]))
            : Card(
                margin: EdgeInsets.zero,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == filtered.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () => _fetchBillings(),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            label: const Text('Load More Invoices', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      );
                    }
                    return _buildInvoiceCard(filtered[i], i, isWide);
                  },
                ),
              ),
          ),
        ]).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
      );
    },
  ))));
}

  Widget _statBadge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w700)),
  );

  Widget _actionBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 22)),
    ),
  );

  Widget _buildInvoiceCard(Billing b, int i, bool isWide) {
    final isPaid = b.data?['payment_received'] == true;
    bool isOverdue = false;
    if (!isPaid && b.date != null && b.date!.isNotEmpty) {
      try {
        final parts = b.date!.split('/');
        if (parts.length == 3) {
          final d = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          if (DateTime.now().difference(d).inDays > 30) {
            isOverdue = true;
          }
        }
      } catch (_) {}
    }
    final typeColor = b.type == 'QUOTATION' ? Colors.purple : AppTheme.primaryColor;
    
    final innerContent = isWide 
      ? Row(children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Icon(b.type == 'QUOTATION' ? Icons.request_quote_rounded : Icons.receipt_long_rounded, color: typeColor, size: 26)),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(b.invoiceNo ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(width: 12),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(b.type ?? 'INVOICE', style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
              if (b.category != null) ...[
                const SizedBox(width: 8),
                Text(b.category!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ]),
            const SizedBox(height: 6),
            InkWell(
              onTap: b.clientName != null ? () => _showClientLedger(b.clientName!) : null,
              child: Text(
                b.clientName ?? 'Unnamed Client', 
                style: TextStyle(fontSize: 14, color: Colors.blue.shade700, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: Colors.blue.shade200)
              ),
            ),
            const SizedBox(height: 2),
            Text('Issued by: ${_getFullAuthorityName(b.authorities, b.invoiceNo)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(b.date ?? '-', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            const SizedBox(height: 4),
            Text(b.amount ?? '0/-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
            if (!isPaid && (b.data?['balance_due']?.isNotEmpty ?? false) && b.data!['balance_due'] != '0/-') ...[
              const SizedBox(height: 2),
              Text('Bal: ${b.data!['balance_due']}', style: TextStyle(color: Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
            ]
          ]),
          const SizedBox(width: 24),
          Container(width: 100, height: 36, alignment: Alignment.center, decoration: BoxDecoration(
            color: (isPaid ? Colors.green : (b.status == 'Interested' ? Colors.teal : (b.status == 'Not Interested' ? Colors.blueGrey : (isOverdue ? Colors.red : Colors.orange)))).withValues(alpha: 0.1), 
            borderRadius: BorderRadius.circular(10)
          ),
            child: Text(isPaid ? 'PAID' : (b.status == 'Interested' ? 'INTERESTED' : (b.status == 'Not Interested' ? 'NOT INTERESTED' : (isOverdue ? 'OVERDUE' : 'PENDING'))), 
              style: TextStyle(color: isPaid ? Colors.green.shade700 : (b.status == 'Interested' ? Colors.teal.shade700 : (b.status == 'Not Interested' ? Colors.blueGrey.shade700 : (isOverdue ? Colors.red.shade700 : Colors.orange.shade700))), fontSize: 10, fontWeight: FontWeight.w900))),
          const SizedBox(width: 12),
          Row(children: [
            IconButton(onPressed: () => _shareViaWhatsApp(b), icon: const Icon(Icons.chat_rounded, color: Colors.green), tooltip: 'Share via WhatsApp'),
            if (!isPaid && b.type != 'QUOTATION') IconButton(onPressed: () => _markPaid(b), icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green), tooltip: 'Mark Paid'),
            if (isPaid) IconButton(onPressed: () => _generateReceipt(b), icon: const Icon(Icons.receipt_rounded, color: Colors.teal), tooltip: 'Generate Receipt'),
            if (b.type == 'QUOTATION') ...[
              IconButton(onPressed: () => _convertToInvoice(b), icon: const Icon(Icons.transform_rounded, color: Colors.deepPurple), tooltip: 'Convert to Invoice'),
              IconButton(onPressed: () => _updateStatus(b, 'Interested'), icon: Icon(Icons.thumb_up_alt_rounded, color: b.status == 'Interested' ? Colors.teal : Colors.grey.shade400, size: 22), tooltip: 'Interested'),
              IconButton(onPressed: () => _updateStatus(b, 'Not Interested'), icon: Icon(Icons.thumb_down_alt_rounded, color: b.status == 'Not Interested' ? Colors.red.shade300 : Colors.grey.shade400, size: 22), tooltip: 'Not Interested'),
            ],
            IconButton(onPressed: () => _duplicateBilling(b), icon: Icon(Icons.copy_rounded, color: Colors.blue.shade300, size: 22), tooltip: 'Duplicate'),
            IconButton(onPressed: () => _openCreator(b), icon: Icon(Icons.edit_note_rounded, color: Colors.grey.shade400, size: 28), tooltip: 'Edit'),
            IconButton(onPressed: () => _deleteBilling(b), icon: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withOpacity(0.5), size: 24), tooltip: 'Delete'),
          ]),
        ])
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                      child: Icon(b.type == 'QUOTATION' ? Icons.request_quote_rounded : Icons.receipt_long_rounded, color: typeColor, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.invoiceNo ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textPrimary), overflow: TextOverflow.ellipsis),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(b.type ?? 'INVOICE', style: TextStyle(color: typeColor, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
                      ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(b.amount ?? '0/-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
                Text(b.date ?? '-', style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
              ]),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: b.clientName != null ? () => _showClientLedger(b.clientName!) : null,
            child: Text(
              b.clientName ?? 'Unnamed Client', 
              style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: Colors.blue.shade200)
            ),
          ),
          const SizedBox(height: 2),
          Text('By: ${_getFullAuthorityName(b.authorities, b.invoiceNo)}', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), alignment: Alignment.center, decoration: BoxDecoration(
                color: (isPaid ? Colors.green : (b.status == 'Interested' ? Colors.teal : (b.status == 'Not Interested' ? Colors.blueGrey : (isOverdue ? Colors.red : Colors.orange)))).withValues(alpha: 0.1), 
                borderRadius: BorderRadius.circular(6)
              ),
                child: Text(isPaid ? 'PAID' : (b.status == 'Interested' ? 'INTERESTED' : (b.status == 'Not Interested' ? 'NOT INT' : (isOverdue ? 'OVERDUE' : 'PENDING'))), 
                  style: TextStyle(color: isPaid ? Colors.green.shade700 : (b.status == 'Interested' ? Colors.teal.shade700 : (b.status == 'Not Interested' ? Colors.blueGrey.shade700 : (isOverdue ? Colors.red.shade700 : Colors.orange.shade700))), fontSize: 9, fontWeight: FontWeight.w900))),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(onPressed: () => _shareViaWhatsApp(b), icon: const Icon(Icons.chat_rounded, color: Colors.green, size: 20), tooltip: 'WhatsApp', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                      if (!isPaid && b.type != 'QUOTATION') IconButton(onPressed: () => _markPaid(b), icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 20), tooltip: 'Mark Paid', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                      if (isPaid) IconButton(onPressed: () => _generateReceipt(b), icon: const Icon(Icons.receipt_rounded, color: Colors.teal, size: 20), tooltip: 'Receipt', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                      if (b.type == 'QUOTATION') ...[
                        IconButton(onPressed: () => _convertToInvoice(b), icon: const Icon(Icons.transform_rounded, color: Colors.deepPurple, size: 20), tooltip: 'Convert', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                        IconButton(onPressed: () => _updateStatus(b, 'Interested'), icon: Icon(Icons.thumb_up_alt_rounded, color: b.status == 'Interested' ? Colors.teal : Colors.grey.shade400, size: 18), tooltip: 'Interested', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                        IconButton(onPressed: () => _updateStatus(b, 'Not Interested'), icon: Icon(Icons.thumb_down_alt_rounded, color: b.status == 'Not Interested' ? Colors.red.shade300 : Colors.grey.shade400, size: 18), tooltip: 'Not Interested', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                      ],
                      IconButton(onPressed: () => _duplicateBilling(b), icon: Icon(Icons.copy_rounded, color: Colors.blue.shade300, size: 20), tooltip: 'Duplicate', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                      IconButton(onPressed: () => _openCreator(b), icon: Icon(Icons.edit_note_rounded, color: Colors.grey.shade400, size: 24), tooltip: 'Edit', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                      IconButton(onPressed: () => _deleteBilling(b), icon: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withOpacity(0.5), size: 20), tooltip: 'Delete', constraints: const BoxConstraints(), padding: const EdgeInsets.all(8)),
                    ],
                  ),
                ),
              ),
            ],
          )
        ]);

    return InkWell(
        onTap: () => _openCreator(b),
        child: Padding(padding: const EdgeInsets.all(18), child: innerContent),
    ).animate().fadeIn(delay: (30 * i).ms, duration: 400.ms).slideX(begin: 0.02, end: 0);
  }
}

// ─── PREMIUM INVOICE CREATOR PAGE ───
class InvoiceCreatorPage extends StatefulWidget {
  final Billing? billing;
  final void Function(dynamic id)? onSaved;
  final String? initialClientName;
  final String? linkedCaseId;

  const InvoiceCreatorPage({
    super.key,
    this.billing,
    this.onSaved,
    this.initialClientName,
    this.linkedCaseId,
  });
  
  // static const auths = ['CUC - Cochin United Legal LLP'];

  @override
  State<InvoiceCreatorPage> createState() => _InvoiceCreatorPageState();
}

class _InvoiceCreatorPageState extends State<InvoiceCreatorPage> {
  late String _type, _category, _authorities, _status;
  late TextEditingController _clientName, _clientAddress, _date, _invoiceNo, _outstanding, _advanceReceived, _promisedDate;
  String? _selectedCaseId;
  final TextEditingController _caseTitleController = TextEditingController();
  late List<Map<String, dynamic>> _items;
  late List<TextEditingController> _itemDescControllers;
  late List<TextEditingController> _itemAmountControllers;
  late List<String> _quotationTerms;
  late List<TextEditingController> _termControllers;
  List<String> _staffs = [];
  List<Map<String, String>> _pastItems = [];
  String _totalAmount = '0/-', _amountInWords = 'Zero', _grandTotal = '', _balanceDue = '';
  final _log = LoggingService();
  final _billingService = BillingService();
  final _clientService = ClientService();
  Timer? _debounceTimer;

  static const cats = ['Legal'];

  void _onFieldChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _calc();
        setState(() {});
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final b = widget.billing;
    _type = b?.type ?? 'INVOICE';
    _status = b?.status ?? 'Pending';
    _category = cats.contains(b?.category) ? b!.category! : cats.first;
    _clientName = TextEditingController(text: b?.clientName ?? widget.initialClientName);
    _clientAddress = TextEditingController(text: b?.data?['client_address'] ?? '');
    _date = TextEditingController(text: b?.date ?? DateFormat('dd/MM/yyyy').format(DateTime.now()));
    _invoiceNo = TextEditingController(text: b?.invoiceNo);
    _outstanding = TextEditingController(text: b?.outstandingAmount.toString());
    _advanceReceived = TextEditingController(text: b?.data?['advance_received']?.toString() ?? '');
    _promisedDate = TextEditingController(text: b?.data?['promised_payment_date']?.toString() ?? '');
    _authorities = b?.authorities ?? '';
    _items = b?.items ?? [{'description': '', 'amount': ''}];

    _selectedCaseId = b?.data?['case_id'] ?? widget.linkedCaseId;
    if (_selectedCaseId != null) {
      _fetchCaseDetails(_selectedCaseId!);
    }

    // Initialize quotation terms
    _quotationTerms = List<String>.from(b?.data?['quotation_terms'] ?? _getDefaultTerms(_category));
    _termControllers = _quotationTerms.map((t) => TextEditingController(text: t)).toList();

    // Initialize item controllers
    _itemDescControllers = _items.map((item) => TextEditingController(text: item['description'].toString())).toList();
    _itemAmountControllers = _items.map((item) => TextEditingController(text: item['amount'].toString())).toList();

    // Add listeners for real-time preview updates
    _clientName.addListener(_onFieldChanged);
    _clientAddress.addListener(_onFieldChanged);
    _date.addListener(_onFieldChanged);
    _invoiceNo.addListener(_onFieldChanged);
    _outstanding.addListener(_onFieldChanged);
    _advanceReceived.addListener(_onFieldChanged);

    for (var controller in _itemDescControllers) {
      controller.addListener(_onFieldChanged);
    }
    for (var controller in _itemAmountControllers) {
      controller.addListener(_onFieldChanged);
    }
    for (var controller in _termControllers) {
      controller.addListener(_onFieldChanged);
    }

    if (b != null) {
      _totalAmount = b.amount ?? '0/-';
      _amountInWords = b.amountInWords;
      _grandTotal = b.grandTotal.toString();
      _balanceDue = b.data?['balance_due']?.toString() ?? '';
    } else {
      _generateInvoiceNo();
    }
    _fetchStaffs();
    _fetchPastItems();
  }

  Future<void> _fetchCaseDetails(String caseId) async {
    try {
      final request = GraphQLRequest<String>(
        document: '''
          query GetCases(\$id: ID!) {
            getCases(id: \$id) {
              case_title
              client_name
            }
          }
        ''',
        variables: {'id': caseId},
      );
      final response = await Amplify.API.query(request: request).response;
      final data = response.data;
      if (data != null && mounted) {
        final Map<String, dynamic> parsed = jsonDecode(data);
        final caseData = parsed['getCases'];
        if (caseData != null) {
          setState(() {
            _caseTitleController.text = caseData['case_title'] ?? '';
            if (_clientName.text.isEmpty && caseData['client_name'] != null) {
              _clientName.text = caseData['client_name'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch case details: $e');
    }
  }

  Future<void> _fetchPastItems() async {
    try {
      final request = GraphQLRequest<String>(
        document: '''
          query ListBillings {
            listBillings(limit: 100) {
              items {
                data
              }
            }
          }
        ''',
      );
      final response = await Amplify.API.query(request: request).response;
      final Set<String> seen = {};
      final List<Map<String, String>> items = [];
      final responseData = response.data;
      if (responseData != null) {
        final Map<String, dynamic> parsed = jsonDecode(responseData);
        final billingsList = parsed['listBillings']?['items'] as List?;
        if (billingsList != null) {
          for (var row in billingsList) {
            final dataStr = row['data'];
            if (dataStr != null) {
              try {
                final mapData = jsonDecode(dataStr);
                final invoiceItems = mapData['items'];
                if (invoiceItems is List) {
                   for (var item in invoiceItems) {
                     final desc = item['description']?.toString() ?? '';
                     final amt = item['amount']?.toString() ?? '';
                     if (desc.isNotEmpty && !seen.contains(desc)) {
                       seen.add(desc);
                       items.add({'description': desc, 'amount': amt});
                     }
                   }
                }
              } catch (_) {}
            }
          }
        }
      }
      if (mounted) setState(() => _pastItems = items);
    } catch (e) {
      debugPrint('Failed to fetch past items: $e');
    }
  }

  Future<void> _fetchStaffs() async {
    try {
      final users = await UserService.getAllUsers();
      final List<String> fetchedStaffs = users.map((u) => DisplayNameHelper.overrideName(u['name'].toString())).toList();
      
      final prefs = await SharedPreferences.getInstance();
      final currentUserName = DisplayNameHelper.overrideName(prefs.getString('user_name') ?? '');

      setState(() {
        _staffs = fetchedStaffs.map((name) {
          final n = name.trim();
          final matchKey = _BillingScreenState.staffMapping.keys.firstWhere(
            (k) => n.toLowerCase().contains(k.toLowerCase()) || k.toLowerCase().contains(n.toLowerCase()),
            orElse: () => ''
          );
          if (matchKey.isNotEmpty) {
            return '${_BillingScreenState.staffMapping[matchKey]} - $n';
          }
          return n;
        }).toList();

        if (widget.billing == null && _authorities.isEmpty) {
          final matchKey = _BillingScreenState.staffMapping.keys.firstWhere(
            (k) => currentUserName.toLowerCase().contains(k.toLowerCase()) || k.toLowerCase().contains(currentUserName.toLowerCase()),
            orElse: () => ''
          );
          final formattedCurrent = matchKey.isNotEmpty 
              ? '${_BillingScreenState.staffMapping[matchKey]} - $currentUserName' 
              : currentUserName;
          if (_staffs.contains(formattedCurrent)) {
            _authorities = formattedCurrent;
          } else if (_staffs.isNotEmpty) {
            _authorities = _staffs.first;
          }
        } else if (widget.billing != null) {
          final invPrefix = widget.billing!.invoiceNo?.split(RegExp(r'[ \-]')).first ?? '';
          final existingAuth = _authorities.isEmpty ? invPrefix : _authorities;
          
          if (existingAuth.isNotEmpty) {
            final match = _BillingScreenState.staffMapping.keys.firstWhere(
              (k) => k.toLowerCase() == existingAuth.toLowerCase() || 
                     existingAuth.toLowerCase().contains(k.toLowerCase()) ||
                     _BillingScreenState.staffMapping[k] == existingAuth.toUpperCase(), 
              orElse: () => ''
            );
            if (match.isNotEmpty) {
              _authorities = '${_BillingScreenState.staffMapping[match]} - $match';
            } else {
              _authorities = existingAuth;
            }
          }

          if (_authorities.isEmpty) {
            _authorities = widget.billing!.authorities ?? (_staffs.isNotEmpty ? _staffs.first : '');
          }
        }
      });
    } catch (e) {
      debugPrint('StaffFetchErr: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _clientName.dispose();
    _clientAddress.dispose();
    _date.dispose();
    _invoiceNo.dispose();
    _outstanding.dispose();
    _advanceReceived.dispose();
    _promisedDate.dispose();
    for (var c in _itemDescControllers) {
      c.dispose();
    }
    for (var c in _itemAmountControllers) {
      c.dispose();
    }
    for (var c in _termControllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _getDefaultTerms(String category) {
    if (_type == 'INVOICE') {
      return [
        'For any clarifications or queries regarding the bill, or to report an error or omission, please contact us at cochinunitedlegallp@gmail.com',
      ];
    }
    return [
      'The validity of this quotation is only for one month from the date of issue.',
      'This quotation is not comprehensive. Inspection charges, additional consultation, statutory fees, and any additional work required as per instructions from authorities are excluded from this quotation and will be charged separately, if required.',
      'Any increase in government fees or additional expenses during the application process must be borne by you.',
      'We are not liable for delays caused by changes in government regulations, system failures, network issues, or unforeseen circumstances beyond our control.',
      'If additional documents or steps are required, your cooperation and support will be necessary, and any extra expenses incurred must be reimbursed by you.',
      'Please regularly follow up on the application process and promptly share any required OTPs.',
      'In case of any unethical practices or misbehavior by our staff, please contact our Client Relationship Manager immediately.',
    ];
  }

  Future<void> _generateInvoiceNo([String? customPrefix]) async {
    if (widget.billing != null) return;
    
    final prefix = customPrefix ?? (_type == 'QUOTATION' ? 'CC' : 'AA');
    try {
      final next = await _billingService.getNextInvoiceNo(prefix);
      if (mounted) {
        if (next != null) {
          setState(() => _invoiceNo.text = next);
        } else {
          setState(() => _invoiceNo.text = "$prefix-001");
        }
      }
    } catch (e) { 
      debugPrint('GenErr: $e');
      if (mounted) setState(() => _invoiceNo.text = "$prefix-001");
    }
  }

  Future<bool> _isInvoiceNoDuplicate(String no) async {
    try {
      final billings = await BillingService.getBillings();
      return billings.any((b) => b['invoice_no'] == no && b['id'] != widget.billing?.id);
    } catch (e) {
      return false;
    }
  }

  void _calc() {
    double t = 0;
    for (int i = 0; i < _items.length; i++) {
      _items[i]['description'] = _itemDescControllers[i].text;
      _items[i]['amount'] = _itemAmountControllers[i].text;
      t += NumberToWords.parseCurrency(_itemAmountControllers[i].text);
    }
    // Sync terms
    for (int i = 0; i < _quotationTerms.length; i++) {
      _quotationTerms[i] = _termControllers[i].text;
    }
    double o = NumberToWords.parseCurrency(_outstanding.text);
    double adv = NumberToWords.parseCurrency(_advanceReceived.text);
    double g = t + o;
    setState(() {
      _totalAmount = t > 0 ? NumberToWords.formatIndianCurrency(t) : '0/-';
      _amountInWords = t > 0 ? NumberToWords.convert(t.round()) : 'Zero';
      _grandTotal = g > t ? NumberToWords.formatIndianCurrency(g) : '';
      _balanceDue = adv > 0 ? NumberToWords.formatIndianCurrency(g - adv) : '';
    });
  }

  Future<void> _syncClientBalance(String clientName) async {
    await _billingService.syncClientBalance(clientName);
  }

  Future<void> _save() async {
    _calc(); // Ensure state is synced from controllers before saving

    if (_invoiceNo.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice number is required'), backgroundColor: Colors.orange));
      return;
    }

    final isDuplicate = await _isInvoiceNoDuplicate(_invoiceNo.text);
    if (isDuplicate) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Duplicate Invoice Number'),
          content: Text('An invoice with number "${_invoiceNo.text}" already exists. Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save Anyway')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    try {
      final d = {
        'items': _items, 
        'outstanding_amount': _outstanding.text, 
        'amount_in_words': _amountInWords, 
        'grand_total': _grandTotal, 
        'balance_due': _balanceDue,
        'advance_received': _advanceReceived.text,
        'promised_payment_date': _promisedDate.text,
        if (_selectedCaseId != null) 'case_id': _selectedCaseId,
        'client_address': _clientAddress.text, 
        'quotation_terms': _quotationTerms,
        'payment_received': (NumberToWords.parseCurrency(_advanceReceived.text) > 0 && NumberToWords.parseCurrency(_advanceReceived.text) >= NumberToWords.parseCurrency(_grandTotal.isEmpty ? _totalAmount : _grandTotal)) || (widget.billing?.data?['payment_received'] == true), 
        'payment_date': widget.billing?.data?['payment_date']
      };
      final prefix = _authorities.split(' ').first;
      final Map<String, dynamic> v = {'inv': _invoiceNo.text, 'client': _clientName.text, 'date': _date.text, 'amt': _totalAmount, 'type': _type, 'cat': _category, 'auth': _authorities, 'status': _status, 'data': d};
      dynamic savedId;
      if (widget.billing == null || widget.billing!.id == null) { 
        savedId = await BillingService.addBilling({
          'invoice_no': _invoiceNo.text,
          'client_name': _clientName.text,
          'date': _date.text,
          'amount': _totalAmount,
          'type': _type,
          'category': _category,
          'authorities': _authorities,
          'status': _status,
          'data': d
        });
        await _log.logAction(action: 'INVOICE_CREATED', targetType: 'Invoice', targetId: _invoiceNo.text, details: 'Created for ${_clientName.text}');
      }
      else { 
        savedId = widget.billing!.id!;
        await BillingService.updateBilling(savedId, {
          'invoice_no': _invoiceNo.text,
          'client_name': _clientName.text,
          'date': _date.text,
          'amount': _totalAmount,
          'type': _type,
          'category': _category,
          'authorities': _authorities,
          'status': _status,
          'data': d
        });
        await _log.logAction(action: 'INVOICE_UPDATED', targetType: 'Invoice', targetId: _invoiceNo.text, details: 'Updated for ${_clientName.text}');
      }
      // Update client's balance in the clients table
      if (_clientName.text.isNotEmpty) {
        await _syncClientBalance(_clientName.text);
      }

      widget.onSaved?.call(savedId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invoice saved as ${_invoiceNo.text}'), backgroundColor: AppTheme.successGreen));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _print() async {
    _calc();
    await InvoicePdfService.printInvoice(
      type: _type, 
      category: _category, 
      clientName: _clientName.text, 
      clientAddress: _clientAddress.text, 
      date: _date.text, 
      invoiceNo: _invoiceNo.text, 
      authorities: _authorities, 
      items: _items, 
      totalAmount: _totalAmount, 
      amountInWords: _amountInWords, 
      outstandingAmount: _outstanding.text, 
      advanceReceived: _advanceReceived.text,
      grandTotal: _grandTotal,
      balanceDue: _balanceDue,
      quotationTerms: _quotationTerms,
    );
  }

  Future<Uint8List> _generatePreviewPdf() async {
    return await InvoicePdfService.generateInvoicePdf(
      type: _type, 
      category: _category, 
      clientName: _clientName.text, 
      clientAddress: _clientAddress.text, 
      date: _date.text, 
      invoiceNo: _invoiceNo.text, 
      authorities: _authorities, 
      items: _items, 
      totalAmount: _totalAmount, 
      amountInWords: _amountInWords, 
      outstandingAmount: _outstanding.text, 
      advanceReceived: _advanceReceived.text,
      grandTotal: _grandTotal,
      balanceDue: _balanceDue,
      quotationTerms: _quotationTerms,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 950;

        final formPanel = Container(
          width: isMobile ? double.infinity : 460,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor, 
            boxShadow: isMobile ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 40, offset: const Offset(10, 0))]
          ),
          child: Column(children: [
            // Header
            Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), decoration: BoxDecoration(color: AppTheme.surfaceColor, border: Border(bottom: BorderSide(color: AppTheme.backgroundColor))),
              child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(6)),
                          child: const Text('CUC', style: TextStyle(color: AppTheme.surfaceColor, fontWeight: FontWeight.w900, fontSize: 14))),
                        const SizedBox(width: 12),
                        const Text('Billing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 13))),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded, size: 14), label: const Text('Save', style: TextStyle(fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 14), label: const Text('Print', style: TextStyle(fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.textPrimary, foregroundColor: AppTheme.backgroundColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
                      ]),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(6)),
                          child: const Text('CUC', style: TextStyle(color: AppTheme.surfaceColor, fontWeight: FontWeight.w900, fontSize: 14))),
                        const SizedBox(width: 12),
                        const Text('Billing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
                      ]),
                      Row(children: [
                        TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 13))),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded, size: 14), label: const Text('Save', style: TextStyle(fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 14), label: const Text('Print', style: TextStyle(fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.textPrimary, foregroundColor: AppTheme.backgroundColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
                      ]),
                    ],
                  ),
            ),
            // Form Content
            Expanded(child: SingleChildScrollView(padding: EdgeInsets.all(isMobile ? 16 : 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [Icon(Icons.description_rounded, color: AppTheme.surfaceColor, size: 18), SizedBox(width: 10), Text('Invoice Details', style: TextStyle(color: AppTheme.surfaceColor, fontWeight: FontWeight.bold, fontSize: 15)), Spacer(), Text('Items', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11))]),
              ),
              const SizedBox(height: 24),
              if (isMobile) ...[
                _buildSelector('DOCUMENT TYPE', _type, ['INVOICE', 'QUOTATION'], (v) {
                  setState(() {
                    final oldType = _type;
                    _type = v;
                    if (oldType == 'INVOICE' && _type == 'QUOTATION') {
                      _quotationTerms = _getDefaultTerms(_category);
                      _termControllers = _quotationTerms.map((t) => TextEditingController(text: t)).toList();
                    } else if (oldType == 'QUOTATION' && _type == 'INVOICE') {
                      _quotationTerms = _getDefaultTerms(_category);
                      _termControllers = _quotationTerms.map((t) => TextEditingController(text: t)).toList();
                    }
                    _generateInvoiceNo();
                  });
                }),
                if (_type == 'QUOTATION') ...[
                   const SizedBox(height: 16),
                   _buildSelector('QUOTATION STATUS', _status, ['Pending', 'Interested', 'Not Interested'], (v) => setState(() => _status = v)),
                ]
              ] else Row(
                children: [
                  Expanded(child: _buildSelector('DOCUMENT TYPE', _type, ['INVOICE', 'QUOTATION'], (v) {
                    setState(() {
                      final oldType = _type;
                      _type = v;
                      if (oldType == 'INVOICE' && _type == 'QUOTATION') {
                        _quotationTerms = _getDefaultTerms(_category);
                        _termControllers = _quotationTerms.map((t) => TextEditingController(text: t)).toList();
                      } else if (oldType == 'QUOTATION' && _type == 'INVOICE') {
                        _quotationTerms = _getDefaultTerms(_category);
                        _termControllers = _quotationTerms.map((t) => TextEditingController(text: t)).toList();
                      }
                      _generateInvoiceNo();
                    });
                  })),
                  if (_type == 'QUOTATION') ...[
                    const SizedBox(width: 16),
                    Expanded(child: _buildSelector('STATUS', _status, ['Pending', 'Interested', 'Not Interested'], (v) => setState(() => _status = v))),
                  ]
                ],
              ),
              const SizedBox(height: 20),
              _sectionTitle('Client Details'),
              _buildClientAutocomplete(isMobile),
              const SizedBox(height: 12),
              _buildCaseAutocomplete(isMobile),
              const SizedBox(height: 12),
              _buildField('Address', _clientAddress, 'Complete billing address...', lines: 3),
              const SizedBox(height: 20),
              if (isMobile) ...[
                _buildField('Date', _date, 'dd/mm/yyyy'),
                const SizedBox(height: 16),
                _buildField(_type == 'QUOTATION' ? 'Quotation No' : 'Invoice No', _invoiceNo, _type == 'QUOTATION' ? 'e.g. CC-001' : 'e.g. AA-001', suffix: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryColor),
                  onPressed: () => _generateInvoiceNo(),
                  tooltip: 'Regenerate sequence',
                )),
                const SizedBox(height: 16),
                _buildField('Promise Date', _promisedDate, 'dd/mm/yyyy'),
              ] else Row(
                children: [
                  Expanded(child: _buildField('Date', _date, 'dd/mm/yyyy')),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField(_type == 'QUOTATION' ? 'Quotation No' : 'Invoice No', _invoiceNo, _type == 'QUOTATION' ? 'e.g. CC-001' : 'e.g. AA-001', suffix: IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryColor),
                    onPressed: () => _generateInvoiceNo(),
                    tooltip: 'Regenerate sequence',
                  ))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField('Promise Date', _promisedDate, 'dd/mm/yyyy')),
                ],
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('STAFF / PREPARED BY', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.primaryColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _authorities.isEmpty ? 'Logged-in Staff' : _authorities,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Logged In',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _sectionTitle('${_type == 'QUOTATION' ? 'Quotation' : 'Invoice'} Terms'),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _quotationTerms.add('');
                      _termControllers.add(TextEditingController()..addListener(_onFieldChanged));
                    });
                  }, 
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18), 
                  label: const Text('Add Point'), 
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor)
                ),
              ]),
              const SizedBox(height: 12),
              ..._termControllers.asMap().entries.map((e) => _buildTermRow(e.key)),

              const SizedBox(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _sectionTitle('Line Items'),
                TextButton.icon(onPressed: () {
                  setState(() {
                    _items.add({'description': '', 'amount': ''});
                    _itemDescControllers.add(TextEditingController()..addListener(_onFieldChanged));
                    _itemAmountControllers.add(TextEditingController()..addListener(_onFieldChanged));
                  });
                }, icon: const Icon(Icons.add_circle_outline_rounded, size: 18), label: const Text('Add Item'), style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor)),
              ]),
              const SizedBox(height: 12),
              ..._items.asMap().entries.map((e) => _buildItemRow(e.key, e.value)),
              if (_items.isEmpty) _emptyItems(),
              const SizedBox(height: 32),
              _sectionTitle('Summary & Outstanding'),
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.secondaryColor, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _summaryRow('Subtotal', _totalAmount, isBold: true),
                  const Divider(height: 24),
                  _buildField('Previous Outstanding', _outstanding, '0/-', onChanged: (_) => _calc(), isCurrency: true),
                  if (_grandTotal.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _summaryRow('Grand Total', _grandTotal, isPrimary: true),
                  ],
                  const SizedBox(height: 16),
                  _buildField('Advance / Received', _advanceReceived, '0/-', onChanged: (_) => _calc(), isCurrency: true),
                  if (_balanceDue.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _summaryRow('Balance Due', _balanceDue, isBold: true, color: Colors.orange.shade700),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Authorized Signature', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    Image.asset('assets/sign.png', height: 40, fit: BoxFit.contain, opacity: const AlwaysStoppedAnimation(0.7)),
                  ]),
                ]),
              ),
              const SizedBox(height: 100),
            ]))),
            // Footer Actions
            Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppTheme.surfaceColor, border: Border(top: BorderSide(color: AppTheme.backgroundColor))),
              child: isMobile
                ? Column(
                    children: [
                      SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _save, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Save Progress'))),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Finalize & Print'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.textPrimary, foregroundColor: AppTheme.backgroundColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _save, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Save Progress')))),
                      const SizedBox(width: 16),
                      Expanded(child: SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Finalize & Print'), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.textPrimary, foregroundColor: AppTheme.backgroundColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))),
                    ],
                  ),
            ),
            // Version Footer
            Container(padding: const EdgeInsets.symmetric(vertical: 12), width: double.infinity, alignment: Alignment.center, decoration: BoxDecoration(color: AppTheme.surfaceColor, border: Border(top: BorderSide(color: AppTheme.backgroundColor))), child: Text('Billing Software v1.0', style: TextStyle(color: Colors.grey.shade400, fontSize: 10))),
          ]),
        );

        final previewPanel = Container(
          color: const Color(0xFFF1F5F9),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.remove_red_eye_rounded, size: 18, color: Color(0xFFC5A059)),
                    const SizedBox(width: 8),
                    const Text(
                      'Live Document Preview',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _type,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: Color(0xFF0F172A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PdfPreview(
                      key: ValueKey('$_type-${_clientName.text}-${_invoiceNo.text}-$_totalAmount-$_date-${_items.length}-${_advanceReceived.text}-${_outstanding.text}'),
                      build: (format) => _generatePreviewPdf(),
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      allowPrinting: true,
                      allowSharing: true,
                      initialPageFormat: PdfPageFormat.a4,
                      pdfFileName: '${_invoiceNo.text.isNotEmpty ? _invoiceNo.text : 'Invoice'}.pdf',
                      loadingWidget: const Center(
                        child: CircularProgressIndicator(color: Color(0xFFC5A059)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: AppTheme.surfaceColor,
              elevation: 0,
              bottom: TabBar(
                tabs: [
                  Tab(text: 'DETAILS', icon: Icon(Icons.edit_note_rounded, size: 20)),
                  Tab(text: 'PREVIEW', icon: Icon(Icons.remove_red_eye_rounded, size: 20)),
                ],
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppTheme.primaryColor,
                indicatorWeight: 3,
                labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
              ),
            ),
            body: TabBarView(children: [formPanel, previewPanel]),
          );
        }

        return ResponsiveScaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Row(children: [formPanel, Expanded(child: previewPanel)]),
        );
      },
    );
  }

  Widget _sectionTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: 1.2)));

  void _formatCurrencyField(TextEditingController controller) {
    double val = NumberToWords.parseCurrency(controller.text);
    if (val > 0) {
      setState(() => controller.text = NumberToWords.formatIndianCurrency(val));
      _calc();
    }
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {int lines = 1, ValueChanged<String>? onChanged, bool isCurrency = false, Widget? suffix}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
    const SizedBox(height: 6),
    Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus && isCurrency) _formatCurrencyField(controller);
      },
      child: TextField(
        controller: controller, maxLines: lines, onChanged: onChanged,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint, 
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal), 
          filled: true, 
          fillColor: const Color(0xFFF8FAFC), 
          suffixIcon: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))), 
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))), 
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5))
        ),
      ),
    ),
  ]);

  Widget _buildCaseAutocomplete(bool isMobile) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Linked Case (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      const SizedBox(height: 6),
      Autocomplete<Map<String, dynamic>>(
        displayStringForOption: (option) => option['case_title'] ?? 'Untitled',
        optionsBuilder: (textEditingValue) async {
          if (textEditingValue.text.isEmpty) return const Iterable.empty();
          final request = GraphQLRequest<String>(
            document: '''
              query SearchCases(\$title: String!) {
                listCases(filter: {case_title: {contains: \$title}}, limit: 10) {
                  items {
                    id
                    case_title
                    case_number
                    client_name
                  }
                }
              }
            ''',
            variables: {'title': textEditingValue.text},
          );
          final response = await Amplify.API.query(request: request).response;
          final data = jsonDecode(response.data!);
          final items = data['listCases']['items'] as List<dynamic>;
          return items.map((i) => i as Map<String, dynamic>).toList();
        },
        onSelected: (option) {
          setState(() {
            _selectedCaseId = option['id'].toString();
            _caseTitleController.text = option['case_title'] ?? '';
            if (option['client_name'] != null && option['client_name'].toString().isNotEmpty) {
              _clientName.text = option['client_name'];
            }
          });
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          if (controller.text.isEmpty && _caseTitleController.text.isNotEmpty) {
            controller.text = _caseTitleController.text;
          }
          controller.addListener(() {
            if (controller.text != _caseTitleController.text) {
               _selectedCaseId = null;
               _caseTitleController.text = controller.text;
            }
          });
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search for a case...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5)),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: isMobile ? MediaQuery.of(context).size.width - 32 : 412,
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      title: Text(option['case_title'] ?? 'Untitled', style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                      subtitle: Text(option['client_name'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ]);
  }

  Widget _buildClientAutocomplete(bool isMobile) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Client Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      const SizedBox(height: 6),
      Autocomplete<Map<String, dynamic>>(
        displayStringForOption: (option) => option['name'],
        optionsBuilder: (textEditingValue) async {
          if (textEditingValue.text.isEmpty) return const Iterable.empty();
          return await _clientService.searchClients(textEditingValue.text);
        },
        onSelected: (option) {
          setState(() {
            _clientName.text = option['name'];
            _clientAddress.text = option['address'];
            _outstanding.text = option['balance_due'] ?? '';
            _calc();
          });
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          // Sync internal controller with autocomplete controller
          if (controller.text.isEmpty && _clientName.text.isNotEmpty) {
            controller.text = _clientName.text;
          }
          controller.addListener(() {
            _clientName.text = controller.text;
            setState(() {});
          });
          
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Start typing client name...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5)),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: isMobile ? MediaQuery.of(context).size.width - 32 : 412, // Match field width approximately
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      title: Text(option['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                      subtitle: Text(option['address'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ]);
  }

  Widget _buildSelector(String label, String value, List<String> items, ValueChanged<String> onChanged) {
    // Create a safe copy of items and ensure the current value is included to prevent DropdownButton crashes
    final List<String> safeItems = List.from(items);
    if (value.isNotEmpty && !safeItems.contains(value)) {
      safeItems.add(value);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      const SizedBox(height: 6),
      Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCBD5E1))),
        child: DropdownButton<String>(
          value: value.isEmpty ? (safeItems.isNotEmpty ? safeItems.first : null) : value, 
          isExpanded: true, 
          dropdownColor: Colors.white,
          underline: const SizedBox(), 
          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          items: safeItems.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), 
          onChanged: (v) => onChanged(v!),
        ),
      ),
    ]);
  }

  void _moveItem(int idx, int dir) {
    if (idx + dir < 0 || idx + dir >= _items.length) return;
    setState(() {
      final item = _items.removeAt(idx);
      final desc = _itemDescControllers.removeAt(idx);
      final amt = _itemAmountControllers.removeAt(idx);
      _items.insert(idx + dir, item);
      _itemDescControllers.insert(idx + dir, desc);
      _itemAmountControllers.insert(idx + dir, amt);
    });
  }

  Widget _buildItemRow(int idx, Map<String, dynamic> item) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFCBD5E1)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Builder(
              builder: (context) {
                final isHeading = _itemAmountControllers[idx].text.trim().isEmpty;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isHeading ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isHeading ? 'Item #${idx + 1} (Heading)' : 'Item #${idx + 1}',
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.w700, 
                      color: isHeading ? const Color(0xFF92400E) : AppTheme.textPrimary,
                    ),
                  ),
                );
              },
            ),
            const Spacer(),
            if (idx > 0)
              IconButton(
                onPressed: () => _moveItem(idx, -1),
                icon: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.blueGrey),
                tooltip: 'Move Up',
              ),
            if (idx < _items.length - 1)
              IconButton(
                onPressed: () => _moveItem(idx, 1),
                icon: const Icon(Icons.arrow_downward_rounded, size: 18, color: Colors.blueGrey),
                tooltip: 'Move Down',
              ),
            IconButton(
              onPressed: () => setState(() { 
                _items.removeAt(idx); 
                _itemDescControllers[idx].dispose();
                _itemAmountControllers[idx].dispose();
                _itemDescControllers.removeAt(idx);
                _itemAmountControllers.removeAt(idx);
                _calc(); 
              }),
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
              tooltip: 'Delete Item',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Autocomplete<Map<String, String>>(
            displayStringForOption: (option) => option['description'] ?? '',
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return const Iterable<Map<String, String>>.empty();
              return _pastItems.where((option) => option['description']!.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            onSelected: (option) {
              setState(() {
                _itemDescControllers[idx].text = option['description'] ?? '';
                _items[idx]['description'] = option['description'];
                if ((option['amount'] ?? '').isNotEmpty) {
                  _itemAmountControllers[idx].text = option['amount'] ?? '';
                  _items[idx]['amount'] = option['amount'];
                }
                _calc();
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (controller.text.isEmpty && _itemDescControllers[idx].text.isNotEmpty) {
                controller.text = _itemDescControllers[idx].text;
              }
              controller.addListener(() {
                if (_itemDescControllers[idx].text != controller.text) {
                   _itemDescControllers[idx].text = controller.text;
                   _items[idx]['description'] = controller.text;
                }
              });
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Item description...',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal),
                  border: InputBorder.none,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 340,
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option['description'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          trailing: Text('₹${option['amount'] ?? '0'}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.currency_rupee_rounded, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      double a = NumberToWords.parseCurrency(item['amount'].toString());
                      if (a > 0) setState(() => item['amount'] = NumberToWords.formatIndianCurrency(a));
                      _calc();
                    }
                  },
                  child: TextField(
                    controller: _itemAmountControllers[idx],
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Amount',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) { 
                      _items[idx]['amount'] = v; 
                      _calc(); 
                    },
                    onSubmitted: (v) { 
                      double a = NumberToWords.parseCurrency(v); 
                      if (a > 0) {
                        setState(() => _itemAmountControllers[idx].text = NumberToWords.formatIndianCurrency(a)); 
                      } else {
                        setState(() => _itemAmountControllers[idx].text = '');
                      }
                      _calc(); 
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ).animate().slideY(begin: 0.1, end: 0, duration: 300.ms);

  Widget _emptyItems() => Container(width: double.infinity, padding: const EdgeInsets.all(32), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid)), child: const Column(children: [Icon(Icons.add_shopping_cart_rounded, color: AppTheme.textSecondary, size: 32), SizedBox(height: 12), Text('No items added yet', style: TextStyle(color: AppTheme.textSecondary))]));

  Widget _summaryRow(String label, String value, {bool isBold = false, bool isPrimary = false, Color? color}) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: TextStyle(fontSize: 14, color: color ?? (isPrimary ? AppTheme.primaryColor : AppTheme.textSecondary), fontWeight: isBold ? FontWeight.w800 : FontWeight.w500)),
    Text(value, style: TextStyle(fontSize: isPrimary ? 20 : 16, fontWeight: FontWeight.w900, color: color ?? (isPrimary ? AppTheme.primaryColor : AppTheme.textPrimary))),
  ]);

  Widget _buildTermRow(int idx) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCBD5E1))),
    child: Row(
      children: [
        const Text('•', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textSecondary)),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _termControllers[idx],
            onChanged: (v) => _quotationTerms[idx] = v,
            maxLines: null,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'Enter term...', hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.normal), border: InputBorder.none, isDense: true),
          ),
        ),
        IconButton(
          onPressed: () => setState(() {
            _quotationTerms.removeAt(idx);
            _termControllers[idx].dispose();
            _termControllers.removeAt(idx);
          }),
          icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    ),
  );
}
