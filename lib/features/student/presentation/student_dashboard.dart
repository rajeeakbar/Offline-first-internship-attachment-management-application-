import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internship_app/features/auth/data/auth_repository.dart';
import 'package:internship_app/core/services/local_database.dart';
import 'package:internship_app/features/student/presentation/pdf_export_service.dart';
import 'package:internship_app/features/student/presentation/log_entry_form.dart';
import 'package:internship_app/core/services/providers.dart';
import 'package:internship_app/core/services/main_drawer.dart';
import 'package:internship_app/features/student/presentation/student_logs_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(userProfileProvider);

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
    final results =
        await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);

    if (results.isNotEmpty && results.first['supervisor_id'] != null) {
      setState(() => _isAllocated = true);
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final fullName = user?.userMetadata?['full_name'] ?? 'Student';

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }


    return profileAsync.when(
      data: (profile) {
        if (profile?['supervisor_id'] == null) {
          return const SupervisorSelectionScreen();
        }


        final fullName = profile?['full_name'] ?? 'Student';

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: const Text('Logbook Dashboard'),
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
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, $fullName!',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Keep track of your internship progress.',
                              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          fullName[0].toUpperCase(),
                          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSummaryCard(theme),
                  const SizedBox(height: 24),
                  _buildStatsRow(theme),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your Recent Logs',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const StudentLogsListScreen()),
                          );
                        },
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildLogsList(theme),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _createNewLogEntry,
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('New Daily Log'),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Logbook Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hello, $fullName!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Keep track of your internship progress.',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _buildSummaryCard(theme),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activities',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildEmptyLogsPlaceholder(theme),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNewLogEntry(),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Daily Log'),
      ),

    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Internship Progress',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),

                    _buildDynamicProgressText(theme),

                    Text(
                      '12 of 60 days completed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildDynamicProgressBar(theme),

            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: 0.2,
                minHeight: 10,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),

            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                final user = ref.read(currentUserProvider);
                PdfExportService.generateStudentLogReport(
                  user!.id,
                  user.userMetadata?['full_name'] ?? 'Student',
                );
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Generate PDF Report'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildLogsList(ThemeData theme) {
    final logsAsync = ref.watch(currentUserLogsProvider);

    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 64,
                  color: theme.colorScheme.onSurface.withOpacity(0.1),
                ),
                const SizedBox(height: 16),
                Text(
                  'No logs submitted yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: logs.length > 5 ? 5 : logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final log = logs[index];
            return Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.withOpacity(0.1)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${log['day_number']}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                title: Text(
                  log['work_description'] ?? 'No description',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    log['date']?.toString().split('T')[0] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                trailing: _getStatusChip(log['status'] ?? 'pending', theme),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildStatsRow(ThemeData theme) {
    final logsAsync = ref.watch(currentUserLogsProvider);

    return logsAsync.when(
      data: (logs) {
        final approved = logs.where((l) => l['status'] == 'approved').length;
        final pending = logs.where((l) => l['status'] == 'submitted' || l['status'] == 'pending').length;
        final rejected = logs.where((l) => l['status'] == 'rejected').length;

        return Row(
          children: [
            _statBox(theme, 'Approved', approved.toString(), Colors.green),
            const SizedBox(width: 12),
            _statBox(theme, 'Pending', pending.toString(), Colors.orange),
            const SizedBox(width: 12),
            _statBox(theme, 'Rejected', rejected.toString(), Colors.red),

          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _statBox(ThemeData theme, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getStatusChip(String status, ThemeData theme) {
    Color color;
    switch (status) {
      case 'approved':
        color = Colors.green;
        break;
      case 'submitted':
        color = Colors.orange;
        break;
      case 'rejected':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDynamicProgressBar(ThemeData theme) {
    final progressAsync = ref.watch(internshipProgressProvider);
    return progressAsync.when(
      data: (data) {
        final double progress = (data['count'] as int) / (data['goal'] as int);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
          ),
        );
      },
      loading: () => const LinearProgressIndicator(minHeight: 10),
      error: (_, __) => const SizedBox(height: 10),
    );
  }

  Widget _buildDynamicProgressText(ThemeData theme) {
    final progressAsync = ref.watch(internshipProgressProvider);
    return progressAsync.when(
      data: (data) => Text(
        '${data['count']} of ${data['goal']} days completed',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      loading: () => const Text('Loading...'),
      error: (_, __) => const Text('Error loading progress'),
    );
  }


  Future<void> _createNewLogEntry() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LogEntryForm()),
    );

  Widget _buildEmptyLogsPlaceholder(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'No logs submitted yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
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
  ConsumerState<SupervisorSelectionScreen> createState() =>
      _SupervisorSelectionScreenState();
}

class _SupervisorSelectionScreenState
    extends ConsumerState<SupervisorSelectionScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _staffList = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadInitialStaff();
  }

  Future<void> _loadInitialStaff() async {
    _searchStaff('');
  }

  Future<void> _searchStaff(String query) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _staffList = [];
    });
    final supabase = sb.Supabase.instance.client;

    try {
      final queryBuilder = supabase.from('profiles').select();

      final results = await queryBuilder
          .or('role.eq.academic_supervisor,role.eq.industry_supervisor')
          .ilike('full_name', '%$query%')
          .order('full_name');

      if (mounted) {
        setState(() {
          _staffList = List<Map<String, dynamic>>.from(results);
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);

    try {
      final results = await supabase
          .from('profiles')
          .select()
          .inFilter('role', ['academic_supervisor', 'industry_supervisor'])
          .ilike('full_name', '%$query%');

      setState(() {
        _staffList = List<Map<String, dynamic>>.from(results);
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  Future<void> _selectSupervisor(Map<String, dynamic> staff) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;


    final isIndustry = staff['role'] == 'industry_supervisor';


    setState(() => _isSearching = true);
    try {
      final db = await LocalDatabase.instance.database;
      final now = DateTime.now().toIso8601String();

      await db.update('profiles', {

        isIndustry ? 'industry_supervisor_id' : 'supervisor_id': staff['id'],

        'supervisor_id': staff['id'],

        'updated_at': now,
        'is_dirty': 1,
      }, where: 'id = ?', whereArgs: [user.id]);

      await sb.Supabase.instance.client
          .from('profiles')

          .update({
            isIndustry ? 'industry_supervisor_id' : 'supervisor_id': staff['id'],
            'updated_at': now,
          })
          .eq('id', user.id);

      ref.read(syncServiceProvider).syncData();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StudentDashboard()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);

          .update({'supervisor_id': staff['id']})
          .eq('id', user.id);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StudentDashboard()),
        );
      }
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selection failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Complete Onboarding'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 64,
              color: Colors.indigo,
            ),
            const SizedBox(height: 24),
            Text(
              'One last step!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please select your assigned supervisor to unlock your student dashboard.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search supervisor by name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _searchStaff(_searchController.text),
                ),
              ),
              onSubmitted: _searchStaff,
            ),
            const SizedBox(height: 24),
            if (_isSearching)
              const Center(child: CircularProgressIndicator())
            else
              Expanded(
                child: _staffList.isEmpty
                    ? Center(
                        child: Text(
                          'No supervisors found. Try searching.',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _staffList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final staff = _staffList[index];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Text(
                                  (staff['full_name'] as String? ?? 'U')[0]
                                      .toUpperCase(),
                                  style: TextStyle(color: theme.colorScheme.primary),
                                ),
                              ),
                              title: Text(
                                staff['full_name'] ?? 'Anonymous Staff',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(staff['department'] ?? 'General Dept'),
                              trailing: const Icon(Icons.add_circle_outline,
                                  color: Colors.indigo),
                              onTap: () => _selectSupervisor(staff),
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
