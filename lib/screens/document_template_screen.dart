import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/document_template.dart';
import '../models/client.dart';
import '../models/case_model.dart';
import '../services/document_automation_service.dart';
import '../services/client_service.dart';
import '../services/case_service.dart';
import '../services/microsoft_word_service.dart';
import 'word_webview_screen.dart';
import '../widgets/responsive.dart';

class DocumentTemplateScreen extends StatefulWidget {
  const DocumentTemplateScreen({super.key});

  @override
  State<DocumentTemplateScreen> createState() => _DocumentTemplateScreenState();
}

class _DocumentTemplateScreenState extends State<DocumentTemplateScreen> {
  List<DocumentTemplate> _templates = [];
  List<Client> _clients = [];
  List<CaseFile> _cases = [];
  
  bool _isLoading = true;
  String _searchQuery = '';
  
  // Selection state for generation
  Client? _selectedClient;
  CaseFile? _selectedCase;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final templates = await DocumentAutomationService.getTemplates();
      final clientsData = await ClientService().getAllClients();
      final clients = clientsData.map((e) => Client.fromMap(e)).toList();
      final casesData = await CaseService.getCases();
      final cases = casesData.map((e) => CaseFile.fromJson(e)).toList();
      
      if (mounted) {
        setState(() {
          _templates = templates;
          _clients = clients;
          _cases = cases;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateDocument(DocumentTemplate template) async {
    if (_selectedClient == null && _selectedCase == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Client or Case to auto-fill the template.')),
      );
    }
    
    setState(() => _isLoading = true);

    final generatedContent = DocumentAutomationService.generateDocument(
      template,
      client: _selectedClient,
      caseFile: _selectedCase,
    );

    final urlString = await MicrosoftWordService.createNewDocument(
      template.title,
      content: generatedContent,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (urlString != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WordWebviewScreen(
              url: urlString,
              title: template.title,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate Word Document.')),
        );
      }
    }
  }

  Future<void> _showCreateTemplateDialog() async {
    final titleController = TextEditingController();
    final categoryController = TextEditingController();
    final contentController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Create Smart Template', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Template Title', labelStyle: TextStyle(color: AppTheme.textSecondary)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Category (e.g., Litigation, Notice)', labelStyle: TextStyle(color: AppTheme.textSecondary)),
              ),
              const SizedBox(height: 12),
              const Text('Variables available: [ClientName], [CaseTitle], [Date]', style: TextStyle(color: AppTheme.accentColor, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: contentController,
                style: const TextStyle(color: AppTheme.textPrimary),
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Template Content',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
            child: const Text('Save Template', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == true) {
      if (titleController.text.isNotEmpty && contentController.text.isNotEmpty) {
        final newTemplate = DocumentTemplate(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: titleController.text,
          category: categoryController.text.isNotEmpty ? categoryController.text : 'Custom',
          content: contentController.text,
        );
        await DocumentAutomationService.addTemplate(newTemplate);
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTemplates = _templates.where((t) {
      return t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             t.category.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return ResponsiveScaffold(
      backgroundColor: AppTheme.primaryColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        title: const Text('Smart Templates', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
        iconTheme: const IconThemeData(color: AppTheme.accentColor),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTemplateDialog,
        backgroundColor: AppTheme.accentColor,
        foregroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('CREATE TEMPLATE', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Montserrat')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : Column(
              children: [
                _buildConfigurationPanel(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'),
                    decoration: InputDecoration(
                      hintText: 'Search templates...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.secondaryColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filteredTemplates.isEmpty
                      ? const Center(child: Text('No templates found.', style: TextStyle(color: AppTheme.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredTemplates.length,
                          itemBuilder: (context, index) {
                            return _buildTemplateCard(filteredTemplates[index])
                                .animate()
                                .fadeIn(delay: Duration(milliseconds: 50 * index))
                                .slideX();
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildConfigurationPanel() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1: Select Context for Auto-Fill',
            style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, color: AppTheme.accentColor, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Client>(
                  value: _selectedClient,
                  dropdownColor: AppTheme.primaryColor,
                  style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'),
                  decoration: InputDecoration(
                    labelText: 'Select Client',
                    labelStyle: const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.secondaryColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: _clients.map((c) => DropdownMenuItem(value: c, child: Text(c.name ?? '', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (val) => setState(() => _selectedClient = val),
                  isExpanded: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<CaseFile>(
                  value: _selectedCase,
                  dropdownColor: AppTheme.primaryColor,
                  style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'),
                  decoration: InputDecoration(
                    labelText: 'Select Case',
                    labelStyle: const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.secondaryColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: _cases.map((c) => DropdownMenuItem(value: c, child: Text(c.caseTitle, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (val) => setState(() => _selectedCase = val),
                  isExpanded: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Variables like [ClientName] or [CaseTitle] will be automatically replaced when you generate a document.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(DocumentTemplate template) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.description, color: AppTheme.accentColor),
        ),
        title: Text(
          template.title,
          style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  template.category,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _generateDocument(template),
          child: const Text('GENERATE', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Montserrat')),
        ),
      ),
    );
  }
}
