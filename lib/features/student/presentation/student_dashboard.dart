import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internship_app/features/auth/data/auth_repository.dart';
import 'package:internship_app/core/services/local_database.dart';
import 'package:internship_app/features/student/presentation/pdf_export_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard> {
  bool _isAllocated = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAllocationStatus();
  }

  Future<void> _checkAllocationStatus() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final db = await LocalDatabase.instance.database;
    final results = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);

    if (results.isNotEmpty && results.first['supervisor_id'] != null) {
      setState(() => _isAllocated = true);
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (!_isAllocated) {
      return const SupervisorSelectionScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Logs PDF',
            onPressed: () {
              final user = ref.read(currentUserProvider);
              PdfExportService.generateStudentLogReport(user!.id, user.userMetadata?['full_name'] ?? 'Student');
            },
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              // Navigate to profile to edit or logout
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _createNewLogEntry(),
            icon: const Icon(Icons.add),
            label: const Text('Submit Daily Log'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 20),
          const Text('Recent Logs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          // List of logs would go here
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Internship Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('Days Completed: 12 / 60'),
            LinearProgressIndicator(value: 0.2, backgroundColor: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _createNewLogEntry() {
    // Navigate to Log Entry Form
  }
}

class SupervisorSelectionScreen extends ConsumerStatefulWidget {
  const SupervisorSelectionScreen({super.key});

  @override
  ConsumerState<SupervisorSelectionScreen> createState() => _SupervisorSelectionScreenState();
}

class _SupervisorSelectionScreenState extends ConsumerState<SupervisorSelectionScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _staffList = [];
  bool _isSearching = false;

  Future<void> _searchStaff(String query) async {
    setState(() => _isSearching = true);
    final supabase = sb.Supabase.instance.client;

    // In a real app, we'd search the local 'staff' table or remote 'profiles'
    final results = await supabase
        .from('profiles')
        .select()
        .inFilter('role', ['academic_supervisor', 'industry_supervisor'])
        .ilike('full_name', '%$query%');

    setState(() {
      _staffList = List<Map<String, dynamic>>.from(results);
      _isSearching = false;
    });
  }

  Future<void> _selectSupervisor(Map<String, dynamic> staff) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.update('profiles', {
      'supervisor_id': staff['id'],
      'updated_at': now,
      'is_dirty': 1,
    }, where: 'id = ?', whereArgs: [user.id]);

    // Also update remote Supabase profile
    await sb.Supabase.instance.client
        .from('profiles')
        .update({'supervisor_id': staff['id']})
        .eq('id', user.id);

    // Refresh dashboard
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StudentDashboard()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Onboarding'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Please select your assigned supervisor to unlock your dashboard.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Supervisor by Name',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchStaff(_searchController.text),
                ),
              ),
              onSubmitted: _searchStaff,
            ),
            const SizedBox(height: 20),
            if (_isSearching) const CircularProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _staffList.length,
                itemBuilder: (context, index) {
                  final staff = _staffList[index];
                  return ListTile(
                    title: Text(staff['full_name'] ?? 'No Name'),
                    subtitle: Text(staff['department'] ?? 'No Department'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _selectSupervisor(staff),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
