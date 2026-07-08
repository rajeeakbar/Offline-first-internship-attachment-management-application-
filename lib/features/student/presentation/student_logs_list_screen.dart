import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';

class StudentLogsListScreen extends ConsumerWidget {
  const StudentLogsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Daily Logs')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _getLogsStream(ref),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final logs = snapshot.data ?? [];
          if (logs.isEmpty) return const Center(child: Text('No logs found.'));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(log['day_number'].toString())),
                  title: Text(log['work_description'] ?? 'No description', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(log['date']?.toString().split('T')[0] ?? ''),
                  trailing: Text(log['status']?.toUpperCase() ?? 'PENDING', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _getLogsStream(WidgetRef ref) async* {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      yield [];
      return;
    }
    final db = await LocalDatabase.instance.database;
    while (true) {
      final results = await db.query('log_entries', where: 'student_id = ?', whereArgs: [user.id], orderBy: 'day_number DESC');
      yield results;
      await Future.delayed(const Duration(seconds: 5));
    }
  }
}
