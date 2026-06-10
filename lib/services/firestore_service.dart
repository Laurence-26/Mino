import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:uuid/uuid.dart';
import 'package:rxdart/rxdart.dart';
import '../models/transaction_model.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';

class FirestoreService {
  final fs.FirebaseFirestore _firestore = fs.FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  // --- User ---
  Stream<AppUser?> getUserStream(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _firestore.collection('users').doc(uid).snapshots().map(
          (doc) => doc.exists
              ? AppUser.fromMap({...doc.data()!, 'uid': doc.id})
              : null,
        );
  }

  // --- Personal Transactions ---
  Future<void> addTransaction(Transaction transaction) async {
    if (transaction.id.isEmpty || transaction.userId.isEmpty) return;
    await _firestore
        .collection('transactions')
        .doc(transaction.id)
        .set(transaction.toMap());
  }

  Stream<List<Transaction>> getTransactionsForUser(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Transaction.fromMap(doc.data()))
            .toList());
  }

  Future<void> updateTransaction(Transaction transaction) async {
    if (transaction.id.isEmpty) return;
    await _firestore
        .collection('transactions')
        .doc(transaction.id)
        .update(transaction.toMap());
  }

  Future<void> deleteTransaction(String transactionId) async {
    if (transactionId.isEmpty) return;
    await _firestore.collection('transactions').doc(transactionId).delete();
  }

  // --- Groups ---
  // Chunked version to handle >10 groups
  Stream<List<Group>> getUserGroupsStream(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .asyncMap((userDoc) async {
      final groupIds = List<String>.from(userDoc.data()?['groupIds'] ?? []);
      if (groupIds.isEmpty) return [];

      // Firestore whereIn supports max 10 values, so we chunk
      const chunkSize = 10;
      List<Group> allGroups = [];
      for (var i = 0; i < groupIds.length; i += chunkSize) {
        final chunk = groupIds.sublist(i,
            i + chunkSize > groupIds.length ? groupIds.length : i + chunkSize);
        final snapshot = await _firestore
            .collection('groups')
            .where(fs.FieldPath.documentId, whereIn: chunk)
            .get();
        allGroups.addAll(snapshot.docs
            .map((doc) => Group.fromMap(doc.id, doc.data())));
      }
      return allGroups;
    });
  }

  // Create group using name and adminUid (generates id and invite code internally)
  Future<String> createGroup(String name, String adminUid) async {
    if (adminUid.isEmpty) throw ArgumentError('adminUid cannot be empty');
    final groupId = _uuid.v4();
    final inviteCode = _uuid.v4().substring(0, 6).toUpperCase();
    final group = Group(
      id: groupId,
      name: name,
      createdBy: adminUid,
      createdAt: DateTime.now(),
      members: {adminUid: GroupRole.admin},
      inviteCode: inviteCode,
    );
    await _firestore.collection('groups').doc(groupId).set(group.toMap());
    await _firestore.collection('users').doc(adminUid).update({
      'groupIds': fs.FieldValue.arrayUnion([groupId]),
    });
    return groupId;
  }

  // NEW: Update group name
  Future<void> updateGroupName(String groupId, String newName) async {
    if (groupId.isEmpty) return;
    await _firestore.collection('groups').doc(groupId).update({'name': newName});
  }

  Future<void> joinGroup(String inviteCode, String userId, GroupRole role) async {
    if (userId.isEmpty) throw ArgumentError('userId cannot be empty');
    final query = await _firestore
        .collection('groups')
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) throw Exception('Invalid invite code');

    final groupDoc = query.docs.first;
    final groupId = groupDoc.id;
    final groupData = groupDoc.data();

    if (groupData['members'] != null &&
        (groupData['members'] as Map).containsKey(userId)) {
      throw Exception('You are already a member of this group');
    }

    await groupDoc.reference.update({
      'members.$userId': role.name,
    });

    await _firestore.collection('users').doc(userId).update({
      'groupIds': fs.FieldValue.arrayUnion([groupId]),
    });
  }

  Stream<Group?> getGroupStream(String groupId) {
    if (groupId.isEmpty) return Stream.value(null);
    return _firestore.collection('groups').doc(groupId).snapshots().map(
          (doc) => doc.exists ? Group.fromMap(doc.id, doc.data()!) : null,
        );
  }

  // Improved: skip missing user docs
  Stream<List<AppUser>> getGroupMembersStream(String groupId) {
    if (groupId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .switchMap((doc) {
      if (!doc.exists) return Stream.value([]);
      final membersMap = doc.data()?['members'] as Map<String, dynamic>? ?? {};
      final memberUids =
          membersMap.keys.where((k) => k.isNotEmpty).toList();
      if (memberUids.isEmpty) return Stream.value([]);

      final userStreams = memberUids
          .map((uid) => _firestore
              .collection('users')
              .doc(uid)
              .snapshots()
              .map((doc) => doc.exists
                  ? AppUser.fromMap({...doc.data()!, 'uid': doc.id})
                  : null)
              .where((user) => user != null)
              .cast<AppUser>())
          .toList();

      return Rx.combineLatestList(userStreams);
    });
  }

  // Leave group
  Future<void> leaveGroup(String groupId, String userId) async {
    if (groupId.isEmpty || userId.isEmpty) return;
    await _firestore.collection('groups').doc(groupId).update({
      'members.$userId': fs.FieldValue.delete(),
    });
    await _firestore.collection('users').doc(userId).update({
      'groupIds': fs.FieldValue.arrayRemove([groupId]),
    });
  }

  // Remove member (admin only)
  Future<void> removeMember(String groupId, String memberId) async {
    if (groupId.isEmpty || memberId.isEmpty) return;
    await leaveGroup(groupId, memberId); // reuse logic
  }

  // Delete group entirely (admin only) – also removes groupId from all members
  Future<void> deleteGroup(String groupId) async {
    if (groupId.isEmpty) return;
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return;
    final membersMap = groupDoc.data()?['members'] as Map<String, dynamic>? ?? {};
    final memberUids = membersMap.keys.toList();

    // Delete all transactions subcollection
    final transactions = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('transactions')
        .get();
    for (var doc in transactions.docs) {
      await doc.reference.delete();
    }

    // Delete the group document
    await _firestore.collection('groups').doc(groupId).delete();

    // Remove groupId from all members' groupIds
    for (var uid in memberUids) {
      await _firestore.collection('users').doc(uid).update({
        'groupIds': fs.FieldValue.arrayRemove([groupId]),
      });
    }
  }

  // --- Group Transactions (subcollection) ---
  Future<void> addGroupTransaction(String groupId, Transaction transaction) async {
    if (groupId.isEmpty || transaction.id.isEmpty) return;
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('transactions')
        .doc(transaction.id)
        .set(transaction.toMap());
  }

  Stream<List<Transaction>> getGroupTransactionsStream(String groupId) {
    if (groupId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('transactions')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Transaction.fromMap(doc.data()))
            .toList());
  }

  Future<void> updateGroupTransaction(String groupId, Transaction transaction) async {
    if (groupId.isEmpty || transaction.id.isEmpty) return;
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('transactions')
        .doc(transaction.id)
        .update(transaction.toMap());
  }

  Future<void> deleteGroupTransaction(String groupId, String transactionId) async {
    if (groupId.isEmpty || transactionId.isEmpty) return;
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('transactions')
        .doc(transactionId)
        .delete();
  }

  // --- User Categories ---
  Future<Map<String, List<String>>?> getUserCategories(String userId) async {
    if (userId.isEmpty) return null;
    final doc = await _firestore.collection('users').doc(userId).get();
    if (doc.exists) {
      final data = doc.data();
      if (data != null && data.containsKey('categories')) {
        final raw = data['categories'] as Map<String, dynamic>;
        return {
          'income': List<String>.from(raw['income'] ?? []),
          'expense': List<String>.from(raw['expense'] ?? []),
        };
      }
    }
    return null;
  }

  Future<void> saveUserCategories(String userId, Map<String, List<String>> categories) async {
    if (userId.isEmpty) return;
    await _firestore.collection('users').doc(userId).set({
      'categories': {
        'income': categories['income'] ?? [],
        'expense': categories['expense'] ?? [],
      }
    }, fs.SetOptions(merge: true));
  }

  Future<void> addCategory(String userId, TransactionType type, String categoryName) async {
    if (userId.isEmpty) return;
    final categoryListField = type == TransactionType.income ? 'income' : 'expense';
    await _firestore.collection('users').doc(userId).set({
      'categories': {
        categoryListField: fs.FieldValue.arrayUnion([categoryName]),
      }
    }, fs.SetOptions(merge: true));
  }
}