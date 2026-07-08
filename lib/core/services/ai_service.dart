import 'package:flutter_riverpod/flutter_riverpod.dart';

final aiServiceProvider = Provider((ref) => AIService());

class AIService {
  String? _geminiApiKey;

  /// Update the API key for Gemini integration
  void setApiKey(String key) {
    _geminiApiKey = key;
  }

  /// Simulates an AI refinement of log text.
  /// If _geminiApiKey is set, it would ideally call the Google Generative AI API.
  Future<String> refineLog(String input) async {
    if (input.trim().isEmpty) return input;

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1500));

    if (_geminiApiKey != null && _geminiApiKey!.isNotEmpty) {
      // TODO: Implement actual google_generative_ai call here
      // For now, we still use the enhanced heuristic but signal Gemini readiness
      print('Gemini API Key detected. Readiness for Google AI established.');
    }

    String refined = input.trim();

    // Sophisticated professional mapping
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

    // Advanced Sentence Structuring
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

    // Contextual Enhancement for Professionalism
    if (refined.split(' ').length < 6) {
      refined = 'Actively participated in operational tasks where $refined';
    }

    return refined;
  }

  Future<String> generateWeeklySummary(List<Map<String, dynamic>> logs) async {
    await Future.delayed(const Duration(seconds: 3));
    if (logs.isEmpty) return 'No progress recorded this week.';

    final activities = logs.take(5).map((l) => l['work_description']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');

    return 'Summary of Week: Primary activities focused on $activities. Significant milestones were achieved in system implementation and professional development.';
  }
}
