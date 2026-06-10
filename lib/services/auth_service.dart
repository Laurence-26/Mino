import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';

import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '386356240136-1jikkedhu6his1c78qgnvsfhbffc0ibr.apps.googleusercontent.com',
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String _getFriendlyError(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
          return 'Incorrect password.';
        case 'email-already-in-use':
          return 'An account already exists with this email.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'requires-recent-login':
          return 'Please log out and log in again, then try.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Try again later.';
        default:
          return e.message ?? 'Something went wrong.';
      }
    }
    return e.toString();
  }

  // ── Email / Password ──────────────────────────────────────────────

  Future<AppUser?> signInWithEmail(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return await _getUserFromFirestore(cred.user!.uid);
    } on FirebaseAuthException catch (e) {
      throw _getFriendlyError(e);
    }
  }

  Future<AppUser?> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final user = cred.user!;
      await user.updateDisplayName(name.trim());

      final appUser = AppUser(
        uid: user.uid,
        phone: '',
        email: email.trim(),
        displayName: name.trim(),
        createdAt: DateTime.now(),
      );
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(appUser.toMap());
      return appUser;
    } on FirebaseAuthException catch (e) {
      throw _getFriendlyError(e);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _getFriendlyError(e);
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────

  Future<AppUser?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final cred = await _auth.signInWithCredential(credential);
      final user = cred.user!;

      final resolvedName =
          user.displayName ?? googleUser.displayName ?? 'User';
      final resolvedPhoto = user.photoURL;

      if (user.displayName == null || user.displayName!.isEmpty) {
        await user.updateDisplayName(resolvedName);
      }

      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        final appUser = AppUser(
          uid: user.uid,
          phone: '',
          email: user.email ?? '',
          displayName: resolvedName,
          photoUrl: resolvedPhoto,
          createdAt: DateTime.now(),
        );
        await docRef.set(appUser.toMap());
        return appUser;
      }

      // Merge the latest Google profile into the existing doc so
      // displayName/photoUrl/email are kept up to date.
      final existing = AppUser.fromMap(doc.data()!);
      final mergedDisplayName =
          (existing.displayName == null || existing.displayName!.isEmpty)
              ? resolvedName
              : existing.displayName;
      final mergedPhotoUrl = existing.photoUrl ?? resolvedPhoto;
      final mergedEmail =
          existing.email.isEmpty ? (user.email ?? '') : existing.email;

      await docRef.set({
        'displayName': mergedDisplayName,
        'photoUrl': mergedPhotoUrl,
        'email': mergedEmail,
      }, SetOptions(merge: true));

      return AppUser(
        uid: existing.uid,
        phone: existing.phone,
        email: mergedEmail,
        displayName: mergedDisplayName,
        photoUrl: mergedPhotoUrl,
        createdAt: existing.createdAt,
        groupIds: existing.groupIds,
      );
    } on FirebaseAuthException catch (e) {
      throw _getFriendlyError(e);
    } catch (e) {
      throw 'Google sign-in failed: $e';
    }
  }

  // ── Anonymous ─────────────────────────────────────────────────────

  Future<AppUser?> signInAnonymously(String name) async {
    try {
      final cred = await _auth.signInAnonymously();
      final user = cred.user!;
      await user.updateDisplayName(name.trim());

      final appUser = AppUser(
        uid: user.uid,
        phone: '',
        email: '',
        displayName: name.trim(),
        createdAt: DateTime.now(),
        groupIds: [],
      );
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(appUser.toMap());
      return appUser;
    } on FirebaseAuthException catch (e) {
      throw _getFriendlyError(e);
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // ── Delete Account ────────────────────────────────────────────────

  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No user logged in.';

    try {
      // Re-authenticate based on provider
      final providers = user.providerData.map((p) => p.providerId).toList();

      if (providers.contains('google.com')) {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) throw 'Re-authentication cancelled.';
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      } else if (providers.contains('password')) {
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: password.trim(),
        );
        await user.reauthenticateWithCredential(credential);
      }

      await _firestore.collection('users').doc(user.uid).delete();
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw _getFriendlyError(e);
    }
  }

  // ── Internal ──────────────────────────────────────────────────────

  Future<AppUser?> _getUserFromFirestore(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) return AppUser.fromMap(doc.data()!);
      return null;
    } catch (_) {
      return null;
    }
  }
}
