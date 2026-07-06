import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/main_drawer.dart';
import '../../auth/data/auth_repository.dart';

class SupervisorDashboard extends ConsumerStatefulWidget {
  final bool isAcademic;
  const SupervisorDashboard({super.key, required this.isAcademic});

  @override
  ConsumerState<SupervisorDashboard> createState() =>
      _SupervisorDashboardState();
}

class _SupervisorDashboardState extends ConsumerState<SupervisorDashboard> {
  List<Map<String, dynamic>> _assignedStudents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssignedStudents();
  }

  Future<void> _loadAssignedStudents() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final db = await LocalDatabase.instance.database;

    final results = await db
        .query('profiles', where: 'supervisor_id = ?', whereArgs: [user.id]);

    setState(() {
      _assignedStudents = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.isAcademic ? 'Academic Portal' : 'Industry Portal'),
      ),
      drawer: const MainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(syncServiceProvider).syncData();
          await _loadAssignedStudents();
        },
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                    child: _buildStatsOverview(theme),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Your Assigned Students',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                _assignedStudents.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'No students assigned yet.',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final student = _assignedStudents[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        theme.colorScheme.secondaryContainer,
                                    child: Text(
                                      (student['full_name'] as String? ?? 'S')[0]
                                          .toUpperCase(),
                                      style: TextStyle(
                                          color: theme.colorScheme.secondary),
                                    ),
                                  ),
                                  title: Text(
                                    student['full_name'] ?? 'Unknown Student',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: const Text('5 Pending Logs Approval'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _viewStudentLogs(student),
                                ),
                              );
                            },
                            childCount: _assignedStudents.length,
                          ),
                        ),
                      ),
              ],
            ),
      ),
    );
  }

  Widget _buildStatsOverview(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statItem(theme, 'Students', _assignedStudents.length.toString(),
                Icons.people_outline),
            _statItem(theme, 'Pending', '12', Icons.pending_actions_outlined),
            _statItem(theme, 'Avg. Grade', 'B+', Icons.grade_outlined),
          ],
        ),
      ),
    );
  }

  Widget _statItem(ThemeData theme, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _viewStudentLogs(Map<String, dynamic> student) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentLogsReviewScreen(
          student: student,
          isAcademic: widget.isAcademic,
        ),
      ),
    ).then((_) => _loadAssignedStudents());
  }
}

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

  Future<void> _updateLogStatus(String logId, String status, {int? score, String? recommendation}) async {
    final db = await LocalDatabase.instance.database;
    await db.update('log_entries', {
      'status': status,
      'score': score,
      'recommendation': recommendation,
      'is_dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [logId]);
    _loadLogs();

    // Trigger sync in background
    ref.read(syncServiceProvider).syncData();
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
              title: Text('Day ${log['day_number'] ?? index + 1} - ${log['date']?.toString().split('T')[0] ?? "N/A"}'),
              subtitle: Text('Status: ${log['status']}'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Work Description:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(log['work_description'] ?? 'No description provided'),
                      const SizedBox(height: 10),
                      const Text('Knowledge Acquired:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(log['knowledge_acquired'] ?? 'No info provided'),
                      const SizedBox(height: 20),
                      if (log['status'] == 'submitted' || log['status'] == 'pending')
                        Row(
                          children: [
                            if (widget.isAcademic)
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _showReviewDialog(log),
                                  child: const Text('Review & Grade'),
                                ),
                              )
                            else
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _showReviewDialog(log),
                                  child: const Text('Review & Sign Off'),
                                ),
                              ),
                          ],
                        ),
                      if (log['recommendation'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Supervisor Feedback:', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(log['recommendation'], style: const TextStyle(fontStyle: FontStyle.italic)),
                            ],
                          ),
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

  void _showReviewDialog(Map<String, dynamic> log) {
    int score = log['score'] ?? 5;
    final TextEditingController recommendationController = TextEditingController(text: log['recommendation']);
    String status = 'approved';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Review Day ${log['day_number']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isAcademic) ...[
                      const Text('Rate performance (1-10)'),
                      Slider(
                        value: score.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: score.toString(),
                        onChanged: (val) => setDialogState(() => score = val.toInt()),
                      ),
                    ],
                    TextField(
                      controller: recommendationController,
                      decoration: const InputDecoration(
                        labelText: 'Feedback / Recommendation',
                        hintText: 'Enter your comments here...',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Action'),
                      items: const [
                        DropdownMenuItem(value: 'approved', child: Text('Approve / Sign Off')),
                        DropdownMenuItem(value: 'pending', child: Text('Keep Pending')),
                        DropdownMenuItem(value: 'rejected', child: Text('Reject / Requires Revision')),
                      ],
                      onChanged: (val) => setDialogState(() => status = val!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    _updateLogStatus(
                      log['id'],
                      status,
                      score: widget.isAcademic ? score : null,
                      recommendation: recommendationController.text,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Submit Review'),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
