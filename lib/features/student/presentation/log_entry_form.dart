import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/ai_service.dart';
import '../../auth/data/auth_repository.dart';

class LogEntryForm extends ConsumerStatefulWidget {
  const LogEntryForm({super.key});

  @override
  ConsumerState<LogEntryForm> createState() => _LogEntryFormState();
}

class _LogEntryFormState extends ConsumerState<LogEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _workController = TextEditingController();
  final _knowledgeController = TextEditingController();
  bool _isRefiningWork = false;
  bool _isRefiningKnowledge = false;

  Future<void> _refineText(TextEditingController controller, bool isWork) async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    // Pillar: Offline-First AI Pattern
    // 1. Apply heuristic instantly
    final aiService = ref.read(aiServiceProvider);
    final offlineRefined = aiService.refineHeuristic(text);
    controller.text = offlineRefined;

    setState(() {
      if (isWork) {
        _isRefiningWork = true;
      } else {
        _isRefiningKnowledge = true;
      }
    });

    try {
      // 2. Try Gemini in background for upgrade
      final refined = await aiService.refineLog(text).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      setState(() {
        controller.text = refined;
        if (isWork) {
          _isRefiningWork = false;
        } else {
          _isRefiningKnowledge = false;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(refined == offlineRefined
              ? 'Refined (Offline Mode) ⚡'
              : 'Professionalized by Gemini AI ✨'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isWork) {
          _isRefiningWork = false;
        } else {
          _isRefiningKnowledge = false;
        }
      });
      // We already have the heuristic version in the controller, so we just finish quietly
    }
  }

  Future<void> _submitLog() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please sign in again.')),
      );
      return;
    }

    final db = await LocalDatabase.instance.database;
    final logId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    // Calculate day number based on previous logs
    final lastLog = await db.query(
      'log_entries',
      where: 'student_id = ?',
      whereArgs: [user.id],
      orderBy: 'day_number DESC',
      limit: 1,
    );
    final int nextDayNumber = (lastLog.isNotEmpty ? (lastLog.first['day_number'] as int? ?? 0) : 0) + 1;

    // 1. Save Log Entry
    await db.insert('log_entries', {
      'id': logId,
      'student_id': user.id,
      'day_number': nextDayNumber,
      'date': now,
      'work_description': _workController.text,
      'knowledge_acquired': _knowledgeController.text,
      'status': 'submitted',
      'updated_at': now,
      'is_dirty': 1,
      'is_deleted': 0,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Log saved successfully (Local Cache)'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Invalidate providers for immediate UI update
      // We also invalidate currentUserLogsProvider since it depends on studentLogsProvider
      ref.invalidate(studentLogsProvider(user.id));
      ref.invalidate(currentUserLogsProvider);
      ref.invalidate(internshipProgressProvider);

      // Trigger a sync if possible
      ref.read(syncServiceProvider).syncData();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Log Entry')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _workController,
                  decoration: InputDecoration(
                    labelText: 'Description of Work Done',
                    hintText: 'e.g. I fixed some bugs today...',
                    suffixIcon: _isRefiningWork
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          icon: const Icon(Icons.auto_awesome, color: Colors.indigo),
                          onPressed: () => _refineText(_workController, true),
                          tooltip: 'Professionalize with AI',
                        ),
                  ),
                  minLines: 8,
                  maxLines: null, // Unlimited lines to prevent overflow when content is many!
                  keyboardType: TextInputType.multiline,
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _knowledgeController,
                  decoration: InputDecoration(
                    labelText: 'Knowledge/Experience Acquired',
                    hintText: 'e.g. I learned how to use Flutter...',
                    suffixIcon: _isRefiningKnowledge
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          icon: const Icon(Icons.auto_awesome, color: Colors.indigo),
                          onPressed: () => _refineText(_knowledgeController, false),
                          tooltip: 'Professionalize with AI',
                        ),
                  ),
                  minLines: 5,
                  maxLines: null, // Unlimited lines to prevent overflow when content is many!
                  keyboardType: TextInputType.multiline,
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
              ],
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _submitLog,
              child: const Text('Submit Log'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _workController.dispose();
    _knowledgeController.dispose();
    super.dispose();
  }
}
