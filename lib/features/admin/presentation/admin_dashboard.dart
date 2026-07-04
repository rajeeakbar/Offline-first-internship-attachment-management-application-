import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/services/local_database.dart';

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});

  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  int _studentCount = 0;
  int _supervisorCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = await LocalDatabase.instance.database;
    final students = await db.query('profiles', where: 'role = ?', whereArgs: ['student']);
    final supervisors = await db.query('profiles', where: 'role IN (?, ?)', whereArgs: ['academic_supervisor', 'industry_supervisor']);

    setState(() {
      _studentCount = students.length;
      _supervisorCount = supervisors.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Institution Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 20),
          _buildMenuTile(Icons.business, 'Company Profiles', 'Manage participating companies'),
          _buildMenuTile(Icons.people, 'Student Allocations', 'Match students to supervisors'),
          _buildMenuTile(Icons.bar_chart, 'Completion Metrics', 'View institution-wide progress'),
          _buildMenuTile(Icons.settings, 'System Settings', 'Configure attachment parameters'),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(child: _statCard('Active Students', _studentCount.toString(), Colors.blue)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Staff Members', _supervisorCount.toString(), Colors.green)),
      ],
    );
  }

  Widget _statCard(String title, String value, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, String subtitle) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {},
      ),
    );
  }
}
