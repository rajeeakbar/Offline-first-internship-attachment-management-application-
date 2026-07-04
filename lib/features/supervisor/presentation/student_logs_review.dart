import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';

class StudentLogsReviewScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;
  final bool isAcademic;
  const StudentLogsReviewScreen({super.key, required this.student, required this.isAcademic});

  @override
  ConsumerState<StudentLogsReviewScreen> createState() => _StudentLogsReviewScreenState();
}

class _StudentLogsReviewScreenState extends ConsumerState<StudentLogsReviewScreen> {
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final db = await LocalDatabase.instance.database;
    final results = await db.query('log_entries', where: 'student_id = ?', whereArgs: [widget.student['id']]);
    setState(() => _logs = results);
  }

  Future<void> _approveLog(String logId, {int? score}) async {
    final db = await LocalDatabase.instance.database;
    await db.update('log_entries', {
      'status': 'approved',
      'score': score,
      'is_dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [logId]);
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Logs: ${widget.student['full_name']}')),
      body: ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (context, index) {
          final log = _logs[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ExpansionTile(
              title: Text('Day ${log['day_number'] ?? index + 1} - ${log['date'].toString().split('T')[0]}'),
              subtitle: Text('Status: ${log['status']}'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Work Description:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(log['work_description']),
                      const SizedBox(height: 10),
                      const Text('Knowledge Acquired:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(log['knowledge_acquired']),
                      const SizedBox(height: 20),
                      if (log['status'] == 'submitted')
                        Row(
                          children: [
                            if (widget.isAcademic)
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _showGradingDialog(log['id']),
                                  child: const Text('Grade Assessment'),
                                ),
                              )
                            else
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _approveLog(log['id']),
                                  child: const Text('Sign Off (Approve)'),
                                ),
                              ),
                            const SizedBox(width: 10),
                            TextButton(onPressed: () {}, child: const Text('Reject')),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showGradingDialog(String logId) {
    showDialog(
      context: context,
      builder: (context) {
        int score = 5;
        return AlertDialog(
          title: const Text('Grade Log Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Rate performance (1-10)'),
              Slider(
                value: score.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: score.toString(),
                onChanged: (val) => score = val.toInt(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                _approveLog(logId, score: score);
                Navigator.pop(context);
              },
              child: const Text('Submit Grade'),
            ),
          ],
        );
      },
    );
  }
}
