import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/models/group_model.dart';
import 'package:pesa_tools/models/transaction_model.dart';
import 'package:pesa_tools/models/user_model.dart';
import 'package:pesa_tools/providers/auth_provider.dart';
import 'package:pesa_tools/providers/firestore_provider.dart';

/// Stream of groups the current user is a member of.
final userGroupsStreamProvider = StreamProvider<List<Group>>((ref) {
  final userId = ref.watch(currentUserProvider).value?.uid;
  if (userId == null) return Stream.value([]);
  final firestore = ref.watch(firestoreServiceProvider);
  return firestore.getUserGroupsStream(userId);
});

/// Stream of members belonging to a specific group.
final groupMembersStreamProvider = StreamProvider.family<List<AppUser>, String>((ref, groupId) {
  final firestore = ref.watch(firestoreServiceProvider);
  return firestore.getGroupMembersStream(groupId);
});

/// Stream of a single group.
final groupStreamProvider = StreamProvider.family<Group?, String>((ref, groupId) {
  final firestore = ref.watch(firestoreServiceProvider);
  return firestore.getGroupStream(groupId);
});

/// Stream of transactions for a specific group
final groupTransactionsStreamProvider = StreamProvider.family<List<Transaction>, String>((ref, groupId) {
  final firestore = ref.watch(firestoreServiceProvider);
  return firestore.getGroupTransactionsStream(groupId);
});

/// Get the current user's role in the group
final userGroupRoleProvider = FutureProvider.family<GroupRole?, String>((ref, groupId) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return null;
  final group = await ref.watch(groupStreamProvider(groupId).future);
  return group?.members[user.uid];
});


/// Is current user admin in group
final isGroupAdminProvider = Provider.family<bool, String>((ref, groupId) {
  final user = ref.watch(currentUserProvider).value;
  final groupAsync = ref.watch(groupStreamProvider(groupId));

  return groupAsync.when(
    data: (group) {
      if (user == null || group == null) return false;
      return group.members[user.uid] == GroupRole.admin;
    },
    loading: () => false,
    error: (_, __) => false,
  );
});
