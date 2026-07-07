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
      refined = refined.replaceAll(RegExp(key, caseSensitive: false), value);
    });

    // Add a professional opening/closing if it looks like a short note
    if (refined.split(' ').length < 10) {
      refined = 'During today\'s session, $refined, ensuring all tasks met the expected standards.';
    }

    return refined;
  }
}
