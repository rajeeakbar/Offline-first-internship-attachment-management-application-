import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database.dart';

class SystemSettingsScreen extends ConsumerStatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  ConsumerState<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends ConsumerState<SystemSettingsScreen> {
  final _logGoalController = TextEditingController(text: '60');
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = await LocalDatabase.instance.database;
    final results = await db.query('app_settings', where: 'key = ?', whereArgs: ['required_logs']);
    if (results.isNotEmpty) {
      setState(() {
        _logGoalController.text = results.first['value'].toString();
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.insert('app_settings', {
      'id': 'required_logs_setting',
      'key': 'required_logs',
      'value': _logGoalController.text,
      'updated_at': now,
      'is_dirty': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved locally.')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Internship Parameters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          TextField(
            controller: _logGoalController,
            decoration: const InputDecoration(
              labelText: 'Required Number of Log Entries',
              helperText: 'Default is 60 (12 weeks * 5 days)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 32),
          _isSaving
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Save Configuration'),
                ),
        ],
      ),
    );
  }
}
