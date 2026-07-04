import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';
import '../../auth/data/auth_repository.dart';

class SupervisorDashboard extends ConsumerStatefulWidget {
  final bool isAcademic;
  const SupervisorDashboard({super.key, required this.isAcademic});

  @override
  ConsumerState<SupervisorDashboard> createState() => _SupervisorDashboardState();
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
    final db = await LocalDatabase.instance.database;

    // In a hybrid app, we'd query the local 'profiles' table filtered by supervisor_id
    final results = await db.query('profiles', where: 'supervisor_id = ?', whereArgs: [user!.id]);

    setState(() {
      _assignedStudents = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAcademic ? 'Academic Supervisor' : 'Industry Supervisor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStatsOverview(),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Your Assigned Students', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _assignedStudents.length,
                    itemBuilder: (context, index) {
                      final student = _assignedStudents[index];
                      return ListTile(
                        title: Text(student['full_name'] ?? 'Unknown Student'),
                        subtitle: Text('Logs: 5 Pending Approval'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _viewStudentLogs(student),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsOverview() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('Students', _assignedStudents.length.toString()),
          _statItem('Pending Logs', '12'),
          _statItem('Average Grade', 'B+'),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  void _viewStudentLogs(Map<String, dynamic> student) {
    // Navigate to student detail view
  }
}
