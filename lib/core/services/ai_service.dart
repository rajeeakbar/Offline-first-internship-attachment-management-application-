import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/supabase_config.dart';

final aiServiceProvider = Provider((ref) => AIService());

class AIService {
  late final GenerativeModel _model;
  bool _isInitialized = false;

  AIService() {
    try {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: AppConfig.geminiApiKey,
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('AI Service Initialization Error: $e');
    }
  }

  /// Professionally rewrites log text using Google Gemini.
  Future<String> refineLog(String input) async {
    if (input.trim().isEmpty) return input;

    if (!_isInitialized) {
      return _refineHeuristic(input);
    }

    try {
      final prompt = 'Rewrite the following internship log entry to be more professional, formal, and suitable for an official industrial attachment report. Keep it concise but descriptive. Input: "$input"';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      final text = response.text;
      if (text != null && text.isNotEmpty) {
        return text.trim();
      }
      return _refineHeuristic(input);
    } catch (e) {
      debugPrint('Gemini API Error (refineLog): $e');
      return _refineHeuristic(input);
    }
  }

  /// Generates a weekly summary of internship activities.
  Future<String> generateWeeklySummary(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return 'No progress recorded this week.';

    if (!_isInitialized) {
      final activities = logs.take(5).map((l) => l['work_description']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');
      return 'Summary of Week: Primary activities focused on $activities. Significant milestones were achieved.';
    }

    try {
      final descriptions = logs.map((l) => '- ${l['work_description']}').join('\n');
      final prompt = 'Based on the following daily log entries for an intern, generate a professional weekly summary (2-3 sentences) suitable for a supervisor review:\n$descriptions';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      return response.text?.trim() ?? 'Summary generation failed.';
    } catch (e) {
      debugPrint('Gemini API Error (generateWeeklySummary): $e');
      return 'Failed to generate automated summary due to connection issues.';
    }
  }

  /// Sophisticated fallback professional mapping
  String _refineHeuristic(String input) {
    String refined = input.trim();

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

    if (refined.split(' ').length < 6) {
      refined = 'Actively participated in operational tasks where $refined';
    }

    return refined;
  }
}
