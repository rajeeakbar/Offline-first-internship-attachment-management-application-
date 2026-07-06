import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';

class CompletionMetricsScreen extends ConsumerStatefulWidget {
  const CompletionMetricsScreen({super.key});

  @override
  ConsumerState<CompletionMetricsScreen> createState() => _CompletionMetricsScreenState();
}

class _CompletionMetricsScreenState extends ConsumerState<CompletionMetricsScreen> {
  List<Map<String, dynamic>> _metrics = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateMetrics();
  }

  Future<void> _calculateMetrics() async {
    final db = await LocalDatabase.instance.database;

    // Get all students
    final students = await db.query('profiles', where: 'role = ?', whereArgs: ['student']);

    List<Map<String, dynamic>> stats = [];

    for (var student in students) {
      final logCountResult = await db.rawQuery(
        'SELECT COUNT(*) as total FROM log_entries WHERE student_id = ?',
        [student['id']]
      );
      final approvedCountResult = await db.rawQuery(
        'SELECT COUNT(*) as approved FROM log_entries WHERE student_id = ? AND status = ?',
        [student['id'], 'approved']
      );

      stats.add({
        'name': student['full_name'] ?? 'Unknown',
        'total_logs': logCountResult.first['total'] ?? 0,
        'approved_logs': approvedCountResult.first['approved'] ?? 0,
        'percentage': (logCountResult.first['total'] as int) > 0
            ? ((approvedCountResult.first['approved'] as int) / 60 * 100).toStringAsFixed(1)
            : "0.0",
      });
    }

    setState(() {
      _metrics = stats;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completion Metrics')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _metrics.isEmpty
              ? const Center(child: Text('No student data available.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _metrics.length,
                  itemBuilder: (context, index) {
                    final item = _metrics[index];
                    return Card(
                      child: ListTile(
                        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Logs: ${item['total_logs']} total, ${item['approved_logs']} approved'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${item['percentage']}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                            const Text('Goal: 60', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
