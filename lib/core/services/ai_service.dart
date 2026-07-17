import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dart_openai/dart_openai.dart'; // This talks to NVIDIA via OpenAI-compatible endpoint
import '../config/supabase_config.dart';

final aiServiceProvider = Provider((ref) => AIService());

class AIService {
  bool _isInitialized = false;

  AIService() {
    _initialize();
  }

  void _initialize() {
    final apiKey = AppConfig.geminiApiKey.trim(); // We keep using geminiApiKey from config, which now holds the NVIDIA API Key

    // Stop if there is no key
    if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_KEY') {
      debugPrint('❌ No API Key found.');
      _isInitialized = false;
      return;
    }

    try {
      // Connect to NVIDIA Free AI
      OpenAI.baseUrl = 'https://integrate.api.nvidia.com';
      OpenAI.apiKey = apiKey; // Your NVIDIA key goes here

      _isInitialized = true;
      debugPrint('✅ App is now connected to NVIDIA Free AI.');
    } catch (e) {
      debugPrint('❌ Setup Error: $e');
      _isInitialized = false;
    }
  }

  /// This is the button you press to make your log sound professional.
  Future<String> refineLog(String input) async {
    if (input.trim().isEmpty) return input;

    // Double check initialization in case of race conditions
    if (!_isInitialized) {
      _initialize();
    }

    // If the internet is off or NVIDIA fails, we use the backup fixer (heuristic)
    if (!_isInitialized) {
      debugPrint('⚠️ No internet/key, using backup text-fixer.');
      return _refineHeuristic(input);
    }

    debugPrint('📤 Sending your log to NVIDIA AI...');

    try {
      // Send the prompt to the meta/llama-3.1-8b-instruct model on NVIDIA
      final chatCompletion = await OpenAI.instance.chat.create(
        model: 'meta/llama-3.1-8b-instruct', // A very good free model from NVIDIA
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
        // If NVIDIA gives us nothing, use the backup fixer
        return _refineHeuristic(input);
      }
    } catch (e) {
      // If NVIDIA breaks (no internet, etc.), use the backup fixer
      debugPrint('❌ NVIDIA Error: $e. Using backup fixer.');
      return _refineHeuristic(input);
    }
  }

  /// Generates a weekly summary of internship activities.
  Future<String> generateWeeklySummary(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return 'No progress recorded this week.';

    // Double check initialization in case of race conditions
    if (!_isInitialized) {
      _initialize();
    }

    if (!_isInitialized) {
      final activities = logs.take(5).map((l) => l['work_description']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');
      return 'Summary of Week: Primary activities focused on $activities. Significant milestones were achieved.';
    }

    try {
      final descriptions = logs.map((l) => '- ${l['work_description']}').join('\n');
      final chatCompletion = await OpenAI.instance.chat.create(
        model: 'meta/llama-3.1-8b-instruct',
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
      return summaryText?.trim() ?? 'Summary generation failed.';
    } catch (e) {
      debugPrint('NVIDIA API Error (generateWeeklySummary): $e');
      return 'Failed to generate automated summary due to connection issues.';
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
