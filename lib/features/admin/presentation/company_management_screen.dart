import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/services/local_database.dart';
import '../../../core/services/providers.dart';

class CompanyManagementScreen extends ConsumerStatefulWidget {
  const CompanyManagementScreen({super.key});

  @override
  ConsumerState<CompanyManagementScreen> createState() => _CompanyManagementScreenState();
}

class _CompanyManagementScreenState extends ConsumerState<CompanyManagementScreen> {
  List<Map<String, dynamic>> _companies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    final db = await LocalDatabase.instance.database;
    final results = await db.query('companies', where: 'is_deleted = ?', whereArgs: [0]);
    setState(() {
      _companies = results;
      _isLoading = false;
    });
  }

  Future<void> _upsertCompany({String? id, required String name, required String email, String? address, String? contactPerson}) async {
    final db = await LocalDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final companyId = id ?? const Uuid().v4();

    await db.insert('companies', {
      'id': companyId,
      'name': name,
      'email': email,
      'address': address,
      'contact_person': contactPerson,
      'updated_at': now,
      'is_dirty': 1,
      'is_deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _loadCompanies();
    ref.read(syncServiceProvider).syncData();
  }

  Future<void> _deleteCompany(String id) async {
    final db = await LocalDatabase.instance.database;
    await db.update('companies', {
      'is_deleted': 1,
      'is_dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    _loadCompanies();
    ref.read(syncServiceProvider).syncData();
  }

  void _showCompanyDialog({Map<String, dynamic>? company}) {
    final nameController = TextEditingController(text: company?['name']);
    final emailController = TextEditingController(text: company?['email']);
    final addressController = TextEditingController(text: company?['address']);
    final contactPersonController = TextEditingController(text: company?['contact_person']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(company == null ? 'Add Company' : 'Edit Company'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Company Name')),
              const SizedBox(height: 12),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Official Email')),
              const SizedBox(height: 12),
              TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Physical Address')),
              const SizedBox(height: 12),
              TextField(controller: contactPersonController, decoration: const InputDecoration(labelText: 'Contact Person')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _upsertCompany(
                id: company?['id'],
                name: nameController.text,
                email: emailController.text,
                address: addressController.text,
                contactPerson: contactPersonController.text,
              );
              Navigator.pop(context);
            },
            child: Text(company == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Company Profiles')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _companies.isEmpty
            ? const Center(child: Text('No companies registered yet.'))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _companies.length,
                itemBuilder: (context, index) {
                  final company = _companies[index];
                  return Card(
                    child: ListTile(
                      title: Text(company['name'] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${company['email'] ?? 'No email'}\n${company['contact_person'] ?? 'No contact'}'),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showCompanyDialog(company: company),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _confirmDelete(company),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCompanyDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> company) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Company'),
        content: Text('Are you sure you want to delete ${company['name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _deleteCompany(company['id']);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}
