import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/firestore_provider.dart';
import 'package:pesa_tools/models/group_model.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _codeController = TextEditingController();
  GroupRole _selectedRole = GroupRole.editor;
  bool _isLoading = false;

  Future<void> _joinGroup() async {
    if (_codeController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) throw Exception('Not logged in');
      final firestore = ref.read(firestoreServiceProvider);
      await firestore.joinGroup(_codeController.text, user.uid, _selectedRole);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTranslations.of(context, 'joinGroup'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _codeController, decoration: InputDecoration(labelText: AppTranslations.of(context, 'groupCode'), border: const OutlineInputBorder())),
            const SizedBox(height: 16),
            DropdownButtonFormField<GroupRole>(
              value: _selectedRole,
              decoration: InputDecoration(labelText: AppTranslations.of(context, 'yourRole'), border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: GroupRole.editor, child: Text(AppTranslations.of(context, 'editor_role'))),
                DropdownMenuItem(value: GroupRole.viewer, child: Text(AppTranslations.of(context, 'viewer_role'))),
              ],
              onChanged: (value) => setState(() => _selectedRole = value ?? GroupRole.viewer),
            ),
            const SizedBox(height: 32),
            ElevatedButton(onPressed: _isLoading ? null : _joinGroup, child: Text(AppTranslations.of(context, 'joinGroup'))),
          ],
        ),
      ),
    );
  }
}
