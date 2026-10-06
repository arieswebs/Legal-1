import 'dart:math' as math;
import '../utils/display_name_helper.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive.dart';
import '../models/expense_model.dart';
import '../services/case_service.dart';
import '../services/expense_service.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ExpenseScreen extends StatefulWidget {
  final String? initialCaseId;
  const ExpenseScreen({super.key, this.initialCaseId});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  List<ExpenseModel> _transactions = [];
  Map<String, String> _caseIdToName = {};
  bool _isLoading = true;
  String _currentUserName = '';

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    _loadUserAndData();
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndData() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserName = DisplayNameHelper.overrideName(prefs.getString('user_name') ?? prefs.getString('user_email') ?? 'User');
    await _fetchTransactions();
  }

  static String _formatCaseTitle(Map<String, dynamic> c) {
    final caseNo = (c['case_number'] ?? c['court_case_number'] ?? c['workfile_no'] ?? c['file_no'] ?? c['case_id'] ?? '').toString().trim();
    String title = (c['case_title'] ?? c['title'] ?? c['case_name'] ?? c['name'] ?? '').toString().trim();
    
    if (title.isEmpty && c['client_name'] != null && c['client_name'].toString().trim().isNotEmpty) {
      title = "${c['client_name']}'s Case";
    }
    
    if (title.isEmpty) {
      title = caseNo.isNotEmpty ? 'Case #$caseNo' : 'Untitled Case';
    }
    
    return caseNo.isNotEmpty && !title.contains(caseNo) ? '$title (#$caseNo)' : title;
  }

  String _getCaseDisplayName(ExpenseModel transaction) {
    final caseId = transaction.linkedCaseId;
    if (caseId == null || caseId.trim().isEmpty) return '';

    // 1. Direct map lookup
    if (_caseIdToName.containsKey(caseId) && _caseIdToName[caseId]!.isNotEmpty) {
      return _caseIdToName[caseId]!;
    }

    // 2. Check if linkedClientName is stored on transaction
    if (transaction.linkedClientName != null && transaction.linkedClientName!.trim().isNotEmpty) {
      final client = transaction.linkedClientName!.trim();
      final shortId = caseId.length > 8 ? caseId.substring(0, 8) : caseId;
      return "$client's Case (#$shortId)";
    }

    // 3. Fallback for raw UUID string
    if (caseId.contains('-') || caseId.length >= 20) {
      final shortId = caseId.length > 8 ? caseId.substring(0, 8) : caseId;
      return 'Case #$shortId';
    }

    return 'Case #$caseId';
  }

  Future<void> _fetchTransactions() async {
    setState(() => _isLoading = true);
    var data = await ExpenseService.getExpenses();
    if (widget.initialCaseId != null && widget.initialCaseId!.trim().isNotEmpty) {
      data = data.where((e) => e.linkedCaseId == widget.initialCaseId).toList();
    }
    final cases = await CaseService.getCases();
    
    final Map<String, String> caseMap = {};
    for (var c in cases) {
      final displayName = _formatCaseTitle(c);
      final keysToMap = [
        c['id']?.toString(),
        c['case_id']?.toString(),
        c['caseId']?.toString(),
        c['case_number']?.toString(),
        c['court_case_number']?.toString(),
        c['workfile_no']?.toString(),
        c['file_no']?.toString(),
      ];
      for (final k in keysToMap) {
        if (k != null && k.isNotEmpty) {
          caseMap[k] = displayName;
        }
      }
    }

    if (mounted) {
      setState(() {
        _transactions = data;
        _caseIdToName = caseMap;
        _isLoading = false;
      });
    }
  }

  void _showAddTransactionDialog() {
    showDialog(
      context: context,
      builder: (context) => AddTransactionDialog(
        currentUserName: _currentUserName,
        onAdded: _fetchTransactions,
        initialCaseId: widget.initialCaseId,
        lockCaseSelection: widget.initialCaseId != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double totalIncome = _transactions
        .where((t) => t.type == TransactionType.income && t.status != ExpenseStatus.rejected)
        .fold(0, (sum, item) => sum + item.amount);
    final double totalExpense = _transactions
        .where((t) => t.type == TransactionType.expense && t.status != ExpenseStatus.rejected)
        .fold(0, (sum, item) => sum + item.amount);
    final double netBalance = totalIncome - totalExpense;

    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return ResponsiveScaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTransactionDialog,
        backgroundColor: AppTheme.primaryColor,
        elevation: 8,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Log Transaction', style: TextStyle(fontFamily: 'Montserrat', color: Colors.white, fontWeight: FontWeight.bold)),
      ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width > 900 ? 32.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textPrimary, size: 20),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Financial Register',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.end,
                    children: [
                      _buildSummaryBox('Income', currencyFormatter.format(totalIncome), AppTheme.successGreen),
                      _buildSummaryBox('Expenses', currencyFormatter.format(totalExpense), AppTheme.errorRed),
                      _buildSummaryBox('Net Balance', currencyFormatter.format(netBalance), AppTheme.primaryColor),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // Transactions List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                    : _transactions.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppTheme.textSecondary.withAlpha(30), width: 1),
                                  ),
                                  child: Icon(Icons.receipt_long_outlined, size: 64, color: AppTheme.textSecondary.withAlpha(100)),
                                ).animate().fadeIn(duration: 600.ms),
                                const SizedBox(height: 24),
                                const Text(
                                  'No Transactions',
                                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary, letterSpacing: 0.5),
                                ).animate().fadeIn(delay: 200.ms),
                                const SizedBox(height: 8),
                                const Text(
                                  'Your financial register is currently empty.',
                                  style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary, fontSize: 14),
                                ).animate().fadeIn(delay: 300.ms),
                              ],
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final incomeTxs = _transactions.where((t) => t.type == TransactionType.income).toList();
                              final expenseTxs = _transactions.where((t) => t.type == TransactionType.expense).toList();
                              
                              if (constraints.maxWidth < 800) {
                                // Narrow screen: 1 column
                                return ListView.builder(
                                  itemCount: _transactions.length,
                                  itemBuilder: (context, index) {
                                    return _buildTransactionCard(_transactions[index], currencyFormatter);
                                  },
                                );
                              }
                              
                              // Wide screen: 2 columns
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 16),
                                          child: Row(
                                            children: [
                                              Icon(Icons.arrow_downward_rounded, color: AppTheme.successGreen, size: 20),
                                              const SizedBox(width: 8),
                                              const Text('INCOME', style: TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.successGreen, letterSpacing: 1.0)),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: incomeTxs.isEmpty
                                              ? const Center(child: Text('No income recorded', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary)))
                                              : ListView.builder(
                                                  itemCount: incomeTxs.length,
                                                  itemBuilder: (context, index) => _buildTransactionCard(incomeTxs[index], currencyFormatter),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 16),
                                          child: Row(
                                            children: [
                                              Icon(Icons.arrow_upward_rounded, color: AppTheme.errorRed, size: 20),
                                              const SizedBox(width: 8),
                                              const Text('EXPENSES', style: TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.errorRed, letterSpacing: 1.0)),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: expenseTxs.isEmpty
                                              ? const Center(child: Text('No expenses recorded', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary)))
                                              : ListView.builder(
                                                  itemCount: expenseTxs.length,
                                                  itemBuilder: (context, index) => _buildTransactionCard(expenseTxs[index], currencyFormatter),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBox(String label, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSecondary.withAlpha(20), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(label == 'Income' ? Icons.arrow_downward : label == 'Expenses' ? Icons.arrow_upward : Icons.drag_handle, color: color, size: 16),
              const SizedBox(width: 8),
              Text(label.toUpperCase(), style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount,
            style: TextStyle(fontFamily: 'Montserrat', fontSize: 24, fontWeight: FontWeight.w500, color: AppTheme.textPrimary, letterSpacing: 0.5),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildTransactionCard(ExpenseModel transaction, NumberFormat formatter) {
    final isIncome = transaction.type == TransactionType.income;
    final typeColor = isIncome ? AppTheme.successGreen : AppTheme.errorRed;
    final icon = isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSecondary.withAlpha(20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: typeColor.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: typeColor, size: 20),
          ),
          const SizedBox(width: 16),
          
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        transaction.title,
                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary, letterSpacing: 0.2),
                      ),
                    ),
                    Text(
                      (isIncome ? '+' : '-') + formatter.format(transaction.amount),
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        transaction.category,
                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('dd MMM yyyy').format(transaction.date),
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '• By ${transaction.submittedBy}',
                      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                if (transaction.linkedCaseId != null && transaction.linkedCaseId!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.folder_shared, size: 14, color: AppTheme.accentColor),
                      const SizedBox(width: 4),
                      Text(
                        'Linked Case: ${_getCaseDisplayName(transaction)}',
                        style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
                if (transaction.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    transaction.description,
                    style: const TextStyle(fontFamily: 'Montserrat', fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddTransactionDialog extends StatefulWidget {
  final String currentUserName;
  final VoidCallback onAdded;
  final String? initialCaseId;
  final bool lockCaseSelection;

  const AddTransactionDialog({
    super.key,
    required this.currentUserName,
    required this.onAdded,
    this.initialCaseId,
    this.lockCaseSelection = false,
  });

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  TransactionType _selectedType = TransactionType.expense;
  String _selectedCategory = 'Travel';
  
  final List<String> _expenseCategories = [
    'Travel',
    'Filing Fees',
    'Stationery',
    'Client Meeting',
    'Software/IT',
    'Miscellaneous'
  ];
  
  final List<String> _incomeCategories = [
    'Client Payment',
    'Consultation Fee',
    'Retainer',
    'Refund/Reimbursement',
    'Miscellaneous'
  ];

  bool _isSubmitting = false;
  List<Map<String, dynamic>> _availableCases = [];
  String? _selectedCaseId;

  @override
  void initState() {
    super.initState();
    _selectedCategory = _expenseCategories.first;
    _selectedCaseId = widget.initialCaseId;
    _loadCases();
  }

  Future<void> _loadCases() async {
    final cases = await CaseService.getCases();
    if (mounted) {
      setState(() {
        _availableCases = cases;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);
    
    String? clientName;
    if (_selectedCaseId != null) {
      final caseObj = _availableCases.firstWhere((c) => c['id'] == _selectedCaseId, orElse: () => <String, dynamic>{});
      clientName = caseObj['client_name'] as String?;
    }

    final newTransaction = ExpenseModel(
      id: 'TRX-\${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim(),
      amount: double.tryParse(_amountController.text.trim()) ?? 0.0,
      category: _selectedCategory,
      date: DateTime.now(),
      description: _descriptionController.text.trim(),
      status: ExpenseStatus.approved,
      submittedBy: widget.currentUserName,
      type: _selectedType,
      linkedCaseId: _selectedCaseId,
      linkedClientName: clientName,
    );

    await ExpenseService.addExpense(newTransaction);
    
    if (mounted) {
      widget.onAdded();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction logged successfully.'), backgroundColor: AppTheme.successGreen),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _selectedType == TransactionType.income ? _incomeCategories : _expenseCategories;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.1)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Log Transaction',
                style: TextStyle(fontFamily: 'Montserrat', fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 24),
              
              // Transaction Type Toggle
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedType = TransactionType.income;
                          if (!_incomeCategories.contains(_selectedCategory)) {
                            _selectedCategory = _incomeCategories.first;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedType == TransactionType.income ? AppTheme.successGreen : AppTheme.secondaryColor,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                          border: Border.all(color: _selectedType == TransactionType.income ? AppTheme.successGreen : AppTheme.textSecondary.withValues(alpha: 0.2)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Income / Money In',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.bold,
                            color: _selectedType == TransactionType.income ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedType = TransactionType.expense;
                          if (!_expenseCategories.contains(_selectedCategory)) {
                            _selectedCategory = _expenseCategories.first;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedType == TransactionType.expense ? AppTheme.errorRed : AppTheme.secondaryColor,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                          border: Border.all(color: _selectedType == TransactionType.expense ? AppTheme.errorRed : AppTheme.textSecondary.withValues(alpha: 0.2)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Expense / Money Out',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.bold,
                            color: _selectedType == TransactionType.expense ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              

              
              // Case Selection
              if (!widget.lockCaseSelection) ...[
                const SizedBox(height: 16),
                const Text('Link to Case (Optional)', style: TextStyle(fontFamily: 'Montserrat', fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCaseId,
                    dropdownColor: AppTheme.secondaryColor,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      prefixIcon: Icon(Icons.folder_outlined, color: AppTheme.textSecondary),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None', style: TextStyle(color: AppTheme.textPrimary))),
                      ..._availableCases.map((c) {
                            final displayTitle = _ExpenseScreenState._formatCaseTitle(c);
                            return DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text(displayTitle, style: const TextStyle(color: AppTheme.textPrimary)),
                            );
                          }),
                    ],
                    onChanged: (val) => setState(() => _selectedCaseId = val),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              
              _buildTextField(_titleController, 'Title', Icons.title),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: _buildTextField(_amountController, 'Amount (₹)', Icons.currency_rupee, keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          dropdownColor: AppTheme.surfaceColor,
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryColor),
                          style: const TextStyle(fontFamily: 'Montserrat', fontSize: 14, color: AppTheme.textPrimary),
                          items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCategory = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(_descriptionController, 'Description (Optional)', Icons.description, maxLines: 3),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Submit Transaction', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Montserrat', fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
        prefixIcon: maxLines == 1 ? Icon(icon, color: AppTheme.textSecondary, size: 20) : null,
        filled: true,
        fillColor: AppTheme.secondaryColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (val) => (val == null || val.isEmpty) && !hint.contains('Optional') ? 'Required' : null,
    );
  }
}

// Elegant Animated Mesh Gradient Background Painter
class MeshGradientPainter extends CustomPainter {
  final double animationValue;

  MeshGradientPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rect = Offset.zero & size;

    // Base background color
    paint.color = AppTheme.backgroundColor;
    canvas.drawRect(rect, paint);

    // Create moving glowing orbs using radial gradients (increased movement range)
    _drawOrb(canvas, size, 
      offset: Offset(size.width * (0.3 + 0.3 * math.sin(animationValue * math.pi * 2)), size.height * (0.3 + 0.3 * math.cos(animationValue * math.pi * 2))), 
      color: AppTheme.accentColor.withValues(alpha: 0.12),
      radius: size.width * 0.8,
    );

    _drawOrb(canvas, size, 
      offset: Offset(size.width * (0.7 + 0.3 * math.cos(animationValue * math.pi * 2)), size.height * (0.7 + 0.3 * math.sin(animationValue * math.pi * 2))), 
      color: AppTheme.accentColor.withValues(alpha: 0.10),
      radius: size.width * 0.9,
    );
    
    _drawOrb(canvas, size, 
      offset: Offset(size.width * (0.5 + 0.4 * math.sin(animationValue * math.pi)), size.height * (0.5 + 0.4 * math.cos(animationValue * math.pi))), 
      color: AppTheme.highlightColor.withValues(alpha: 0.08),
      radius: size.width * 0.7,
    );
  }

  void _drawOrb(Canvas canvas, Size size, {required Offset offset, required Color color, required double radius}) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        offset,
        radius,
        [color, color.withValues(alpha: 0)],
        [0.0, 1.0],
      );
    canvas.drawCircle(offset, radius, paint);
  }

  @override
  bool shouldRepaint(covariant MeshGradientPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
