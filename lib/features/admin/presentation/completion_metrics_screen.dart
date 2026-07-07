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

    // Get required logs goal from settings
    final settingsResult = await db.query('app_settings', where: 'key = ?', whereArgs: ['required_logs']);
    final int logGoal = settingsResult.isNotEmpty ? (int.tryParse(settingsResult.first['value'].toString()) ?? 60) : 60;

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

      final int approved = approvedCountResult.first['approved'] as int? ?? 0;

      stats.add({
        'name': student['full_name'] ?? 'Unknown',
        'total_logs': logCountResult.first['total'] ?? 0,
        'approved_logs': approved,
        'goal': logGoal,
        'percentage': logGoal > 0
            ? (approved / logGoal * 100).toStringAsFixed(1)
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
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: ListTile(
                          title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Logs: ${item['total_logs']} total, ${item['approved_logs']} approved'),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: (int.tryParse(item['goal'].toString()) ?? 1) > 0
                                  ? (item['approved_logs'] / item['goal'])
                                  : 0,
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
                              ),
                            ],
                          ),
                          trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${item['percentage']}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                            Text('Goal: ${item['goal']}', style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                      ),
                    );
                  },
                ),
    );
  }
}
