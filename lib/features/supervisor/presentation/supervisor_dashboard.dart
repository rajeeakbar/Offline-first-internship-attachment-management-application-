import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final studentsAsync = ref.watch(supervisorStudentsProvider(widget.isAcademic));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.isAcademic ? 'Academic Portal' : 'Industry Portal'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: StreamBuilder<List<ConnectivityResult>>(
            stream: Connectivity().onConnectivityChanged,
            builder: (context, snapshot) {
              final results = snapshot.data ?? [];
              final isOnline = results.any((r) => r != ConnectivityResult.none);
              if (isOnline) return const SizedBox.shrink();
              return Container(
                color: Colors.orange.withOpacity(0.9),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Text(
                  'OFFLINE MODE',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => ref.read(syncServiceProvider).syncData(),
          ),
        ],
      ),
      drawer: const MainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(syncServiceProvider).syncData();
        },
        child: studentsAsync.when(
          data: (students) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(
                  child: _buildStatsOverview(theme, students.length),
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
              students.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 40),
                            Text(
                              'No students assigned yet.',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.isAcademic
                                  ? 'Your assigned students are allocated by the administrator.'
                                  : 'Students must select you as their Industry supervisor to be added to your list.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final student = students[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.withOpacity(0.1)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  radius: 25,
                                  backgroundColor: theme.colorScheme.secondaryContainer,
                                  child: Text(
                                    (student['full_name'] as String? ?? 'S')[0].toUpperCase(),
                                    style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(
                                  student['full_name'] ?? 'Unknown Student',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: FutureBuilder<int>(
                                  future: _getStudentPendingCount(student['id']),
                                  builder: (context, snapshot) => Text(
                                    '${snapshot.data ?? 0} Pending Logs Approval',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 20),
                                      onPressed: () => _confirmUnassignStudent(student),
                                      tooltip: 'Unassign Student',
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => _viewStudentLogs(student),
                              ),
                            );
                          },
                          childCount: students.length,
                        ),
                      ),
                    ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _buildStatsOverview(ThemeData theme, int studentCount) {
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
            _statItem(theme, 'Students', studentCount.toString(), Icons.people_outline),
            FutureBuilder<int>(
              future: _getPendingCount(),
              builder: (context, snapshot) => _statItem(theme, 'Pending', (snapshot.data ?? 0).toString(), Icons.pending_actions_outlined),
            ),
            _statItem(theme, 'Role', widget.isAcademic ? 'ACAD' : 'IND', Icons.badge_outlined),
          ],
        ),
      ),
    );
  }

  Future<int> _getStudentPendingCount(String studentId) async {
    final db = await LocalDatabase.instance.database;
    final results = await db.rawQuery(
      'SELECT COUNT(*) as total FROM log_entries WHERE student_id = ? AND status = ?',
      [studentId, 'submitted']
    );
    return results.first['total'] as int? ?? 0;
  }

  Future<int> _getPendingCount() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return 0;
    final db = await LocalDatabase.instance.database;
    final results = await db.rawQuery(
      'SELECT COUNT(*) as total FROM log_entries WHERE supervisor_id = ? AND status = ?',
      [user.id, 'submitted']
    );
    return results.first['total'] as int? ?? 0;
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

  void _confirmUnassignStudent(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unassign Student?'),
        content: Text('Are you sure you want to remove ${student['full_name']} from your list? They will need to select a new supervisor.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _unassignStudent(student['id']);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove Student'),
          ),
        ],
      ),
    );
  }

  Future<void> _unassignStudent(String studentId) async {
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    // Update local first (Offline-First)
    await db.update('profiles', {
      widget.isAcademic ? 'supervisor_id' : 'industry_supervisor_id': null,
      'updated_at': now,
      'is_dirty': 1,
    }, where: 'id = ?', whereArgs: [studentId]);

    // Trigger non-blocking remote write to background
    sb.Supabase.instance.client
        .from('profiles')
        .update({
          widget.isAcademic ? 'supervisor_id' : 'industry_supervisor_id': null,
          'updated_at': now,
        })
        .eq('id', studentId)
        .then((_) => debugPrint('Background remote unassignment completed.'))
        .catchError((e) => debugPrint('Background remote unassignment failed (will sync later): $e'));

    // Soft sync and invalidate
    ref.read(syncServiceProvider).syncData();
    ref.invalidate(supervisorStudentsProvider(widget.isAcademic));
  }

  void _viewStudentLogs(Map<String, dynamic> student) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentLogsReviewScreen(
          student: student,
          isAcademic: widget.isAcademic,
        ),
      ),
    );
  }
}

class BrowseStudentsScreen extends ConsumerStatefulWidget {
  final bool isAcademic;
  const BrowseStudentsScreen({super.key, required this.isAcademic});

  @override
  ConsumerState<BrowseStudentsScreen> createState() => _BrowseStudentsScreenState();
}

