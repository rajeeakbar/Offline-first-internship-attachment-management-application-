import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';
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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
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
    // Navigate to student detail view
  }
}
