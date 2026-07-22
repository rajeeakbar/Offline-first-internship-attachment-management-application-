import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internship_app/features/auth/data/auth_repository.dart';
import 'package:internship_app/core/services/local_database.dart';
import 'package:internship_app/features/student/presentation/pdf_export_service.dart';
import 'package:internship_app/features/student/presentation/log_entry_form.dart';
import 'package:internship_app/core/services/providers.dart';
import 'package:internship_app/core/services/main_drawer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internship_app/features/student/presentation/student_logs_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:shared_preferences/shared_preferences.dart';

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

    return profileAsync.when(
      data: (profile) {
        if (profile?['industry_supervisor_id'] == null) {
          return const SupervisorSelectionScreen();
        }

        final fullName = profile?['full_name'] ?? 'Student';

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Logbook Dashboard'),
                const SizedBox(width: 8),
                _buildSyncIndicator(),
              ],
            ),
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
                      'OFFLINE MODE - Changes will sync when online',
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
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Starting synchronization...'), duration: Duration(seconds: 1)),
                  );
                  await ref.read(syncServiceProvider).syncData();
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Data is up to date.')),
                    );
                  }
                },
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
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
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
                    const Text(
                      'Internship Progress',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDynamicProgressText(theme, isWhite: true),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_graph_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDynamicProgressBar(theme, isWhite: true),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                final profile = ref.read(userProfileProvider).value;
                if (profile != null) {
                  PdfExportService.generateStudentLogReport(
                    profile['id'],
                    profile['full_name'] ?? 'Student',
                  );
                }
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: const Text('Export Monthly Logbook'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
          separatorBuilder: (_, _) => const SizedBox(height: 12),
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
      error: (_, _) => const SizedBox.shrink(),
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

  Widget _buildDynamicProgressBar(ThemeData theme, {bool isWhite = false}) {
    final progressAsync = ref.watch(internshipProgressProvider);
    return progressAsync.when(
      data: (data) {
        final double progress = (data['count'] as int) / (data['goal'] as int);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 12,
            backgroundColor: isWhite ? Colors.white.withOpacity(0.2) : theme.colorScheme.primary.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(isWhite ? Colors.white : theme.colorScheme.primary),
          ),
        );
      },
      loading: () => const LinearProgressIndicator(minHeight: 12),
      error: (_, _) => const SizedBox(height: 12),
    );
  }

  Widget _buildDynamicProgressText(ThemeData theme, {bool isWhite = false}) {
    final progressAsync = ref.watch(internshipProgressProvider);
    return progressAsync.when(
      data: (data) => Text(
        '${data['count']} of ${data['goal']} days completed',
        style: TextStyle(
          color: isWhite ? Colors.white.withOpacity(0.9) : theme.colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      loading: () => Text('Loading...', style: TextStyle(color: isWhite ? Colors.white70 : Colors.grey)),
      error: (_, _) => const Text('Error loading progress'),
    );
  }

  Widget _buildSyncIndicator() {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        final results = snapshot.data ?? [];
        final isOnline = results.any((r) => r != ConnectivityResult.none);
        return Tooltip(
          message: isOnline ? 'Online - Cloud Sync Active' : 'Offline Mode - Local Storage Only',
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isOnline ? Colors.green : Colors.orange).withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createNewLogEntry() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LogEntryForm()),
    );
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
  final String _activeRole = 'industry_supervisor'; // Only Industry Supervisor is selected by the Student

  Map<String, dynamic>? _selectedAcademic;
  Map<String, dynamic>? _selectedIndustry;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialSelections();
  }

  Future<void> _loadInitialSelections() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final db = await LocalDatabase.instance.database;
      final results = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
      if (results.isNotEmpty) {
        final profile = results.first;
        final acadId = profile['supervisor_id'] as String?;
        final indId = profile['industry_supervisor_id'] as String?;

        if (acadId != null) {
          final acadProfile = await db.query('profiles', where: 'id = ?', whereArgs: [acadId]);
          if (acadProfile.isNotEmpty && mounted) {
            setState(() {
              _selectedAcademic = acadProfile.first;
            });
          }
        }

        if (indId != null) {
          final indProfile = await db.query('profiles', where: 'id = ?', whereArgs: [indId]);
          if (indProfile.isNotEmpty && mounted) {
            setState(() {
              _selectedIndustry = indProfile.first;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading initial selections: $e');
    }

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
          .eq('role', _activeRole)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  void _selectSupervisor(Map<String, dynamic> staff) {
    setState(() {
      _selectedIndustry = staff;
    });
  }

  Future<void> _completeOnboarding() async {
    if (_selectedIndustry == null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      final db = await LocalDatabase.instance.database;
      final now = DateTime.now().toIso8601String();

      // Keep Academic Supervisor as whatever is currently set locally (by Admin)
      final profileResults = await db.query('profiles', where: 'id = ?', whereArgs: [user.id]);
      final String? existingAcademicId = profileResults.isNotEmpty ? profileResults.first['supervisor_id'] as String? : null;

      final industrySupervisorId = _selectedIndustry!['id']?.toString() ?? '';

      // 1. Instantly save to SharedPreferences cache
      final prefs = await SharedPreferences.getInstance();
      if (existingAcademicId != null) {
        await prefs.setString('user_supervisor_id_${user.id}', existingAcademicId);
      }
      await prefs.setString('user_industry_supervisor_id_${user.id}', industrySupervisorId);

      // 2. Instantly update locally in SQLite
      await db.update('profiles', {
        'industry_supervisor_id': industrySupervisorId,
        'updated_at': now,
        'is_dirty': 1,
      }, where: 'id = ?', whereArgs: [user.id]);

      // 3. Trigger remote update in background / non-blocking
      sb.Supabase.instance.client
          .from('profiles')
          .update({
            'industry_supervisor_id': industrySupervisorId,
            'updated_at': now,
          })
          .eq('id', user.id)
          .then((_) {
            debugPrint('Background onboarding update succeeded.');
          })
          .catchError((e) {
            debugPrint('Background onboarding remote update failed (will sync later): $e');
          });

      // 4. Trigger sync and invalidate profile provider instantly
      ref.read(syncServiceProvider).syncData();
      ref.invalidate(userProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Onboarding complete! Loading dashboard...')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 48,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),
                Text(
                  'Assign Your Industry Supervisor',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Select your Industry supervisor below. Your Academic supervisor is assigned by the institution administrator.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  color: Colors.green.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.school, color: Colors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Academic Supervisor Status',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selectedAcademic != null
                                    ? 'Assigned: ${_selectedAcademic!['full_name']}'
                                    : 'Allocation handled directly by Admin',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Your Industry Supervisor:',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.indigo, width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.business_center, color: Colors.indigo),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedIndustry?['full_name'] ?? 'Please search and select below...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _selectedIndustry != null ? Colors.black87 : Colors.grey,
                            ),
                          ),
                        ),
                        if (_selectedIndustry != null)
                          const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search industry supervisor by name...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _searchStaff,
                  onSubmitted: _searchStaff,
                ),
                const SizedBox(height: 12),
                _isSearching
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _staffList.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0),
                            child: Center(
                              child: Text(
                                'No industry supervisors found. Try searching.',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _staffList.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final staff = _staffList[index];
                              final isCurrentlySelected = _selectedIndustry?['id'] == staff['id'];

                              return Card(
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isCurrentlySelected
                                        ? theme.colorScheme.primary
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
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
                                  subtitle: Text(staff['company_name'] ?? staff['department'] ?? 'General Dept'),
                                  trailing: isCurrentlySelected
                                      ? const Icon(Icons.check_circle, color: Colors.green)
                                      : const Icon(Icons.add_circle_outline,
                                          color: Colors.indigo),
                                  onTap: () => _selectSupervisor(staff),
                                ),
                              );
                            },
                          ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (_selectedIndustry == null || _isSaving)
                      ? null
                      : _completeOnboarding,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Complete Onboarding',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
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
