import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/client_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/client.dart';
import '../services/excel_service.dart';
import '../services/logging_service.dart';
import '../services/case_service.dart';
import '../services/billing_service.dart';
import '../services/expense_service.dart';
import '../models/expense_model.dart';
import 'client_files_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/role_service.dart';
import '../widgets/excel_import_dialog.dart';

class ClientManagementScreen extends StatefulWidget {
  const ClientManagementScreen({super.key});

  @override
  State<ClientManagementScreen> createState() => _ClientManagementScreenState();
}

class _ClientManagementScreenState extends State<ClientManagementScreen> {
  final _excel = ExcelService();
  List<Client> _clients = [];
  bool _isLoading = true;
  String _searchTerm = '';
  String _currentUserRole = 'Staff';

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    _fetchClients();
  }

  Future<void> _fetchUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currentUserRole = prefs.getString('user_role') ?? 'Staff';
      });
    }
  }

  Future<void> _fetchClients() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final result = await ClientService().getAllClients();
      if (!mounted) return;

      setState(() {
        _clients = result.map((m) => Client.fromMap(m)).toList();
      });
    } catch (e) {
      _showError('Failed to fetch clients: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteClient(Client client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: Text(
          'Confirm Delete',
          style: GoogleFonts.cormorantGaramond(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        content: const Text(
          'Are you sure you want to delete this client? All associated files and cases will be unlinked.',
          style: TextStyle(color: Color(0xFF475569), fontFamily: 'Montserrat'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ClientService.deleteClient(client.id, name: client.name, email: client.email);
        setState(() {
          _clients.removeWhere((c) =>
            (client.id != null && c.id == client.id) ||
            (client.name != null && c.name == client.name)
          );
        });
        _showSuccess('Client deleted');
        
        // Delay fetching to allow backend consistency
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _fetchClients();
        });
      } catch (e) {
        _showError('Error deleting client: $e');
      }
    }
  }

  Future<void> _exportToExcel() async {
    try {
      final clientMaps = _clients.map((c) => c.toMap()).toList();
      final path = await _excel.exportClients(clientMaps);
      if (path != null) {
        _showSuccess('Exported successfully to $path');
      }
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  Future<void> _openExcelImportDialog() async {
    final updated = await ExcelImportDialog.show(context);
    if (updated == true) {
      _fetchClients();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showClientFilesDialog(Client client) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => ClientFilesDialog(client: client),
    );
  }

  void _showClientForm([Client? client]) {
    final nameController = TextEditingController(text: client?.name);
    final emailController = TextEditingController(text: client?.email);
    final phoneController = TextEditingController(text: client?.phone);
    final clientTypeController = TextEditingController(text: client?.clientType ?? 'Individual');
    final workController = TextEditingController(text: client?.typeOfWork);
    final caseController = TextEditingController(text: client?.caseNumber);
    final courtController = TextEditingController(text: client?.courtName);
    final opposingPartyController = TextEditingController(text: client?.opposingParty);
    final opposingCounselController = TextEditingController(text: client?.opposingCounsel);
    final hearingController = TextEditingController(text: client?.nextHearingDate);
    final statusController = TextEditingController(text: client?.caseStatus ?? 'Active');
    final addressController = TextEditingController(text: client?.address);
    final careOfController = TextEditingController(text: client?.careOf);
    final yearController = TextEditingController(text: client?.year ?? DateTime.now().year.toString());
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) =>
            Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(24),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 750),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 36,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 450;
                        Widget responsiveRow(Widget w1, Widget w2) {
                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [w1, const SizedBox(height: 20), w2],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: w1),
                              const SizedBox(width: 20),
                              Expanded(child: w2),
                            ],
                          );
                        }

                        return SingleChildScrollView(
                          padding: EdgeInsets.all(isNarrow ? 24 : 36),
                          child: Form(
                            key: formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFD4AF37)),
                                  ),
                                  child: Icon(
                                    client == null
                                        ? Icons.person_add_alt_1_rounded
                                        : Icons.edit_note_rounded,
                                    color: const Color(0xFFD4AF37),
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        client == null
                                            ? 'ADD NEW CLIENT'
                                            : 'EDIT CLIENT PROFILE',
                                        style: GoogleFonts.cormorantGaramond(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF0F172A),
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const Text(
                                        "Enter client contact profiles & court matter details",
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          color: Color(0xFF64748B),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF64748B),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFFF8FAFC),
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            _buildFormField(
                              nameController,
                              'Full Name',
                              Icons.person_outline,
                              true,
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              careOfController,
                              'Care Of (C/O)',
                              Icons.person_pin_outlined,
                              false,
                            ),
                            const SizedBox(height: 16),
                            responsiveRow(
                              _buildFormField(
                                emailController,
                                'Email Address',
                                Icons.email_outlined,
                                false,
                              ),
                              _buildFormField(
                                phoneController,
                                'Phone Number',
                                Icons.phone_outlined,
                                true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            responsiveRow(
                              _buildDropdownField(
                                clientTypeController,
                                'Client Type',
                                Icons.business_outlined,
                                ['Individual', 'Company', 'Firm', 'Trust', 'Other'],
                              ),
                              _buildDropdownField(
                                workController,
                                'Case Area',
                                Icons.work_outline,
                                ['Civil', 'Criminal', 'Corporate', 'Family', 'Property', 'Tax', 'Constitutional', 'Other'],
                              ),
                            ),
                            const SizedBox(height: 16),
                            responsiveRow(
                              _buildFormField(
                                caseController,
                                'Case/Filing Number',
                                Icons.gavel_outlined,
                                false,
                              ),
                              _buildFormField(
                                yearController,
                                'Filing Year',
                                Icons.calendar_month_outlined,
                                false,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              courtController,
                              'Court Name',
                              Icons.account_balance_outlined,
                              false,
                            ),
                            const SizedBox(height: 16),
                            responsiveRow(
                              _buildFormField(
                                opposingPartyController,
                                'Opposing Party',
                                Icons.person_outline,
                                false,
                              ),
                              _buildFormField(
                                opposingCounselController,
                                'Opposing Counsel',
                                Icons.groups_outlined,
                                false,
                              ),
                            ),
                            const SizedBox(height: 16),
                            responsiveRow(
                              _buildFormField(
                                hearingController,
                                'Next Hearing Date',
                                Icons.calendar_today_outlined,
                                false,
                              ),
                              _buildDropdownField(
                                statusController,
                                'Case Status',
                                Icons.info_outline,
                                ['Active', 'Pending', 'Disposed', 'Stayed', 'Appealed', 'Closed'],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              addressController,
                              'Full Address',
                              Icons.location_on_outlined,
                              false,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                  final newClient = Client(
                                    id: client?.id,
                                    name: nameController.text,
                                    email: emailController.text,
                                    phone: phoneController.text,
                                    address: addressController.text,
                                    clientType: clientTypeController.text,
                                    typeOfWork: workController.text,
                                    caseNumber: caseController.text,
                                    year: yearController.text.trim(),
                                    courtName: courtController.text,
                                    opposingParty: opposingPartyController.text,
                                    opposingCounsel: opposingCounselController.text,
                                    nextHearingDate: hearingController.text,
                                    caseStatus: statusController.text,
                                    balanceDue: client?.balanceDue,
                                    careOf: careOfController.text,
                                  );
                                  try {
                                    final data = {
                                      'name': newClient.name,
                                      'email': newClient.email,
                                      'phone': newClient.phone,
                                      'address': newClient.address,
                                      'client_type': newClient.clientType,
                                      'type_of_work': newClient.typeOfWork,
                                      'case_number': newClient.caseNumber,
                                      'year': newClient.year,
                                      'court_name': newClient.courtName,
                                      'opposing_party': newClient.opposingParty,
                                      'opposing_counsel': newClient.opposingCounsel,
                                      'next_hearing_date': newClient.nextHearingDate,
                                      'case_status': newClient.caseStatus,
                                      'care_of': newClient.careOf,
                                    };

                                  if (client == null || newClient.id == null || newClient.id!.isEmpty) {
                                    await ClientService().addClientFull(data);
                                  } else {
                                    await ClientService.updateClient(
                                      newClient.id!,
                                      data,
                                    );
                                  }

                                  if (context.mounted) Navigator.pop(context);
                                  _fetchClients();

                                  await LoggingService().logAction(
                                    action: client == null
                                        ? 'CLIENT_CREATED'
                                        : 'CLIENT_UPDATED',
                                    targetType: 'Client',
                                    targetId: nameController.text,
                                    details: 'Client: ${nameController.text}',
                                  );

                                  _showSuccess('Client saved successfully');
                                } catch (e) {
                                  _showError('Save failed: $e');
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: const Color(0xFFD4AF37),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(color: Color(0xFFD4AF37)),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Save Client Profile',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                  ),
                )
                .animate()
                .fadeIn(duration: 250.ms)
                .scaleXY(begin: 0.98, end: 1.0, curve: Curves.easeOutQuart),
      ),
    );
  }

  Widget _buildFormField(
    TextEditingController controller,
    String label,
    IconData icon,
    bool required, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Montserrat', fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF0F172A), size: 20),
      ),
      validator: required
          ? (v) => v == null || v.isEmpty ? "Required" : null
          : null,
    );
  }

  Widget _buildDropdownField(
    TextEditingController controller,
    String label,
    IconData icon,
    List<String> options,
  ) {
    String currentValue = controller.text;
    if (currentValue.isEmpty) {
      currentValue = options.first;
      controller.text = currentValue;
    } else if (!options.contains(currentValue)) {
      options = [...options, currentValue];
    }
    
    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF0F172A), size: 20),
      ),
      dropdownColor: Colors.white,
      style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Montserrat', fontSize: 13.5),
      items: options.map((String val) {
        return DropdownMenuItem<String>(
          value: val,
          child: Text(val),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          controller.text = newValue;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 900;
        final filtered = _clients
            .where(
              (c) =>
                  (c.name?.toLowerCase().contains(_searchTerm.toLowerCase()) ??
                      false) ||
                  (c.phone?.contains(_searchTerm) ?? false) ||
                  (c.fileNo?.toLowerCase().contains(
                        _searchTerm.toLowerCase(),
                      ) ??
                      false),
            )
            .toList();

        final totalActiveCases = _clients.where((c) => (c.caseStatus ?? '').toLowerCase() == 'active').length;
        final clientsWithDues = _clients.where((c) => c.balanceDue != null && c.balanceDue != '0/-' && c.balanceDue != '0').length;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Padding(
            padding: EdgeInsets.all(isWide ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Minimal Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (Navigator.canPop(context))
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Color(0xFF0F172A),
                                size: 20,
                              ),
                              onPressed: () => Navigator.pop(context),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Client Management',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const Text(
                              'Manage client profiles, court matters & document vaults',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isWide)
                      Row(
                        children: [
                          SizedBox(
                            width: 280,
                            child: TextField(
                              onChanged: (val) =>
                                  setState(() => _searchTerm = val),
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 13,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search clients, files, phone...',
                                hintStyle: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 13,
                                  color: Color(0xFF94A3B8),
                                ),
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: Color(0xFF64748B),
                                  size: 18,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _headerAction(
                            Icons.refresh_rounded,
                            'Refresh',
                            const Color(0xFF0F172A),
                            _fetchClients,
                          ),
                          const SizedBox(width: 8),
                          _headerAction(
                            Icons.upload_file_rounded,
                            'Import Excel',
                            const Color(0xFFC5A059),
                            _openExcelImportDialog,
                          ),
                          const SizedBox(width: 8),
                          _headerAction(
                            Icons.download_rounded,
                            'Export to Excel',
                            const Color(0xFF0F172A),
                            _exportToExcel,
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () => _showClientForm(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Client', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                if (!isWide) ...[
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (val) => setState(() => _searchTerm = val),
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 13,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search clients, files...',
                      hintStyle: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF64748B),
                        size: 18,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showClientForm(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Client', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _headerAction(
                        Icons.refresh_rounded,
                        'Refresh',
                        const Color(0xFF0F172A),
                        _fetchClients,
                      ),
                      const SizedBox(width: 8),
                      _headerAction(
                        Icons.upload_file_rounded,
                        'Import',
                        const Color(0xFFC5A059),
                        _openExcelImportDialog,
                      ),
                      const SizedBox(width: 8),
                      _headerAction(
                        Icons.download_rounded,
                        'Export',
                        const Color(0xFF0F172A),
                        _exportToExcel,
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Compact Metric Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'Total Roster',
                        '${_clients.length}',
                        Icons.group_outlined,
                        const Color(0xFF0F172A),
                        const Color(0xFFF1F5F9),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Active Matters',
                        '$totalActiveCases',
                        Icons.gavel_outlined,
                        const Color(0xFF059669),
                        const Color(0xFFECFDF5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Dues Pending',
                        '$clientsWithDues',
                        Icons.account_balance_wallet_outlined,
                        const Color(0xFFDC2626),
                        const Color(0xFFFEF2F2),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                      : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFF1F5F9),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Icon(
                                  Icons.people_outline_rounded,
                                  size: 40,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchTerm.isNotEmpty
                                    ? 'No matches found.'
                                    : 'No clients registered yet.',
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _searchTerm.isNotEmpty
                                    ? 'Try adjusting your search query.'
                                    : 'Click Add Client to register your first record.',
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final client = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _buildClientCard(client, isWide),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, Color bgPill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgPill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerAction(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 18),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        padding: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(
            color: Color(0xFFE2E8F0),
          ),
        ),
      ),
    );
  }

  Widget _buildClientCard(Client c, bool isWide) {
    final hasDue = c.balanceDue != null && c.balanceDue != "0/-" && c.balanceDue != "0";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isWide ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Client Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Sleek Circle Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0F172A),
                  ),
                  child: Center(
                    child: Text(
                      (c.name?.isNotEmpty ?? false)
                          ? c.name![0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name ?? 'Unnamed Client',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (c.caseStatus?.isNotEmpty == true) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 12,
                                    color: Color(0xFF059669),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    c.caseStatus!,
                                    style: const TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 11,
                                      color: Color(0xFF059669),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: hasDue ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: hasDue ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 12,
                                  color: hasDue ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Due: ${c.balanceDue ?? '0/-'}",
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: hasDue ? const Color(0xFFDC2626) : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (c.typeOfWork?.isNotEmpty == true) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                c.typeOfWork!,
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  color: Color(0xFF475569),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('• ', style: TextStyle(color: Color(0xFF94A3B8))),
                          ],
                          Text(
                            'File No: ${c.fileNo ?? "N/A"}',
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Unified Details Panel
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: isWide
                  ? Row(
                      children: [
                        Expanded(child: _buildInfoItem(Icons.phone_outlined, c.phone?.isNotEmpty == true ? c.phone! : 'No Phone')),
                        Expanded(child: _buildInfoItem(Icons.email_outlined, c.email?.isNotEmpty == true ? c.email! : 'No Email')),
                        Expanded(child: _buildInfoItem(Icons.gavel_outlined, 'Case: ${c.caseNumber?.isNotEmpty == true ? c.caseNumber! : 'N/A'}${c.year?.isNotEmpty == true ? ' (${c.year})' : ''}')),
                        Expanded(child: _buildInfoItem(Icons.calendar_today_outlined, 'File Date: ${c.fileDate?.isNotEmpty == true ? c.fileDate! : 'N/A'}')),
                        Expanded(child: _buildInfoItem(Icons.account_balance_outlined, 'Court: ${c.courtName?.isNotEmpty == true ? c.courtName! : 'N/A'}')),
                      ],
                    )
                  : Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildInfoItem(Icons.phone_outlined, c.phone?.isNotEmpty == true ? c.phone! : 'No Phone'),
                        _buildInfoItem(Icons.email_outlined, c.email?.isNotEmpty == true ? c.email! : 'No Email'),
                        _buildInfoItem(Icons.gavel_outlined, 'Case: ${c.caseNumber?.isNotEmpty == true ? c.caseNumber! : 'N/A'}${c.year?.isNotEmpty == true ? ' (${c.year})' : ''}'),
                        if (c.year?.isNotEmpty == true)
                          _buildInfoItem(Icons.calendar_month_outlined, 'Year: ${c.year}'),
                        _buildInfoItem(Icons.calendar_today_outlined, 'File Date: ${c.fileDate?.isNotEmpty == true ? c.fileDate! : 'N/A'}'),
                        _buildInfoItem(Icons.account_balance_outlined, 'Court: ${c.courtName?.isNotEmpty == true ? c.courtName! : 'N/A'}'),
                        _buildInfoItem(Icons.location_on_outlined, c.address?.isNotEmpty == true ? c.address! : 'No Address'),
                      ],
                    ),
            ),

            const SizedBox(height: 14),

            // Action Buttons Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showClientDashboard(c),
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 14),
                  label: const Text('Ledger & Cases'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showClientFilesDialog(c),
                  icon: const Icon(Icons.folder_special_rounded, size: 15, color: Color(0xFFD4AF37)),
                  label: const Text('Files Vault', style: TextStyle(fontFamily: 'Montserrat', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showClientForm(c),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (RoleService.canDeleteCases(_currentUserRole)) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _deleteClient(c),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      backgroundColor: const Color(0xFFFEF2F2),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF334155),
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showClientDashboard(Client client) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Container(
            width: 850,
            height: 620,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${client.name} — Ledger & Cases',
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF64748B),
                      ),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF8FAFC),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          labelColor: Color(0xFF0F172A),
                          unselectedLabelColor: Color(0xFF64748B),
                          indicatorColor: Color(0xFFD4AF37),
                          indicatorWeight: 3,
                          labelStyle: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 13.5),
                          unselectedLabelStyle: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w500, fontSize: 13.5),
                          tabs: [
                            Tab(text: 'Associated Cases'),
                            Tab(text: 'Ledger & Payments'),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildClientCasesTab(client),
                              _buildClientLedgerTab(client),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClientCasesTab(Client client) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CaseService.getCases(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0F172A)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'No cases registered.',
              style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat'),
            ),
          );
        }

        final clientCases = snapshot.data!.where((c) {
          // Attempt to match by exact email first if available in case_description
          if (c['case_description'] != null) {
            try {
              final map = jsonDecode(c['case_description']);
              if (map['client_email'] != null && map['client_email'].toString().isNotEmpty) {
                if (map['client_email'].toString().trim().toLowerCase() == (client.email ?? '').trim().toLowerCase()) {
                  return true;
                }
              }
            } catch (_) {}
          }
          
          final cName = (c['client_name'] ?? c['client'] ?? '').toString().trim().toLowerCase();
          final targetName = (client.name ?? '').trim().toLowerCase();
          return cName.isNotEmpty && targetName.isNotEmpty && cName == targetName;
        }).toList();
        if (clientCases.isEmpty) {
          return const Center(
            child: Text(
              'No cases associated with this client.',
              style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat'),
            ),
          );
        }

        return ListView.builder(
          itemCount: clientCases.length,
          itemBuilder: (context, index) {
            final c = clientCases[index];
            final title = (c['case_title'] ?? c['title'] ?? c['case_name'] ?? c['name'] ?? '').toString().trim();
            final displayTitle = title.isNotEmpty ? title : 'Untitled Case';
            
            final status = (c['status'] ?? c['case_status'] ?? 'Active').toString().trim();
            final type = (c['case_type'] ?? c['matter_type'] ?? c['type'] ?? c['category'] ?? 'N/A').toString().trim();
            
            final rawCaseNo = (c['case_number'] ?? c['court_case_number'] ?? c['workfile_no'] ?? c['case_id'] ?? c['id'] ?? '').toString().trim();
            final caseNoDisplay = rawCaseNo.length > 12 && rawCaseNo.contains('-')
                ? '#${rawCaseNo.substring(0, 8)}'
                : (rawCaseNo.isNotEmpty ? '#$rawCaseNo' : '');

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                title: Text(
                  displayTitle,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Montserrat',
                  ),
                ),
                subtitle: Text(
                  'Status: $status | Type: $type',
                  style: const TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontSize: 12.5),
                ),
                trailing: caseNoDisplay.isNotEmpty
                    ? Text(
                        caseNoDisplay,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClientLedgerTab(Client client) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        BillingService.getBillings(),
        ExpenseService.getExpenses(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0F172A)),
          );
        }
        
        final bills = (snapshot.data?[0] as List<Map<String, dynamic>>?) ?? [];
        final expenses = (snapshot.data?[1] as List<ExpenseModel>?) ?? [];

        final clientBills = bills.where((b) => b['client_name'] == client.name).toList();
        final clientExpenses = expenses.where((e) => e.linkedClientName == client.name).toList();

        if (clientBills.isEmpty && clientExpenses.isEmpty) {
          return const Center(
            child: Text(
              'No payments or expenses recorded.',
              style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat'),
            ),
          );
        }

        final combinedList = <Map<String, dynamic>>[];
        for (var b in clientBills) {
          combinedList.add({
             'id': b['id'],
             'title': b['invoice_no'] ?? 'Invoice',
             'type_label': 'Bill',
             'amount': double.tryParse(b['amount']?.toString() ?? '0') ?? 0.0,
             'date': b['date']?.toString().split('T').first ?? '',
             'is_positive': b['status'] == 'Received' || (b['data'] != null && b['data']['payment_received'] == true),
          });
        }
        for (var e in clientExpenses) {
          combinedList.add({
             'id': e.id,
             'title': e.title,
             'type_label': e.type == TransactionType.income ? 'Income' : 'Expense',
             'amount': e.amount,
             'date': e.date.toIso8601String().split('T').first,
             'is_positive': e.type == TransactionType.income,
          });
        }
        
        combinedList.sort((a, b) => b['date'].compareTo(a['date']));

        double netBalance = 0;
        for (var item in combinedList) {
          final isPositive = item['is_positive'] as bool;
          final amt = item['amount'] as double;
          if (isPositive) {
            netBalance += amt;
          } else {
            netBalance -= amt;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFF0F172A),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Net Ledger Balance:',
                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontFamily: 'Montserrat', fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${netBalance >= 0 ? '+' : '-'}₹${netBalance.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      color: netBalance >= 0 ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: combinedList.length,
                itemBuilder: (context, index) {
                  final item = combinedList[index];
                  final isPositive = item['is_positive'] as bool;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPositive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        child: Icon(
                          isPositive ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 16,
                          color: isPositive ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                        ),
                      ),
                      title: Text(
                        item['title'] ?? 'Transaction',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      subtitle: Text(
                        'Type: ${item['type_label']} | Date: ${item['date']}',
                        style: const TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontSize: 12),
                      ),
                      trailing: Text(
                        '${isPositive ? '+' : '-'}₹${item['amount'].toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isPositive ? const Color(0xFF15803D) : const Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
