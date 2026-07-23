import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';
import '../../auth/data/auth_repository.dart';

class AccountManagementScreen extends ConsumerStatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  ConsumerState<AccountManagementScreen> createState() => _AccountManagementScreenState();
}

class _AccountManagementScreenState extends ConsumerState<AccountManagementScreen> {
  final _searchController = TextEditingController();
  String _selectedRoleFilter = 'all';
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    try {
      final db = await LocalDatabase.instance.database;
      final user = ref.read(currentUserProvider);

      // Query profiles that are NOT soft deleted
      final results = await db.query(
        'profiles',
        where: 'is_deleted = ?',
        whereArgs: [0],
      );

      if (mounted) {
        setState(() {
          // Exclude the currently logged-in admin so they can't delete themselves
          _profiles = results
              .where((p) => p['id'] != user?.id)
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load accounts: $e')),
        );
      }
    }
  }

  Future<void> _deleteAccount(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text('Are you sure you want to permanently delete $name\'s account? This action is irreversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = await LocalDatabase.instance.database;
      final now = DateTime.now().toIso8601String();

      // Retrieve user profile to check role and execute cascading deletions
      final userProfiles = await db.query('profiles', where: 'id = ?', whereArgs: [id]);
      if (userProfiles.isNotEmpty) {
        final profile = userProfiles.first;
        final role = profile['role']?.toString();

        if (role == 'student') {
          // Cascade deleted Student: soft delete their log entries and media attachments
          await db.update(
            'log_entries',
            {
              'is_deleted': 1,
              'is_dirty': 1,
              'updated_at': now,
            },
            where: 'student_id = ?',
            whereArgs: [id],
          );

          // Get log ids to cascade delete media
          final logRows = await db.query('log_entries', columns: ['id'], where: 'student_id = ?', whereArgs: [id]);
          final List<String> logIds = logRows.map((row) => row['id'].toString()).toList();
          for (var logId in logIds) {
            await db.update(
              'media_attachments',
              {
                'is_deleted': 1,
                'is_dirty': 1,
                'updated_at': now,
              },
              where: 'log_id = ?',
              whereArgs: [logId],
            );
          }
        } else if (role == 'academic_supervisor') {
          // Cascade deleted Academic Supervisor: detach from all matching student profiles
          await db.update(
            'profiles',
            {
              'supervisor_id': null,
              'is_dirty': 1,
              'updated_at': now,
            },
            where: 'supervisor_id = ?',
            whereArgs: [id],
          );
        } else if (role == 'industry_supervisor') {
          // Cascade deleted Industry Supervisor: detach from all matching student profiles
          await db.update(
            'profiles',
            {
              'industry_supervisor_id': null,
              'is_dirty': 1,
              'updated_at': now,
            },
            where: 'industry_supervisor_id = ?',
            whereArgs: [id],
          );
        }
      }

      // Soft delete locally first, with dirty flag
      await db.update(
        'profiles',
        {
          'is_deleted': 1,
          'is_dirty': 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // Trigger automatic background synchronization which deletes it in Supabase
      ref.read(syncServiceProvider).syncData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted. Synchronizing with cloud...'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Reload accounts
      _loadProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredProfiles() {
    final query = _searchController.text.toLowerCase().trim();

    return _profiles.where((p) {
      final name = (p['full_name'] as String? ?? '').toLowerCase();
      final email = (p['email'] as String? ?? '').toLowerCase();
      final role = p['role'] as String? ?? 'student';

      final matchesSearch = name.contains(query) || email.contains(query);

      if (_selectedRoleFilter == 'all') {
        return matchesSearch;
      } else if (_selectedRoleFilter == 'student') {
        return matchesSearch && role == 'student';
      } else if (_selectedRoleFilter == 'supervisor') {
        return matchesSearch && (role == 'academic_supervisor' || role == 'industry_supervisor');
      } else if (_selectedRoleFilter == 'admin') {
        return matchesSearch && role == 'admin';
      }
      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _getFilteredProfiles();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Manage User Accounts'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search by Name or Email',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _filterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _filterChip('Students', 'student'),
                  const SizedBox(width: 8),
                  _filterChip('Supervisors', 'supervisor'),
                  const SizedBox(width: 8),
                  _filterChip('Admins', 'admin'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text('No accounts found', style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final profile = filtered[index];
                            final role = profile['role'] ?? 'student';
                            final name = profile['full_name'] ?? 'User';
                            final email = profile['email'] ?? '';

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    _getRoleBadge(role, theme),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    if (email.isNotEmpty) ...[
                                      Text(email, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                      const SizedBox(height: 2),
                                    ],
                                    if (role == 'student') ...[
                                      Text(
                                        'ID: ${profile['student_id_number'] ?? 'N/A'} • ${profile['level'] ?? 'N/A'}',
                                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                      ),
                                    ] else if (role == 'academic_supervisor') ...[
                                      Text(
                                        'Department: ${profile['department'] ?? 'N/A'}',
                                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                      ),
                                    ] else if (role == 'industry_supervisor') ...[
                                      Text(
                                        'Company: ${profile['company_name'] ?? 'N/A'}',
                                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  onPressed: () => _deleteAccount(profile['id'], name),
                                  tooltip: 'Delete Account',
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

  Widget _filterChip(String label, String value) {
    final theme = Theme.of(context);
    final isSelected = _selectedRoleFilter == value;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedRoleFilter = value;
          });
        }
      },
      selectedColor: theme.colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? theme.colorScheme.primary : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _getRoleBadge(String role, ThemeData theme) {
    Color color;
    switch (role) {
      case 'student':
        color = Colors.blue;
        break;
      case 'academic_supervisor':
        color = Colors.green;
        break;
      case 'industry_supervisor':
        color = Colors.orange;
        break;
      case 'admin':
        color = Colors.purple;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
