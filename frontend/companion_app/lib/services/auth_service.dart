// ═══════════════════════════════════════════════════════════════════
// FILE: services/auth_service.dart
// PURPOSE: Firebase Auth — Google and email sign-in, auth state stream.
// CONTEXT: Used by auth_provider.dart and routing logic in main.dart.
// ═══════════════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.uid;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleAccount = await _googleSignIn.signIn();
      if (googleAccount == null) {
        throw const AuthException('Google sign-in cancelled by user');
      }

      final GoogleSignInAuthentication googleAuth = await googleAccount.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Authentication failed', code: e.code);
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  Future<UserCredential> createWithEmail(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Registration failed', code: e.code);
    } catch (e) {
      throw AuthException(e.toString());
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  Future<String> getCurrentIdToken() async {
    return await _auth.currentUser?.getIdToken() ?? '';
  }

  // --- Compatibility Aliases ---

  Future<User?> signInWithEmailPassword(String email, String password) async {
    final cred = await signInWithEmail(email, password);
    return cred.user;
  }

  Future<User?> signUpWithEmailPassword(String email, String password) async {
    final cred = await createWithEmail(email, password);
    return cred.user;
  }

  Future<String?> getIdToken() async {
    return await _auth.currentUser?.getIdToken();
  }
}

class AuthException implements Exception {
  final String message;
  final String? code;
  const AuthException(this.message, {this.code});

  @override
  String toString() => message;
}
