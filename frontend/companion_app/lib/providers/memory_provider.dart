// FILE: providers/memory_provider.dart
// PURPOSE: Memory vault state — fetching, filtering, pin/delete actions.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/models.dart';

class MemoriesNotifier extends StateNotifier<List<Memory>> {
  final Ref _ref;
  int _page = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String? _type;
  String _sort = 'recent';

  MemoriesNotifier(this._ref) : super(const []);

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> load(String? type, String sort) async {
    _type = type;
    _sort = sort;
    _page = 1;
    _hasMore = true;
    _isLoadingMore = false;

    try {
      final apiService = _ref.read(apiServiceProvider);
      final list = await apiService.getMemories(type: type, sort: sort, page: 1);
      state = list;
      _hasMore = list.length >= 10;
    } catch (e) {
      debugPrint('Error loading memories: $e');
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    final nextPage = _page + 1;

    try {
      final apiService = _ref.read(apiServiceProvider);
      final list = await apiService.getMemories(type: _type, sort: _sort, page: nextPage);
      if (list.isEmpty) {
        _hasMore = false;
      } else {
        state = [...state, ...list];
        _page = nextPage;
        _hasMore = list.length >= 10;
      }
    } catch (e) {
      debugPrint('Error loading more memories: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> pin(int id) async {
    final originalState = state;
    bool found = false;
    
    state = state.map((m) {
      if (m.id == id) {
        found = true;
        final nextPinned = !m.isPinned;
        return Memory(
          id: m.id,
          memoryText: m.memoryText,
          memoryType: m.memoryType,
          salienceScore: nextPinned ? 0.99 : 0.5,
          emotionalValence: m.emotionalValence,
          isPinned: nextPinned,
          recallCount: m.recallCount,
          tags: m.tags,
          createdAt: m.createdAt,
        );
      }
      return m;
    }).toList();

    if (!found) return;

    try {
      final apiService = _ref.read(apiServiceProvider);
      await apiService.pinMemory(id);
    } catch (e) {
      debugPrint('Error toggling pin status for memory: $e');
      state = originalState; // revert optimistically
    }
  }

  Future<void> delete(int id) async {
    try {
      final apiService = _ref.read(apiServiceProvider);
      await apiService.deleteMemory(id);
      state = state.where((m) => m.id != id).toList();
    } catch (e) {
      debugPrint('Error deleting memory: $e');
    }
  }
}

final memoriesProvider = StateNotifierProvider<MemoriesNotifier, List<Memory>>((ref) {
  return MemoriesNotifier(ref);
});
