import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:archive/archive.dart';

class MicrosoftWordService {
  static String get _clientId => dotenv.env['MICROSOFT_CLIENT_ID'] ?? '';
  static String get _tenantId => dotenv.env['MICROSOFT_TENANT_ID'] ?? 'common';

  static const String _scopes = 'Files.ReadWrite.All offline_access';
  static const String _credentialsKey = 'microsoft_graph_credentials';

  static String? _accessToken;
  static String? _refreshToken;
  static DateTime? _expiry;

  static Future<void> _saveCredentials(Map<String, dynamic> tokenData) async {
    final prefs = await SharedPreferences.getInstance();
    final expiryTime = DateTime.now().add(Duration(seconds: tokenData['expires_in'] as int));
    
    final data = {
      'accessToken': tokenData['access_token'],
      'refreshToken': tokenData['refresh_token'],
      'expiry': expiryTime.toIso8601String(),
    };
    
    _accessToken = data['accessToken'];
    _refreshToken = data['refreshToken'];
    _expiry = expiryTime;
    
    await prefs.setString(_credentialsKey, jsonEncode(data));
  }

  static Future<bool> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_credentialsKey);
    if (str == null) return false;
    
    try {
      final data = jsonDecode(str);
      _accessToken = data['accessToken'];
      _refreshToken = data['refreshToken'];
      _expiry = DateTime.parse(data['expiry']);
      
      if (_expiry!.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
        return await _refreshAccessToken();
      }
      return true;
    } catch (e) {
      print('Error loading credentials: $e');
      return false;
    }
  }

  static Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;
    
    final url = Uri.parse('https://login.microsoftonline.com/$_tenantId/oauth2/v2.0/token');
    final response = await http.post(url, body: {
      'client_id': _clientId,
      'grant_type': 'refresh_token',
      'refresh_token': _refreshToken,
      'scope': _scopes,
    });
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveCredentials(data);
      return true;
    }
    return false;
  }

  static Future<String?> signIn() async {
    try {
      if (await _loadCredentials()) {
        return 'Authenticated User';
      }

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
      final redirectUri = 'http://localhost:8080/';
      
      final authUrl = Uri.parse(
        'https://login.microsoftonline.com/$_tenantId/oauth2/v2.0/authorize'
        '?client_id=$_clientId'
        '&response_type=code'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&response_mode=query'
        '&scope=${Uri.encodeComponent(_scopes)}'
      );

      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch auth URL');
      }

      final request = await server.first;
      final code = request.uri.queryParameters['code'];
      
      request.response
        ..statusCode = 200
        ..headers.set('Content-Type', 'text/html')
        ..write('<html><body><h1>Authentication successful! You can close this tab.</h1></body></html>');
      await request.response.close();
      await server.close(force: true);

      if (code != null) {
        final tokenUrl = Uri.parse('https://login.microsoftonline.com/$_tenantId/oauth2/v2.0/token');
        final tokenResponse = await http.post(tokenUrl, body: {
          'client_id': _clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'scope': _scopes,
        });

        if (tokenResponse.statusCode == 200) {
          final data = jsonDecode(tokenResponse.body);
          await _saveCredentials(data);
          return 'Authenticated User';
        }
      }
      return null;
    } catch (e) {
      print('Microsoft Sign-In Error: $e');
      return null;
    }
  }

  static Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _expiry = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_credentialsKey);
  }

  static Future<String?> _getValidToken() async {
    if (!await _loadCredentials()) {
      await signIn();
    }
    return _accessToken;
  }

  static Future<List<dynamic>> getDriveFiles() async {
    final token = await _getValidToken();
    if (token == null) return [];

    try {
      final url = Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root/children?\$filter=file/mimeType eq \'application/vnd.openxmlformats-officedocument.wordprocessingml.document\'');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['value'] ?? [];
      } else {
        print('Error fetching drive files: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching drive files: $e');
      return [];
    }
  }

  static Future<String?> createNewDocument(String title, {String? content}) async {
    final token = await _getValidToken();
    if (token == null) return null;

    try {
      // Create empty docx
      final url = Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root/children/$title.docx/content');
      
      final response = await http.put(url, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      }, body: <int>[]);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['webUrl'];
      }
      return null;
    } catch (e) {
      print('Error creating document: $e');
      return null;
    }
  }

  static Future<bool> deleteDocument(String documentId) async {
    final token = await _getValidToken();
    if (token == null) return false;

    try {
      final url = Uri.parse('https://graph.microsoft.com/v1.0/me/drive/items/$documentId');
      final response = await http.delete(url, headers: {
        'Authorization': 'Bearer $token',
      });
      return response.statusCode == 204;
    } catch (e) {
      print('Error deleting document: $e');
      return false;
    }
  }

  static Future<String> getDocumentText(String documentId) async {
    final token = await _getValidToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final url = Uri.parse('https://graph.microsoft.com/v1.0/me/drive/items/$documentId/content');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final archive = ZipDecoder().decodeBytes(bytes);
        
        for (final file in archive) {
          if (file.name == 'word/document.xml') {
            final content = utf8.decode(file.content as List<int>);
            final text = content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ');
            return text.trim();
          }
        }
        return '';
      } else {
        throw Exception('Failed to download document content: ${response.statusCode}');
      }
    } catch (e) {
      print('Error reading document: $e');
      throw Exception(e.toString());
    }
  }
}
