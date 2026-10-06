import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'microsoft_word_service.dart';

class AiService {
  /// Calls the Gemini API to summarize the document.
  /// Falls back to a basic heuristic if the GEMINI_API_KEY is not set.
  static Future<Map<String, dynamic>> summarizeDocument(String documentId, String documentName) async {
    try {
      final text = await MicrosoftWordService.getDocumentText(documentId);
      final cleanText = text.trim();
      
      if (cleanText.isEmpty) {
        return {
          'title': 'AI Summary: $documentName',
          'key_points': [
            'This document is currently empty.',
            'No content available to analyze.'
          ],
          'parties_involved': ['None'],
          'recommended_actions': [
            'Add content to the document before requesting a summary.'
          ],
          'confidence_score': 1.0,
        };
      }

      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? const String.fromEnvironment('GEMINI_API_KEY');
      
      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey');
          
          final prompt = '''
You are a legal AI assistant. Read the following document and provide a structured JSON summary.
DO NOT use markdown formatting like ```json in your response. Just return the raw JSON string.

Document:
$cleanText

Output JSON schema:
{
  "key_points": ["point 1", "point 2"],
  "parties_involved": ["party 1", "party 2"],
  "recommended_actions": ["action 1", "action 2"],
  "confidence_score": 0.95
}
''';

          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                 'responseMimeType': 'application/json',
              }
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final contentText = data['candidates'][0]['content']['parts'][0]['text'];
            final Map<String, dynamic> parsed = jsonDecode(contentText);
            
            return {
              'title': 'AI Summary: $documentName',
              'key_points': parsed['key_points'] ?? [],
              'parties_involved': parsed['parties_involved'] ?? [],
              'recommended_actions': parsed['recommended_actions'] ?? [],
              'confidence_score': parsed['confidence_score'] ?? 0.9,
            };
          } else {
            print('Gemini Error: \${response.body}');
          }
        } catch (e) {
          print('Error calling Gemini: $e');
        }
      }

      // Basic pseudo-summarization for non-empty docs (Fallback)
      final sentences = cleanText.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().length > 10).toList();
      final keyPoints = sentences.take(3).map((s) => s.trim()).toList();
      if (keyPoints.isEmpty) {
        keyPoints.add('Document contains formatting or short fragments.');
      }

      // Naive party extraction: Capitalized words (2 or more words)
      final partyRegex = RegExp(r'\b([A-Z][a-z]+(?: [A-Z][a-z]+)+)\b');
      final parties = partyRegex.allMatches(cleanText).map((m) => m.group(0)!).toSet().toList();
      
      return {
        'title': 'AI Summary: $documentName',
        'key_points': keyPoints.isNotEmpty ? keyPoints : ['Document has content, but no clear sentences found.'],
        'parties_involved': parties.isNotEmpty ? parties.take(3).toList() : ['Unknown'],
        'recommended_actions': [
          'Review the document manually as it has limited context for full analysis.',
        ],
        'confidence_score': 0.65,
      };
    } catch (e) {
      return {
        'title': 'Error Summarizing',
        'key_points': ['Failed to read document: $e'],
        'parties_involved': [],
        'recommended_actions': [],
        'confidence_score': 0.0,
      };
    }
  }
}
