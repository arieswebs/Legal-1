import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive.dart';

class WordWebviewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WordWebviewScreen({
    super.key,
    required this.url,
    this.title = 'Microsoft Word Online',
  });

  @override
  State<WordWebviewScreen> createState() => _WordWebviewScreenState();
}

class _WordWebviewScreenState extends State<WordWebviewScreen> {
  final _controller = WebviewController();
  bool _isLoading = true;
  bool _isWebviewInitialized = false;
  bool _hasError = false;

  static bool _environmentInitialized = false;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    try {
      if (!_environmentInitialized) {
        final appDir = await getApplicationSupportDirectory();
        final userDataPath = '${appDir.path}${Platform.pathSeparator}word_webview_data';
        await Directory(userDataPath).create(recursive: true);
        await WebviewController.initializeEnvironment(
          userDataPath: userDataPath,
        );
        _environmentInitialized = true;
      }

      await _controller.initialize();

      _controller.loadingState.listen((state) {
        if (mounted) {
          setState(() {
            _isLoading = state == LoadingState.loading;
          });
        }
      });

      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      if (!mounted) return;
      setState(() {
        _isWebviewInitialized = true;
      });

      await _controller.loadUrl(widget.url);
    } on PlatformException catch (e) {
      if (e.code == 'environment_already_initialized' || _environmentInitialized) {
        _environmentInitialized = true;
        try {
          if (!_controller.value.isInitialized) {
            await _controller.initialize();
          }

          _controller.loadingState.listen((state) {
            if (mounted) {
              setState(() {
                _isLoading = state == LoadingState.loading;
              });
            }
          });

          await _controller.setBackgroundColor(Colors.transparent);
          await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

          if (!mounted) return;
          setState(() {
            _isWebviewInitialized = true;
          });

          await _controller.loadUrl(widget.url);
          return;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.accentColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_rounded, color: AppTheme.accentColor, size: 20),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                  ),
            ),
          ],
        ),
        actions: [
          if (_isWebviewInitialized)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentColor),
              onPressed: () {
                _controller.reload();
              },
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: AppTheme.accentColor.withValues(alpha: 0.15),
            height: 1.0,
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_isWebviewInitialized)
              Webview(
                _controller,
                permissionRequested: (url, permissionKind, isUserInitiated) async {
                  return WebviewPermissionDecision.allow;
                },
              ),
            if (_isLoading && !_hasError)
              IgnorePointer(
                child: Container(
                  color: AppTheme.backgroundColor.withValues(alpha: 0.6),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                    ),
                  ),
                ),
              ),
            if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.errorRed, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to initialize WebView2 Runtime.\nPlease ensure WebView2 is installed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.errorRed, fontFamily: 'Montserrat', fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _hasError = false;
                          _isLoading = true;
                        });
                        initPlatformState();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }
}
