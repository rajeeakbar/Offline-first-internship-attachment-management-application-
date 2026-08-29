import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../config/supabase_config.dart';
import 'network_utility.dart';

final aiServiceProvider = Provider((ref) => AIService());

class AIService {
  bool _isInitialized = false;
  String _activeApiKey = '';

  AIService() {
    _initialize();
  }

  void _initialize() {
    // Sanitize and clean the API key
    String apiKey = AppConfig.geminiApiKey.trim();
    apiKey = apiKey.replaceAll(RegExp(r'\s'), '').replaceAll('"', '').replaceAll("'", '');

    // Stop if there is no key
    if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_KEY') {
      debugPrint('❌ No API Key found.');
      _isInitialized = false;
      return;
    }

    if (!apiKey.startsWith('nvapi-')) {
      debugPrint('⚠️ Warning: API Key does not start with expected "nvapi-" prefix. Initializing anyway...');
    }

    try {
      // Connect to NVIDIA AI API using the correct /v1 endpoint
      OpenAI.baseUrl = 'https://integrate.api.nvidia.com/v1';
      OpenAI.apiKey = apiKey;
      _activeApiKey = apiKey;

      _isInitialized = true;
      debugPrint('✅ App is connected to NVIDIA AI at: ${OpenAI.baseUrl} (Key prefix: ${apiKey.substring(0, min(10, apiKey.length))}...)');
    } catch (e) {
      debugPrint('❌ Setup Error: $e');
      _isInitialized = false;
    }
  }

  /// Refines a student's daily log entry to sound highly professional.
  Future<String> refineLog(String input) async {
    if (input.trim().isEmpty) return input;

    // Check internet connection first to avoid timeout latency
    final hasInternet = await NetworkUtility.instance.hasInternetAccess();
    if (!hasInternet) {
      debugPrint('⚠️ Device offline, bypassing NVIDIA API to use local backup text-fixer.');
      return _refineHeuristic(input);
    }

    // Double check initialization in case of race conditions
    if (!_isInitialized) {
      _initialize();
    }

    // If setup failed or key is missing, we use the backup fixer
    if (!_isInitialized) {
      debugPrint('⚠️ AI Service not initialized, using backup text-fixer.');
      return _refineHeuristic(input);
    }

    debugPrint('📤 Sending your log to NVIDIA AI...');

    try {
      // Send the prompt using the active NVIDIA model
      final chatCompletion = await OpenAI.instance.chat.create(
        model: 'meta/llama-3.2-11b-vision-instruct',
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(
                '''
                Act as a professional industrial attachment/internship supervisor.
                Your task is to rewrite the student's daily log entry to be highly professional and suitable for a formal university report.

                Guidelines:
                - Use industry-standard terminology and active professional verbs (e.g., "Engineered", "Optimized", "Collaborated", "Analyzed").
                - Maintain a formal, sophisticated, yet authentic tone.
                - Correct all grammatical, spelling, and punctuation errors.
                - Ensure the description is detailed but concise.
                - Focus on the technical and professional growth aspects of the work.
                - Do not add information that isn't implied by the original entry, but feel free to elaborate on the professional impact.
                - Return ONLY the rewritten text, without any introductory phrases like "Here is the professional version."

                Student's Original Entry: "$input"
                ''',
              ),
            ],
          ),
        ],
        maxTokens: 200,
        temperature: 0.7,
      );

      // Get the result
      final refinedText = chatCompletion.choices.first.message.content?.first.text;

      if (refinedText != null && refinedText.isNotEmpty) {
        debugPrint('✅ AI Fixed it!');
        return refinedText.trim();
      } else {
        return await _refineLogManual(input);
      }
    } catch (e) {
      debugPrint('❌ NVIDIA SDK Error: $e. Attempting manual HTTP fallback...');
      return await _refineLogManual(input);
    }
  }

  /// Manual HTTP request fallback in case the SDK encounters issues.
  Future<String> _refineLogManual(String input) async {
    try {
      final url = Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions');
      final apiKey = _activeApiKey.isNotEmpty ? _activeApiKey : AppConfig.geminiApiKey.trim();

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'model': 'meta/llama-3.2-11b-vision-instruct',
          'messages': [
            {
              'role': 'user',
              'content': '''
              Act as a professional industrial attachment/internship supervisor.
              Your task is to rewrite the student's daily log entry to be highly professional and suitable for a formal university report.

              Guidelines:
              - Use industry-standard terminology and active professional verbs.
              - Maintain a formal tone.
              - Correct grammatical errors.
              - Return ONLY the rewritten text, without introductory or concluding conversational filler.

              Student's Original Entry: "$input"
              '''
            }
          ],
          'max_tokens': 200,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'];
        if (content != null && content.toString().trim().isNotEmpty) {
          debugPrint('✅ Manual HTTP request succeeded!');
          return content.toString().trim();
        }
      } else {
        debugPrint('❌ HTTP Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Manual HTTP Fallback Error: $e');
    }

    return _refineHeuristic(input);
  }

  /// Generates a weekly summary of internship activities.
  Future<String> generateWeeklySummary(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return 'No progress recorded this week.';

    String fallbackSummary() {
      final activities = logs.take(5).map((l) => l['work_description']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');
      return 'Summary of Week: Primary activities focused on $activities. Significant milestones were achieved.';
    }

    // Check internet connection first to avoid timeout latency
    final hasInternet = await NetworkUtility.instance.hasInternetAccess();
    if (!hasInternet) {
      debugPrint('⚠️ Device offline, bypassing NVIDIA API to use local weekly summary fallback.');
      return fallbackSummary();
    }

    // Double check initialization in case of race conditions
    if (!_isInitialized) {
      _initialize();
    }

    if (!_isInitialized) {
      return fallbackSummary();
    }

    try {
      final descriptions = logs.map((l) => '- ${l['work_description']}').join('\n');
      final chatCompletion = await OpenAI.instance.chat.create(
        model: 'meta/llama-3.2-11b-vision-instruct',
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(
                'Based on the following daily log entries for an intern, generate a professional weekly summary (2-3 sentences) suitable for a supervisor review:\n$descriptions',
              ),
            ],
          ),
        ],
        maxTokens: 150,
        temperature: 0.7,
      );

      final summaryText = chatCompletion.choices.first.message.content?.first.text;
      if (summaryText != null && summaryText.trim().isNotEmpty) {
        return summaryText.trim();
      }
    } catch (e) {
      debugPrint('NVIDIA API Error (generateWeeklySummary): $e');
    }

    return fallbackSummary();
  }

  /// Diagnostic method to test API connection.
  Future<bool> testApiConnection() async {
    try {
      debugPrint('🔍 Testing NVIDIA API connection...');
      final testCompletion = await OpenAI.instance.chat.create(
        model: 'meta/llama-3.2-11b-vision-instruct',
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text('Say "Hello"'),
            ],
          ),
        ],
        maxTokens: 10,
        temperature: 0.1,
      );

      if (testCompletion.choices.isNotEmpty) {
        final response = testCompletion.choices.first.message.content?.first.text;
        debugPrint('✅ API Test Response: $response');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ API Test Error: $e');
      return false;
    }
  }

  /// Public wrapper for offline heuristic refinement
  String refineHeuristic(String input) => _refineHeuristic(input);

  // --------------------------------
  // BACKUP FIXER (Works offline, no AI)
  // --------------------------------
  String _refineHeuristic(String input) {
    String refined = input.trim();

    // Replace casual words with business words
    final Map<String, String> corrections = {
      r'\bi did\b': 'I successfully executed',
      r'\bi made\b': 'I engineered',
      r'\bi saw\b': 'I observed and analyzed',
      r'\bfixed\b': 'rectified and optimized',
      r'\bworked on\b': 'contributed to the development of',
      r'\bhelped\b': 'collaborated with the team on',
      r'\blearned\b': 'gained specialized expertise in',
      r'\bgood\b': 'exemplary',
      r'\bbad\b': 'non-optimal',
      r'\bsetup\b': 'configured and deployed',
      r'\btold them\b': 'communicated to the stakeholders',
      r'\bstarted\b': 'initiated the deployment of',
      r'\bchecked\b': 'conducted a thorough verification of',
      r'\bcode\b': 'source code architecture',
      r'\bbugs\b': 'technical inconsistencies',
    };

    corrections.forEach((pattern, value) {
      refined = refined.replaceAll(RegExp(pattern, caseSensitive: false), value);
    });

    // Capitalize first letter and add a period if missing
    List<String> sentences = refined.split(RegExp(r'(?<=[.!?])\s+'));
    sentences = sentences.map((s) {
      if (s.isEmpty) return s;
      String processed = s.trim();
      processed = processed[0].toUpperCase() + processed.substring(1);
      if (!RegExp(r'[.!?]$').hasMatch(processed)) {
        processed += '.';
      }
      return processed;
    }).toList();

    refined = sentences.join(' ');

    // If the sentence is too short, add a generic opener
    if (refined.split(' ').length < 6) {
      refined = 'Actively participated in operational tasks where $refined';
    }

    return refined;
  }
}
