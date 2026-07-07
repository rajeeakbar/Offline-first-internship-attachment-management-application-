import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';
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
  File? _selectedImage;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _selectedImage = File(pickedFile.path));
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

    // 2. Save Media if selected
    if (_selectedImage != null) {
      await db.insert('media_attachments', {
        'id': const Uuid().v4(),
        'log_id': logId,
        'local_path': _selectedImage!.path,
        'file_type': 'image',
        'updated_at': now,
        'is_dirty': 1,
        'is_deleted': 0,
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log submitted successfully (Offline-first)')),
      );
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
            TextFormField(
              controller: _workController,
              decoration: const InputDecoration(labelText: 'Description of Work Done'),
              maxLines: 5,
              validator: (val) => val!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _knowledgeController,
              decoration: const InputDecoration(labelText: 'Knowledge/Experience Acquired'),
              maxLines: 3,
              validator: (val) => val!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            if (_selectedImage != null)
              Image.file(_selectedImage!, height: 200, fit: BoxFit.cover),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Add Photo Attachment'),
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
}
