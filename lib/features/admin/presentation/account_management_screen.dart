import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';

class AccountManagementScreen extends ConsumerStatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  ConsumerState<AccountManagementScreen> createState() => _AccountManagementScreenState();
}

class _AccountManagementScreenState extends ConsumerState<AccountManagementScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = false;
  String _selectedRoleFilter = 'all'; // 'all', 'student', 'supervisor'

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts([String query = '']) async {
    setState(() => _isLoading = true);

    try {
      final db = await LocalDatabase.instance.database;

      String whereClause = 'is_deleted = 0';
      List<dynamic> whereArgs = [];

      if (query.trim().isNotEmpty) {
        whereClause += ' AND full_name LIKE ?';
        whereArgs.add('%${query.trim()}%');
      }

      if (_selectedRoleFilter == 'student') {
        whereClause += ' AND role = ?';
        whereArgs.add('student');
      } else if (_selectedRoleFilter == 'supervisor') {
        whereClause += ' AND role IN (?, ?)';
        whereArgs.addAll(['academic_supervisor', 'industry_supervisor']);
      } else {
        // Exclude admins from deletion/management to prevent locking themselves out
        whereClause += ' AND role != ?';
        whereArgs.add('admin');
      }

      final results = await db.query(
        'profiles',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'full_name ASC',
      );

      if (mounted) {
        setState(() {
          _accounts = results;
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

  Future<void> _deleteAccount(String id, String fullName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text('Delete Account?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the account for "$fullName"? '
          'This action will mark the account for deletion and sync immediately with the cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final db = await LocalDatabase.instance.database;
      final now = DateTime.now().toIso8601String();

      // Offline-First: set is_deleted = 1 and is_dirty = 1 locally
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

      // Instantly hide from the local UI
      setState(() {
        _accounts.removeWhere((account) => account['id'] == id);
      });

      // Trigger background synchronization pipeline
      ref.read(syncServiceProvider).syncData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account for "$fullName" marked for deletion (syncing...)'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e'), backgroundColor: Colors.redAccent),
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
        title: const Text('Account Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            onPressed: () {
              ref.read(syncServiceProvider).syncData();
              _loadAccounts(_searchController.text);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search accounts by name...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    _loadAccounts();
                  },
                ),
              ),
              onChanged: (val) => _loadAccounts(val),
            ),
            const SizedBox(height: 12),

            // Filters
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _filterChip('All', 'all'),
                _filterChip('Students', 'student'),
                _filterChip('Supervisors', 'supervisor'),
              ],
            ),
            const SizedBox(height: 16),

            // Account list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _accounts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No matching accounts found',
                                style: TextStyle(color: Colors.grey[500], fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _accounts.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final account = _accounts[index];
                            final String role = account['role']?.toString() ?? 'student';
                            final String name = account['full_name']?.toString() ?? 'Anonymous';
                            final String email = account['email']?.toString() ?? 'No email set';

                            IconData roleIcon;
                            Color roleColor;
                            if (role == 'student') {
                              roleIcon = Icons.school_outlined;
                              roleColor = Colors.blue;
                            } else if (role == 'academic_supervisor') {
                              roleIcon = Icons.badge_outlined;
                              roleColor = Colors.green;
                            } else {
                              roleIcon = Icons.business_outlined;
                              roleColor = Colors.amber;
                            }

                            return Card(
                              elevation: 1,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: roleColor.withValues(alpha: 0.1),
                                  child: Icon(roleIcon, color: roleColor),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('$email\nRole: ${role.replaceAll('_', ' ').toUpperCase()}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                isThreeLine: true,
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  onPressed: () => _deleteAccount(account['id'], name),
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
    final selected = _selectedRoleFilter == value;
    final theme = Theme.of(context);

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: theme.colorScheme.primaryContainer,
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedRoleFilter = value;
          });
          _loadAccounts(_searchController.text);
        }
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
