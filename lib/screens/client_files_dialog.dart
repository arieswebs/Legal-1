import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client.dart';
import '../services/logging_service.dart';
import '../models/ChamberDocuments.dart' as amplify_models;

class ClientFilesDialog extends StatefulWidget {
  final Client client;

  const ClientFilesDialog({super.key, required this.client});

  @override
  State<ClientFilesDialog> createState() => _ClientFilesDialogState();
}

class _ClientFilesDialogState extends State<ClientFilesDialog> {
  bool _isLoading = true;
  List<StorageItem> _personalFiles = [];
  List<StorageItem> _workItems = [];
  List<StorageItem> _voiceNotes = [];
  String? _currentWorkFolder;
  String _currentTab = 'personal'; // 'personal', 'work', or 'voice'

  bool _isRecording = false;
  final AudioRecorder _audioRecorder = AudioRecorder();

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles({bool isRetry = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final pResult = await Amplify.Storage.list(
        path: StoragePath.fromString('${widget.client.id}/personal/'),
      ).result;
      
      final workPathStr = _currentWorkFolder == null 
          ? '${widget.client.id}/work/' 
          : '${widget.client.id}/work/$_currentWorkFolder/';
          
      final wResult = await Amplify.Storage.list(
        path: StoragePath.fromString(workPathStr),
      ).result;
      
      final vResult = await Amplify.Storage.list(
        path: StoragePath.fromString('${widget.client.id}/voice/'),
      ).result;
      
      if (!mounted) return;
      setState(() {
        _personalFiles = pResult.items.where((f) => !f.path.contains('.emptyPlaceholder')).toList();
        _workItems = wResult.items.where((f) => !f.path.contains('.emptyPlaceholder')).toList();
        _voiceNotes = vResult.items.where((f) => !f.path.contains('.emptyPlaceholder')).toList();
      });
    } catch (e) {
      debugPrint("Load files error: $e");
      final errStr = e.toString();
      if (!isRetry && (errStr.contains('SessionExpiredException') || errStr.contains('NotAuthorizedException') || errStr.contains('AWS credentials'))) {
        try {
          await Amplify.Auth.fetchAuthSession(
            options: const FetchAuthSessionOptions(forceRefresh: true),
          );
          return await _loadFiles(isRetry: true);
        } catch (refreshErr) {
          debugPrint("Failed to force refresh session: $refreshErr");
        }
      }
      if (mounted && (errStr.contains('SessionExpiredException') || errStr.contains('NotAuthorizedException'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AWS Session Expired: Please sign out and sign back in to refresh credentials.'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createFolder() async {
    final folder = await _showWorkPrefixDialog();
    if (folder == null || folder.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final path = '${widget.client.id}/work/${folder.replaceAll('/', '_')}/.emptyPlaceholder';
      
      await Amplify.Storage.uploadData(
        data: StorageDataPayload.string('folder_placeholder'),
        path: StoragePath.fromString(path),
      ).result;
      
      await _logUpload('work', 'Folder Created: $folder');
      await _loadFiles();
    } catch (e) {
      debugPrint('Create folder error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create folder: $e'), backgroundColor: Colors.redAccent));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        await _uploadVoiceNote(path);
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: filePath);
        setState(() => _isRecording = true);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission denied'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _uploadVoiceNote(String path) async {
    setState(() => _isLoading = true);
    try {
      final file = File(path);
      final fileBytes = await file.readAsBytes();
      final fileName = path.split('/').last.split('\\').last;
      
      final storagePath = '${widget.client.id}/voice/$fileName';
      
      await Amplify.Storage.uploadData(
        data: StorageDataPayload.bytes(fileBytes),
        path: StoragePath.fromString(storagePath),
      ).result;
      
      try {
        final doc = amplify_models.ChamberDocuments(
          title: fileName,
          file_path: storagePath,
          category: 'voice',
        );
        await Amplify.API.mutate(request: ModelMutations.create(doc)).response;
      } catch (dbErr) {
        debugPrint('DB log warning: $dbErr');
      }

      await _logUpload('voice', fileName);
      await _loadFiles();
    } catch (e) {
      debugPrint("Voice upload error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadFile(String category) async {
    final result = await FilePicker.pickFiles(type: FileType.any, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      for (var f in result.files) {
        if (f.bytes == null && f.path == null) continue;
        
        final fileName = f.name;
        String storagePath;
        if (category == 'personal') {
          storagePath = '${widget.client.id}/personal/$fileName';
        } else if (category == 'voice') {
          storagePath = '${widget.client.id}/voice/$fileName';
        } else {
          storagePath = _currentWorkFolder == null 
              ? '${widget.client.id}/work/$fileName' 
              : '${widget.client.id}/work/$_currentWorkFolder/$fileName';
        }

        if (f.bytes != null) {
          await Amplify.Storage.uploadData(
            data: StorageDataPayload.bytes(f.bytes!),
            path: StoragePath.fromString(storagePath),
          ).result;
        } else if (f.path != null) {
          final file = File(f.path!);
          await Amplify.Storage.uploadData(
            data: StorageDataPayload.bytes(await file.readAsBytes()),
            path: StoragePath.fromString(storagePath),
          ).result;
        }

        try {
          final doc = amplify_models.ChamberDocuments(
            title: fileName,
            file_path: storagePath,
            category: category,
          );
          await Amplify.API.mutate(request: ModelMutations.create(doc)).response;
        } catch (dbErr) {
          debugPrint('DB log warning: $dbErr');
        }

        await _logUpload(category, fileName);
      }
      await _loadFiles();
    } catch (e) {
      debugPrint("Upload file error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logUpload(String category, String fileName) async {
    await LoggingService().logAction(
      action: 'FILE_UPLOADED',
      targetType: 'ClientVault',
      targetId: widget.client.id ?? 'Unknown',
      details: 'Uploaded $fileName to $category',
    );
  }

  Future<String?> _showWorkPrefixDialog() async {
    String? prefix;
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          title: Text("Create Work Folder", style: GoogleFonts.cormorantGaramond(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 22)),
          content: TextField(
            controller: ctrl,
            style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Montserrat', fontSize: 14),
            decoration: const InputDecoration(
              hintText: "e.g. GST Return Q1",
              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Montserrat', fontSize: 13),
              helperText: "A new folder will be created for this work",
              helperStyle: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat', fontSize: 12),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0F172A))),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: const Color(0xFFD4AF37), elevation: 0),
              onPressed: () {
                prefix = ctrl.text;
                Navigator.pop(context);
              },
              child: const Text("Create Folder", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Montserrat')),
            ),
          ],
        );
      }
    );
    return prefix;
  }

  Future<void> _deleteFile(String category, String fileName, {bool isFolder = false, String? itemPath}) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: Text(isFolder ? 'Delete Folder' : 'Delete File', style: GoogleFonts.cormorantGaramond(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 22)),
        content: Text('Are you sure you want to delete "$fileName"?', style: const TextStyle(color: Color(0xFF475569), fontFamily: 'Montserrat')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Montserrat'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white, elevation: 0),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Delete', style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        if (isFolder) {
          final files = await Amplify.Storage.list(path: StoragePath.fromString('${widget.client.id}/work/$fileName/')).result;
          for (var file in files.items) {
             await Amplify.Storage.remove(path: StoragePath.fromString(file.path)).result;
          }
        } else if (itemPath != null) {
          await Amplify.Storage.remove(path: StoragePath.fromString(itemPath)).result;
        }
        await _loadFiles();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.redAccent));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _downloadFile(String itemPath) async {
    try {
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(itemPath),
        options: const StorageGetUrlOptions(
          pluginOptions: S3GetUrlPluginOptions(
            validateObjectExistence: true,
            expiresIn: Duration(hours: 1),
          ),
        ),
      ).result;
      
      if (await canLaunchUrl(result.url)) {
        await launchUrl(result.url);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open file: $e'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 24,
      insetPadding: const EdgeInsets.all(32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 750),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Premium dark background
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF334155), width: 1.2), // Darker border
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              // Sidebar Navigation
              Container(
                width: 260,
                color: const Color(0xFF1E293B), // Lighter slate for sidebar
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFD4AF37)),
                                ),
                                child: const Icon(Icons.folder_special_rounded, color: Color(0xFFD4AF37), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'FILES VAULT',
                                  style: GoogleFonts.cormorantGaramond(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFD4AF37), // Gold header
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.client.name ?? 'Client Files',
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              color: Color(0xFF94A3B8), // Lighter subtitle
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFF334155)),
                    const SizedBox(height: 16),
                    _buildNavItem('Personal Details', Icons.person_outline_rounded, 'personal'),
                    _buildNavItem('Work Folders', Icons.work_outline_rounded, 'work'),
                    _buildNavItem('Voice Notes', Icons.mic_none_rounded, 'voice'),
                  ],
                ),
              ),
              
              // Vertical Divider
              Container(width: 1, color: const Color(0xFF334155)),
              
              // Main Content Area
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Header Bar
                    Container(
                      height: 80,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1.2)),
                      ),
                      child: Row(
                        children: [
                          if (_currentTab == 'work' && _currentWorkFolder != null) ...[
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                              onPressed: () {
                                setState(() => _currentWorkFolder = null);
                                _loadFiles();
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                side: const BorderSide(color: Color(0xFF334155)),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Expanded(
                            child: Text(
                              _currentTab == 'personal' ? 'Personal Files' 
                              : _currentTab == 'voice' ? 'Voice Notes'
                              : _currentWorkFolder == null ? 'Work Folders' 
                              : _currentWorkFolder!,
                              style: GoogleFonts.cormorantGaramond(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFD4AF37), // Gold title
                              ),
                            ),
                          ),
                          if (_currentTab == 'voice') ...[
                            ElevatedButton.icon(
                              onPressed: () => _uploadFile('voice'),
                              icon: const Icon(Icons.cloud_upload_outlined, size: 18, color: Color(0xFFD4AF37)),
                              label: const Text('Upload Audio', style: TextStyle(color: Color(0xFFD4AF37))),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: const Color(0xFFD4AF37),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(color: Color(0xFFD4AF37)),
                                ),
                                textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _toggleRecording,
                              icon: Icon(_isRecording ? Icons.stop_circle_outlined : Icons.mic_none_rounded, size: 18),
                              label: Text(_isRecording ? 'Stop Recording' : 'Record Audio'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isRecording ? const Color(0xFFDC2626) : const Color(0xFFD4AF37),
                                foregroundColor: _isRecording ? Colors.white : const Color(0xFF0F172A),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ] else ...[
                            ElevatedButton.icon(
                              onPressed: () {
                                if (_currentTab == 'work' && _currentWorkFolder == null) {
                                  _createFolder();
                                } else {
                                  _uploadFile(_currentTab);
                                }
                              },
                              icon: Icon(_currentTab == 'work' && _currentWorkFolder == null ? Icons.create_new_folder_rounded : Icons.cloud_upload_rounded, size: 18, color: const Color(0xFF0F172A)),
                              label: Text(_currentTab == 'work' && _currentWorkFolder == null ? 'New Folder' : 'Upload File', style: const TextStyle(fontFamily: 'Montserrat', color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4AF37),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                            onPressed: () => Navigator.pop(context),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              side: const BorderSide(color: Color(0xFF334155)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Content Area
                    Expanded(
                      child: Container(
                        color: const Color(0xFF0F172A), // Dark body
                        child: _isLoading 
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                          : _currentTab == 'personal' 
                              ? _buildFileList(_personalFiles, 'personal') 
                              : _currentTab == 'voice' 
                                  ? _buildFileList(_voiceNotes, 'voice')
                                  : _buildFileList(_workItems, 'work'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 250.ms).scaleXY(begin: 0.98, end: 1.0, curve: Curves.easeOutQuart),
    );
  }

  Widget _buildNavItem(String title, IconData icon, String tab) {
    final isSelected = _currentTab == tab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _currentTab = tab;
              _currentWorkFolder = null;
            });
            _loadFiles();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF334155) : Colors.transparent, // Subtle dark active state
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? const Color(0xFFD4AF37) : const Color(0xFF94A3B8), size: 20),
                const SizedBox(width: 12),
                Text(
                  title, 
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8), 
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(List<StorageItem> files, String category) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF334155))),
              child: const Icon(Icons.folder_open_rounded, size: 48, color: Color(0xFFD4AF37)),
            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 20),
            Text(
              category == 'work' && _currentWorkFolder == null ? "No Work Folders Created Yet" 
              : category == 'voice' ? "No Voice Notes Recorded Yet"
              : "No Files Uploaded Here Yet", 
              style: GoogleFonts.cormorantGaramond(color: const Color(0xFFD4AF37), fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Click the action button above to upload or create a new file.", 
              style: TextStyle(fontFamily: 'Montserrat', color: Color(0xFF94A3B8), fontSize: 13.5),
            ),
          ],
        ).animate().fadeIn().slideY(begin: 0.1),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(28),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isFolder = category == 'work' && _currentWorkFolder == null && (file.path.endsWith('/'));
        
        final fileName = file.path.split('/').where((s) => s.isNotEmpty).last;

        if (isFolder) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155), width: 1.2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () {
                  setState(() => _currentWorkFolder = fileName);
                  _loadFiles();
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Icon(Icons.folder_rounded, color: Color(0xFFD4AF37), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          fileName,
                          style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF94A3B8), size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(delay: (30 * index).ms).slideY(begin: 0.05);
        }

        // File Item
        IconData icon = Icons.insert_drive_file_rounded;
        Color iconColor = const Color(0xFF94A3B8);
        Color iconBg = const Color(0xFF334155);
        
        final lowerName = fileName.toLowerCase();
        if (lowerName.endsWith('.pdf')) {
          icon = Icons.picture_as_pdf_rounded;
          iconColor = const Color(0xFFFCA5A5);
          iconBg = const Color(0xFFDC2626).withValues(alpha: 0.15);
        } else if (lowerName.endsWith('.jpg') || lowerName.endsWith('.png') || lowerName.endsWith('.jpeg')) {
          icon = Icons.image_rounded;
          iconColor = const Color(0xFFC4B5FD);
          iconBg = const Color(0xFF8B5CF6).withValues(alpha: 0.15);
        } else if (lowerName.endsWith('.m4a') || lowerName.endsWith('.mp3') || lowerName.endsWith('.wav')) {
          icon = Icons.audiotrack_rounded;
          iconColor = const Color(0xFFFDE68A);
          iconBg = const Color(0xFFD97706).withValues(alpha: 0.15);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF334155), width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName, 
                        style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white), 
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Size: ${(file.size ?? 0) ~/ 1024} KB', 
                        style: const TextStyle(fontFamily: 'Montserrat', color: Color(0xFF94A3B8), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Color(0xFFD4AF37), size: 18),
                      onPressed: () => _downloadFile(file.path),
                      tooltip: "Download File",
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFF334155), side: const BorderSide(color: Color(0xFF475569))),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFCA5A5), size: 18),
                      onPressed: () => _deleteFile(category, fileName, itemPath: file.path),
                      tooltip: "Delete File",
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.15)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: (30 * index).ms).slideY(begin: 0.05);
      },
    );
  }
}
