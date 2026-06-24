// FILE: providers/session_provider.dart  
// PURPOSE: Session state — partner info, conversation id, unread messages.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/models.dart';

final sessionProvider = FutureProvider<Session>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return await apiService.loadSession();
});

final partnerProvider = Provider<Partner?>((ref) {
  final sessionAsync = ref.watch(sessionProvider);
  return sessionAsync.valueOrNull?.partner;
});
