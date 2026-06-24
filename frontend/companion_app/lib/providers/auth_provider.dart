// FILE: providers/auth_provider.dart
// PURPOSE: Riverpod provider for Firebase auth state.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

final authProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  // We watch authProvider to ensure the current user updates reactively when auth state changes
  ref.watch(authProvider);
  final authService = ref.read(authServiceProvider);
  return authService.currentUser;
});
