import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/auth_repository.dart';
import 'providers.dart';

class MainDrawer extends ConsumerWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(userProfileProvider).value;
    final theme = Theme.of(context);

    final fullName = profile?['full_name'] ?? user?.userMetadata?['full_name'] ?? 'User';
    final role = profile?['role'] ?? user?.userMetadata?['role'] ?? 'Guest';

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            currentAccountPicture: CircleAvatar(
              backgroundColor: theme.colorScheme.secondary,
              child: Text(
                fullName[0].toUpperCase(),
                style: TextStyle(fontSize: 24, color: theme.colorScheme.onSecondary),
              ),
            ),
            accountName: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(user?.email ?? ''),
            decoration: BoxDecoration(color: theme.colorScheme.primary),
          ),
          ListTile(
            leading: const Icon(Icons.home_rounded),
            title: const Text('Dashboard'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Sync Now'),
            onTap: () {
              Navigator.pop(context);
              ref.read(syncServiceProvider).syncData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Synchronization started...')),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              // AppRouteStateProvider will handle navigation automatically
              Navigator.pop(context);

              // Pillar 4: Instant Invalidation
              ref.invalidate(userProfileProvider);
              ref.invalidate(currentUserLogsProvider);
              ref.invalidate(internshipProgressProvider);

              await ref.read(authRepositoryProvider).signOut();
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Role: ${role.toString().replaceAll('_', ' ').toUpperCase()}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
