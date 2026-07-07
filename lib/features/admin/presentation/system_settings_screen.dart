import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';

class SystemSettingsScreen extends ConsumerStatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  ConsumerState<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends ConsumerState<SystemSettingsScreen> {
  final _logGoalController = TextEditingController(text: '60');
  final _institutionNameController = TextEditingController(text: 'Industrial Attachment University');
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = await LocalDatabase.instance.database;
    final results = await db.query('app_settings');

    for (var row in results) {
      if (row['key'] == 'required_logs') {
        _logGoalController.text = row['value'].toString();
      } else if (row['key'] == 'institution_name') {
        _institutionNameController.text = row['value'].toString();
      }
    }
    setState(() {});
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    // Save Log Goal
    await db.insert('app_settings', {
      'id': 'required_logs_setting',
      'key': 'required_logs',
      'value': _logGoalController.text,
      'updated_at': now,
      'is_dirty': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Save Institution Name
    await db.insert('app_settings', {
      'id': 'institution_name_setting',
      'key': 'institution_name',
      'value': _institutionNameController.text,
      'updated_at': now,
      'is_dirty': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Trigger background sync
    ref.read(syncServiceProvider).syncData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('System settings updated and syncing...')));
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
          const Text('Institution Identity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _institutionNameController,
            decoration: const InputDecoration(
              labelText: 'School / Institution Name',
              helperText: 'This will appear on student PDF reports',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Internship Parameters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _logGoalController,
            decoration: const InputDecoration(
              labelText: 'Required Number of Log Entries',
              helperText: 'Default is 60 (12 weeks * 5 days)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 40),
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
