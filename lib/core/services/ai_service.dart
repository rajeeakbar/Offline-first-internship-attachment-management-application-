import 'package:flutter_riverpod/flutter_riverpod.dart';

final aiServiceProvider = Provider((ref) => AIService());

class AIService {
  /// Simulates an AI refinement of log text.
  /// In a real app, this would call an OpenAI, Anthropic, or Supabase Edge Function.
  Future<String> refineLog(String input) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    if (input.trim().isEmpty) return input;

    // A simple mock "professionalization" for demonstration
    // In a real scenario, this is where the LLM prompt would go
    String refined = input.trim();

    // Simple heuristic improvements for common phrases
    final corrections = {
      'i did': 'I performed',
      'i made': 'I developed',
      'i saw': 'I observed',
      'fixed': 'resolved',
      'worked on': 'collaborated on the implementation of',
      'helped': 'assisted in',
      'learned': 'acquired proficiency in',
      'good': 'effective',
      'bad': 'suboptimal',
    };

    corrections.forEach((key, value) {
      refined = refined.replaceAll(RegExp('\\b$key\\b', caseSensitive: false), value);
    });

    // Sentence casing and punctuation check
    if (refined.isNotEmpty) {
      refined = refined[0].toUpperCase() + refined.substring(1);
      if (!refined.endsWith('.') && !refined.endsWith('!') && !refined.endsWith('?')) {
        refined += '.';
      }
    }

    // Context-aware prefixing for very short entries
    if (refined.split(' ').length < 5) {
      final hour = DateTime.now().hour;
      final timeContext = hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
      refined = 'During this $timeContext, I successfully $refined';
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
