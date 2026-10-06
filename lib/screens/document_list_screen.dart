import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../theme/app_theme.dart';
import '../services/microsoft_word_service.dart';
import '../services/ai_service.dart';
import 'word_webview_screen.dart';
import '../widgets/responsive.dart';
import '../models/deal.dart' as old;
import '../services/deal_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DocumentListScreen extends StatefulWidget {
  final String userEmail;
  const DocumentListScreen({super.key, required this.userEmail});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  List<dynamic> _documents = [];
  String _searchQuery = '';
  bool _isLoading = false;
  String? _currentUser;

  Future<List<dynamic>> _loadLocalDocumentsCache() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList('local_docs_cache') ?? [];
    return encoded.map((str) {
      final map = jsonDecode(str);
      return map;
    }).toList();
  }

  Future<void> _saveLocalDocumentsCache(List<dynamic> docs) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> encoded = docs.map((d) => jsonEncode({
      'id': d['id'],
      'name': d['name'],
      'webUrl': d['webUrl'],
      'lastModifiedDateTime': d['lastModifiedDateTime'],
    })).toList();
    await prefs.setStringList('local_docs_cache', encoded);
  }

  @override
  void initState() {
    super.initState();
    _checkSignInStatus();
  }

  Future<void> _checkSignInStatus() async {
    setState(() => _isLoading = true);
    final account = await MicrosoftWordService.signIn();
    if (account != null) {
      _currentUser = account;
      await _loadDocuments();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    final account = await MicrosoftWordService.signIn();
    if (account != null) {
      _currentUser = account;
      await _loadDocuments();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await MicrosoftWordService.signOut();
    setState(() {
      _currentUser = null;
      _documents = [];
    });
  }

  Future<void> _loadDocuments() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    List<dynamic> driveDocs = [];
    try {
      driveDocs = await MicrosoftWordService.getDriveFiles();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e.toString().contains('Session expired')) {
            _currentUser = null;
          }
        });
      }
    }

    if (!mounted) return;

    // Load documents stored in the database (Deals)
    try {
      final deals = await DealService().getAllDeals();
      for (var deal in deals) {
        if (deal.driveLink != null && deal.driveLink!.isNotEmpty) {
          try {
            final parsed = jsonDecode(deal.driveLink!);
            for (var p in parsed) {
              final urlStr = p['url']?.toString() ?? '';
              final regex = RegExp(r'/d/([^/]+)/');
              final match = regex.firstMatch(urlStr);
              final docId = match?.group(1);
              if (docId != null) {
                driveDocs.add(drive.File(
                  id: docId,
                  name: p['name']?.toString() ?? 'Linked Document',
                  webViewLink: urlStr,
                  modifiedTime: DateTime.now().toUtc(),
                ));
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Load unlinked documents from local cache
    try {
      final cachedDocs = await _loadLocalDocumentsCache();
      driveDocs.addAll(cachedDocs);
    } catch (_) {}

    if (mounted) {
      setState(() {
        // Deduplicate
        final Map<String, drive.File> uniqueDocs = {};
        for (var d in driveDocs) {
          if (d.id != null) {
            // Keep the one with the newest modifiedTime if there are duplicates
            if (uniqueDocs.containsKey(d.id!)) {
              final existing = uniqueDocs[d.id!];
              final existingTime = existing?.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();
              final newTime = d.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();
              if (newTime.isAfter(existingTime)) {
                uniqueDocs[d.id!] = d;
              }
            } else {
              uniqueDocs[d.id!] = d;
            }
          }
        }
        
        _documents = uniqueDocs.values.toList();
        _documents.sort((a, b) => (b.modifiedTime ?? DateTime.now().toUtc()).compareTo(a.modifiedTime ?? DateTime.now().toUtc()));
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreateDocumentDialog() async {
    final titleController = TextEditingController(text: 'New Legal Document');
    String? selectedWorkId;
    List<old.Deal> availableDeals = [];
    bool isLoadingDeals = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isLoadingDeals) {
              DealService().getAllDeals().then((deals) {
                if (mounted) {
                  setDialogState(() {
                    availableDeals = deals;
                    isLoadingDeals = false;
                  });
                }
              });
            }

            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              title: const Text('Create New Document', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat'),
                      decoration: InputDecoration(
                        labelText: 'Document Name',
                        labelStyle: const TextStyle(color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.backgroundColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isLoadingDeals)
                      const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
                    else
                      DropdownButtonFormField<String>(
                        value: selectedWorkId,
                        dropdownColor: AppTheme.surfaceColor,
                        decoration: InputDecoration(
                          labelText: 'Link to Work (Optional)',
                          labelStyle: const TextStyle(color: AppTheme.textSecondary),
                          filled: true,
                          fillColor: AppTheme.backgroundColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('None (Unlinked)', style: TextStyle(color: AppTheme.textPrimary))),
                          ...availableDeals.map((d) => DropdownMenuItem(
                            value: d.id.toString(),
                            child: Text(d.name, style: const TextStyle(color: AppTheme.textPrimary)),
                          ))
                        ],
                        onChanged: (val) {
                          setDialogState(() => selectedWorkId = val);
                          if (val != null) {
                            final d = availableDeals.firstWhere((element) => element.id.toString() == val);
                            titleController.text = '${d.name} - Document';
                          }
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    Navigator.of(ctx).pop({'title': title, 'workId': selectedWorkId});
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
                  child: const Text('Create', style: TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold, fontFamily: 'Montserrat')),
                ),
              ],
            );
          },
        );
      },
    ).then((result) async {
      if (result != null && result is Map) {
        final title = result['title'] as String;
        final workId = result['workId'] as String?;
        await _createNewDocument(title, workId: workId);
      }
    });
  }

  Future<void> _createNewDocument(String title, {String? workId}) async {
    setState(() => _isLoading = true);
    try {
      final url = await MicrosoftWordService.createNewDocument(title);
      if (mounted) {
        setState(() => _isLoading = false);
      }
      if (url != null) {
        if (workId != null) {
          try {
            final deals = await DealService().getAllDeals();
            final deal = deals.firstWhere((d) => d.id.toString() == workId);
            List<Map<String, String>> docs = [];
            if (deal.driveLink != null && deal.driveLink!.isNotEmpty) {
              try {
                final parsed = jsonDecode(deal.driveLink!);
                for (var p in parsed) {
                  docs.add({"name": p["name"].toString(), "url": p["url"].toString()});
                }
              } catch (_) {}
            }
            docs.add({"name": title, "url": url});
            
            // Assuming the `deal.dart` model allows replacing driveLink, but it's a final field in `old.Deal`!
            // Wait, I saw deal.driveLink is final, we must use copyWith or pass it differently. Let me just mutate it in a Map since it's sent to updateDeal.
            // Oh, Deal model doesn't have a mutable driveLink. I will reconstruct Deal or use copyWith if it has it.
            // Let me use a workaround if needed: 
            // In deal_service.dart, updateDeal gets deal.toMap() and updates.
            final map = deal.toMap();
            map['drive_link'] = jsonEncode(docs);
            final updatedDeal = old.Deal.fromMap(map);
            await DealService().updateDeal(updatedDeal);
          } catch (e) {
            print('Error linking to deal: $e');
          }
        }
        
        final RegExp regex = RegExp(r'/d/([^/]+)/');
        final match = regex.firstMatch(url);
        final docId = match?.group(1);
        
        final newFile = drive.File(
          id: docId,
          name: title,
          webViewLink: url,
          modifiedTime: DateTime.now().toUtc(),
        );

        if (mounted) {
          setState(() {
            _documents.insert(0, newFile);
          });
        }
        
        final cached = await _loadLocalDocumentsCache();
        cached.insert(0, newFile);
        await _saveLocalDocumentsCache(cached);
        
        _openUrl(url, title);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create document.', style: TextStyle(fontFamily: 'Montserrat'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (e.toString().contains('Session expired')) {
            _currentUser = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e', style: const TextStyle(fontFamily: 'Montserrat', fontSize: 12)),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(String? urlString, String title) async {
    if (urlString != null) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WordWebviewScreen(
              url: urlString,
              title: title,
            ),
          ),
        ).then((_) => _loadDocuments());
      }
    } else {
      print('Could not launch document');
    }
  }

  Future<void> _showAiSummary(dynamic doc) async {
    if (doc['id'] == null) return;
    
    // Show a loading dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ),
    );

    try {
      final summary = await AiService.summarizeDocument(doc['id']!, doc['name'] ?? 'Document');
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Show summary bottom sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: AppTheme.accentColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        summary['title'],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontFamily: 'Montserrat'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummarySection('Key Points', summary['key_points'], Icons.format_list_bulleted),
                      const SizedBox(height: 24),
                      _buildSummarySection('Parties Involved', summary['parties_involved'], Icons.people),
                      const SizedBox(height: 24),
                      _buildSummarySection('Recommended Actions', summary['recommended_actions'], Icons.next_plan),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating summary: $e')));
    }
  }

  Widget _buildSummarySection(String title, List<dynamic> items, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.accentColor, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontFamily: 'Montserrat')),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
              Expanded(child: Text(item.toString(), style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat', height: 1.5))),
            ],
          ),
        )),
      ],
    );
  }

  Future<void> _confirmDelete(dynamic doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Delete Document', style: TextStyle(color: AppTheme.textPrimary, fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${doc['name']}"? This action cannot be undone and will permanently delete the file from your Documents Vault.', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Montserrat')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('DELETE', style: TextStyle(color: AppTheme.errorRed, fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && doc['id'] != null) {
      setState(() => _isLoading = true);
      try {
        final success = await MicrosoftWordService.deleteDocument(doc['id']!);
        
        bool deletedLocally = false;
        
        // Remove from local cache
        final cachedDocs = await _loadLocalDocumentsCache();
        final initialLength = cachedDocs.length;
        cachedDocs.removeWhere((d) => d['id'] == doc['id']);
        if (cachedDocs.length < initialLength) {
           await _saveLocalDocumentsCache(cachedDocs);
           deletedLocally = true;
        }
        
        // Remove from Deals
        try {
          final deals = await DealService().getAllDeals();
          for (var deal in deals) {
            if (deal.driveLink != null && deal.driveLink!.isNotEmpty) {
              try {
                final parsed = List<dynamic>.from(jsonDecode(deal.driveLink!));
                final originalCount = parsed.length;
                parsed.removeWhere((p) {
                   final urlStr = p['url']?.toString() ?? '';
                   return urlStr.contains(doc['id']!);
                });
                if (parsed.length < originalCount) {
                   final map = deal.toMap();
                   map['drive_link'] = jsonEncode(parsed);
                   await DealService().updateDeal(old.Deal.fromMap(map));
                   deletedLocally = true;
                }
              } catch (_) {}
            }
          }
        } catch (_) {}

        if (mounted) {
          if (success || deletedLocally) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Document deleted successfully', style: TextStyle(fontFamily: 'Montserrat', color: Colors.white)),
                backgroundColor: AppTheme.successGreen,
              ),
            );
            _loadDocuments();
          } else {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to delete document', style: TextStyle(fontFamily: 'Montserrat', color: Colors.white)),
                backgroundColor: AppTheme.errorRed,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            if (e.toString().contains('Session expired')) {
              _currentUser = null;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.accentColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Image.asset('assets/logo.png', width: 28, height: 28),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Documents Vault',
                  style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                Text(
                  _currentUser != null ? _currentUser! : 'Not Signed In',
                  style: const TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_currentUser != null)
            IconButton(
              icon: const Icon(Icons.logout, color: AppTheme.errorRed),
              tooltip: 'Sign Out',
              onPressed: _signOut,
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, AppTheme.accentColor.withValues(alpha: 0.3), Colors.transparent],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _currentUser != null
          ? FloatingActionButton.extended(
              onPressed: _showCreateDocumentDialog,
              backgroundColor: AppTheme.accentColor,
              foregroundColor: AppTheme.backgroundColor,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('NEW GOOGLE DOC', style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            )
          : null,
      body: _currentUser == null
          ? _buildSignInState()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.12)),
                    ),
                    child: TextField(
                      style: const TextStyle(fontFamily: 'Montserrat', color: AppTheme.textPrimary, fontSize: 13),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.textSecondary),
                        hintText: 'Search documents...',
                        hintStyle: TextStyle(fontFamily: 'Montserrat', color: AppTheme.textSecondary.withValues(alpha: 0.4), fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
                      : _buildLogsList(),
                ),
              ],
            ),
    );
  }

  Widget _buildSignInState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_sync, size: 64, color: AppTheme.accentColor),
          const SizedBox(height: 16),
          const Text('Connect to Documents Vault', style: TextStyle(fontFamily: 'Montserrat', fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Sign in with your Google account to view and manage your legal documents directly via your Documents Vault.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Montserrat', fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _signIn,
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    final filtered = _documents.where((d) => (d.name ?? '').toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text('No documents found in Documents Vault.', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        return Card(
          color: AppTheme.secondaryColor,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.description, color: Colors.blueAccent),
            title: Text(doc['name'] ?? 'Untitled', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text('Modified: ${doc['lastModifiedDateTime'] != null ? DateTime.parse(doc['lastModifiedDateTime']).toLocal().toString().split('.')[0] : ''}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: AppTheme.accentColor, size: 20),
                  onPressed: () => _showAiSummary(doc),
                  tooltip: 'AI Summarize',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed, size: 20),
                  onPressed: () => _confirmDelete(doc),
                  tooltip: 'Delete Document',
                ),
                const Icon(Icons.open_in_new, color: AppTheme.accentColor, size: 18),
              ],
            ),
            onTap: () => _openUrl(doc['webUrl'], doc['name'] ?? 'Word Doc'),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideX();
      },
    );
  }
}
