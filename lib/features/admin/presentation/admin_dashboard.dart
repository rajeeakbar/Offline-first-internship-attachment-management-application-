import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/main_drawer.dart';
import 'student_allocation_screen.dart';
import 'company_management_screen.dart';
import 'completion_metrics_screen.dart';
import 'system_settings_screen.dart';
import 'account_management_screen.dart';

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
    final students =
        await db.query('profiles', where: 'role = ?', whereArgs: ['student']);
    final supervisors = await db.query('profiles',
        where: 'role IN (?, ?)',
        whereArgs: ['academic_supervisor', 'industry_supervisor']);

    if (mounted) {
      setState(() {
        _studentCount = students.length;
        _supervisorCount = supervisors.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Institution Admin'),
      ),
      drawer: const MainDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(syncServiceProvider).syncData();
          await _loadStats();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'System Overview',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSummaryCards(theme),
            const SizedBox(height: 32),
            Text(
              'Management Tools',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildMenuTile(theme, Icons.business_rounded, 'Company Profiles',
                'Manage participating companies', onTap: () {
                   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompanyManagementScreen()));
                }),
            _buildMenuTile(theme, Icons.manage_accounts_rounded, 'Manage Accounts',
                'View and delete user accounts', onTap: () {
                   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountManagementScreen()));
                }),
            _buildMenuTile(theme, Icons.people_alt_rounded, 'Student Allocations',
                'Match students to supervisors', onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudentAllocationScreen()));
                }),
            _buildMenuTile(theme, Icons.analytics_outlined, 'Completion Metrics',
                'View institution-wide progress', onTap: () {
                   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompletionMetricsScreen()));
                }),
            _buildMenuTile(theme, Icons.settings_suggest_rounded,
                'System Settings', 'Configure attachment parameters', onTap: () {
                   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SystemSettingsScreen()));
                }),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            theme,
            'Students',
            _studentCount.toString(),
            Colors.blue,
            Icons.school_outlined,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _statCard(
            theme,
            'Staff',
            _supervisorCount.toString(),
            Colors.green,
            Icons.badge_outlined,
          ),
        ),
      ],
    );
  }

  Widget _statCard(ThemeData theme, String title, String value, Color color,
      IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(
      ThemeData theme, IconData icon, String title, String subtitle, {VoidCallback? onTap, String? badge}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        title: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: onTap,
      ),
    );
  }
}
