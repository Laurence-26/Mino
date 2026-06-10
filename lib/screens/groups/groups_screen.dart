import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/providers/group_provider.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/screens/groups/create_group_screen.dart';
import 'package:pesa_tools/screens/groups/group_detail_screen.dart';
import 'package:pesa_tools/screens/groups/join_group_screen.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  void _showFABMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 0, 0), // approximate
      items: [
        PopupMenuItem(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
          child: Row(
            children: [const Icon(Icons.create), const SizedBox(width: 8), Text(AppTranslations.of(context, 'createGroup'))],
          ),
        ),
        PopupMenuItem(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinGroupScreen())),
          child: Row(
            children: [const Icon(Icons.group_add), const SizedBox(width: 8), Text(AppTranslations.of(context, 'joinGroup'))],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppTranslations.of(context, 'groups'))),
      body: groupsAsync.when(
        data: (groups) {
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_off, size: 80, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(AppTranslations.of(context, 'noActiveGroup'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(AppTranslations.of(context, 'joinGroupDesc'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinGroupScreen())),
                      icon: const Icon(Icons.group_add),
                      label: Text(AppTranslations.of(context, 'joinGroup')),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
                      icon: const Icon(Icons.create),
                      label: Text(AppTranslations.of(context, 'createGroup')),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.group)),
                title: Text(group.name),
                subtitle: Text('${group.members.length} members'),
                trailing: Text(group.inviteCode ?? ''),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id))),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showFABMenu(context), child: const Icon(Icons.add)),
    );
  }
}