class _BrowseStudentsScreenState extends ConsumerState<BrowseStudentsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _allStudents = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStudents('');
  }

  Future<void> _loadStudents(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final db = await LocalDatabase.instance.database;

      // Query local database for all students
      final results = await db.query(
        'profiles',
        where: 'role = ? AND full_name LIKE ?',
        whereArgs: ['student', '%$query%'],
        orderBy: 'full_name',
      );

      if (mounted) {
        setState(() {
          _allStudents = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load students: $e')),
        );
      }
    }
  }

  Future<void> _toggleAssignment(Map<String, dynamic> student, bool assign) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final updateField = widget.isAcademic ? 'supervisor_id' : 'industry_supervisor_id';

    setState(() => _isLoading = true);

    try {
      final updateData = {
        updateField: assign ? currentUser.id : null,
        'updated_at': now,
        'is_dirty': 1,
      };

      // 1. Update local DB (Instant)
      await db.update('profiles', updateData, where: 'id = ?', whereArgs: [student['id']]);

      // 2. Update remote DB in background / non-blocking
      sb.Supabase.instance.client
          .from('profiles')
          .update({
            updateField: assign ? currentUser.id : null,
            'updated_at': now,
          })
          .eq('id', student['id'])
          .then((_) => debugPrint('Background student assignment toggle succeeded.'))
          .catchError((e) => debugPrint('Background student assignment toggle failed: $e'));

      // 3. Trigger sync and invalidate profile to update state
      ref.read(syncServiceProvider).syncData();
      ref.invalidate(supervisorStudentsProvider(widget.isAcademic));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              assign
                  ? 'Assigned ${student['full_name']} to your roster'
                  : 'Removed ${student['full_name']} from your roster',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assignment failed: $e')),
        );
      }
    } finally {
      _loadStudents(_searchController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse & Assign Students'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search students by name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _loadStudents(_searchController.text),
                ),
              ),
              onSubmitted: _loadStudents,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _allStudents.isEmpty
                      ? Center(
                          child: Text(
                            'No students found.',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _allStudents.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final student = _allStudents[index];
                            final acadSuperId = student['supervisor_id'];
                            final indSuperId = student['industry_supervisor_id'];

                            final isAssignedToMe = widget.isAcademic
                                ? acadSuperId == currentUser?.id
                                : indSuperId == currentUser?.id;

                            String statusText = 'Unassigned';
                            if (widget.isAcademic) {
                              if (acadSuperId != null) {
                                statusText = isAssignedToMe ? 'Assigned to You' : 'Assigned to Other Academic';
                              }
                            } else {
                              if (indSuperId != null) {
                                statusText = isAssignedToMe ? 'Assigned to You' : 'Assigned to Other Industry';
                              }
                            }

                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  child: Text(
                                    (student['full_name'] as String? ?? 'S')[0].toUpperCase(),
                                    style: TextStyle(color: theme.colorScheme.primary),
                                  ),
                                ),
                                title: Text(
                                  student['full_name'] ?? 'Unknown Student',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Dept: ${student['department'] ?? "N/A"}'),
                                    const SizedBox(height: 4),
                                    Text(
                                      statusText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isAssignedToMe
                                            ? Colors.green
                                            : (statusText == 'Unassigned' ? Colors.grey : Colors.orange),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: isAssignedToMe
                                    ? ElevatedButton.icon(
                                        onPressed: () => _toggleAssignment(student, false),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.withOpacity(0.1),
                                          foregroundColor: Colors.red,
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.remove_circle_outline, size: 16),
                                        label: const Text('Remove'),
                                      )
                                    : ElevatedButton.icon(
                                        onPressed: () => _toggleAssignment(student, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme.colorScheme.primaryContainer,
                                          foregroundColor: theme.colorScheme.primary,
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.add_circle_outline, size: 16),
                                        label: const Text('Assign'),
                                      ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final now = DateTime.now().toIso8601String();

    await db.update('log_entries', {
      'status': status,
      'score': score,
      'recommendation': recommendation,
      'is_dirty': 1,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [logId]);

    // Also update profiles for the student to trigger sync if needed
    await db.update('profiles', {
      'updated_at': now,
      'is_dirty': 1,
    }, where: 'id = ?', whereArgs: [widget.student['id']]);

    await _loadLogs();

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
                                  child: const Text('Review & Decide'),
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
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Action'),
                      items: const [
                        DropdownMenuItem(value: 'approved', child: Text('Approve Pending')),
                        DropdownMenuItem(value: 'pending', child: Text('Keep Pending')),
                        DropdownMenuItem(value: 'rejected', child: Text('Reject')),
                      ],
                      onChanged: (val) => setDialogState(() => status = val!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    await _updateLogStatus(
                      log['id'],
                      status,
                      score: widget.isAcademic ? score : null,
                      recommendation: recommendationController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
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
