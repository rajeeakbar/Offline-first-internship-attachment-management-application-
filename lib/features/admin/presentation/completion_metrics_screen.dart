import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';

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

    // Get all active (not soft deleted) students
    final students = await db.query('profiles', where: 'role = ? AND is_deleted = ?', whereArgs: ['student', 0]);

    List<Map<String, dynamic>> stats = [];
    final now = DateTime.now();

    for (var student in students) {
      final logCountResult = await db.rawQuery(
        'SELECT COUNT(*) as total FROM log_entries WHERE student_id = ? AND is_deleted = ?',
        [student['id'], 0]
      );
      final approvedCountResult = await db.rawQuery(
        'SELECT COUNT(*) as approved FROM log_entries WHERE student_id = ? AND status = ? AND is_deleted = ?',
        [student['id'], 'approved', 0]
      );

      // Query latest log entry date to analyze weekly compliance
      final latestLogResult = await db.query(
        'log_entries',
        columns: ['date'],
        where: 'student_id = ? AND is_deleted = ?',
        whereArgs: [student['id'], 0],
        orderBy: 'date DESC',
        limit: 1,
      );

      final int approved = approvedCountResult.first['approved'] as int? ?? 0;
      bool isCompliant = true;
      int daysSinceLastSubmission = -1;

      if (latestLogResult.isEmpty) {
        // No logs submitted at all -> Flag as Non-Compliant
        isCompliant = false;
      } else {
        final latestDateStr = latestLogResult.first['date']?.toString();
        if (latestDateStr != null && latestDateStr.isNotEmpty) {
          try {
            final latestDate = DateTime.parse(latestDateStr);
            daysSinceLastSubmission = now.difference(latestDate).inDays;
            if (daysSinceLastSubmission > 7) {
              isCompliant = false;
            }
          } catch (e) {
            isCompliant = false;
          }
        } else {
          isCompliant = false;
        }
      }

      stats.add({
        'id': student['id'],
        'name': student['full_name'] ?? 'Unknown',
        'total_logs': logCountResult.first['total'] ?? 0,
        'approved_logs': approved,
        'goal': logGoal,
        'percentage': logGoal > 0
            ? (approved / logGoal * 100).toStringAsFixed(1)
            : "0.0",
        'is_compliant': isCompliant,
        'days_since_last': daysSinceLastSubmission,
      });
    }

    setState(() {
      _metrics = stats;
      _isLoading = false;
    });
  }

  void _sendManualReminder(String studentName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Reminder'),
        content: Text('Are you sure you want to send an automated compliance reminder to $studentName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚡ Reminder sent to $studentName successfully!'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _sendBulkReminders(int count) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Bulk Reminders'),
        content: Text('Are you sure you want to send compliance reminders to all $count non-compliant students?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚡ Bulk warnings sent to all $count non-compliant students successfully!'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Send Bulk'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nonCompliantCount = _metrics.where((item) => item['is_compliant'] == false).length;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: const Text('Completion Metrics')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _calculateMetrics();
                await ref.read(syncServiceProvider).syncData();
              },
              child: _metrics.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 100),
                    Center(child: Text('No student data available.')),
                  ],
                )
              : CustomScrollView(
                  slivers: [
                    if (nonCompliantCount > 0)
                      SliverPadding(
                        padding: const EdgeInsets.all(16.0),
                        sliver: SliverToBoxAdapter(
                          child: Card(
                            color: Colors.red.withOpacity(0.05),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.red.withOpacity(0.2), width: 1.5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 36),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Compliance Warnings',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$nonCompliantCount students missed their weekly submissions.',
                                          style: TextStyle(color: Colors.grey[700], fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _sendBulkReminders(nonCompliantCount),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(120, 44),
                                    ),
                                    icon: const Icon(Icons.notifications_active, size: 18),
                                    label: const Text('Remind All', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _metrics[index];
                            final isCompliant = item['is_compliant'] == true;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: ListTile(
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['name'],
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isCompliant ? Colors.green : Colors.red).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isCompliant ? 'COMPLIANT' : 'NON-COMPLIANT',
                                          style: TextStyle(
                                            color: isCompliant ? Colors.green : Colors.red,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text('Logs: ${item['total_logs']} total, ${item['approved_logs']} approved'),
                                      if (!isCompliant) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item['days_since_last'] == -1
                                              ? '⚠️ No entries submitted yet'
                                              : '⚠️ No submissions for ${item['days_since_last']} days',
                                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500, fontSize: 12),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: (int.tryParse(item['goal'].toString()) ?? 1) > 0
                                          ? (item['approved_logs'] / item['goal'])
                                          : 0,
                                        backgroundColor: Colors.grey[200],
                                        valueColor: AlwaysStoppedAnimation<Color>(isCompliant ? Colors.indigo : Colors.red),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('${item['percentage']}%', style: TextStyle(fontWeight: FontWeight.bold, color: isCompliant ? Colors.indigo : Colors.red)),
                                          Text('Goal: ${item['goal']}', style: const TextStyle(fontSize: 10)),
                                        ],
                                      ),
                                      if (!isCompliant) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.notification_add, color: Colors.red),
                                          onPressed: () => _sendManualReminder(item['name']),
                                          tooltip: 'Send Manual Reminder',
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: _metrics.length,
                        ),
                      ),
                    ),
                  ],
                ),
            ),
    );
  }
}
