// ═══════════════════════════════════════════════════════════════════
// FILE: services/local_cache_service.dart
// PURPOSE: Isar DB local cache — last 50 messages available offline instantly.
// CONTEXT: Used by chat screen to show messages before backend responds.
// ═══════════════════════════════════════════════════════════════════

// RESPONSIBILITIES: Persist lightweight local cache data for frontend responsiveness.
// NEVER: Contain widget state, route definitions, or remote API logic.
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class LocalCacheService {
  Isar? _isar;

  Future<Isar> get isar async {
    if (_isar != null) return _isar!;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [MessageSchema],
      directory: dir.path,
    );
    return _isar!;
  }

  Future<void> saveMessages(List<Message> messages) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.messages.putAll(messages);
    });
  }

  Future<List<Message>> getRecentMessages({int limit = 50}) async {
    final db = await isar;
    return await db.messages.where().sortBySentAtDesc().limit(limit).findAll();
  }

  Future<void> clearAll() async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.messages.clear();
    });
  }

  void dispose() {
    _isar?.close();
    _isar = null;
  }
}
