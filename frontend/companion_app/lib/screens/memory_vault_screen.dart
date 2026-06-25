// ═══════════════════════════════════════════════════════════════════
// FILE: screens/memory_vault_screen.dart
// PURPOSE: Browse and manage what the partner remembers about the user.
// CONTEXT: Accessed from settings. Shows episodic memories by type.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../models/models.dart';
import '../providers/memory_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/shimmer_loader.dart';
import '../widgets/pill_option.dart';
import '../widgets/memory_card.dart';
import '../main.dart';

class MemoryVaultScreen extends ConsumerStatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  ConsumerState<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends ConsumerState<MemoryVaultScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey<MemoryCardState>> _cardKeys = {};
  
  bool _isInitialLoading = true;
  String? _partnerName;
  int _totalMemoryCount = 0;
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Feelings',
    'Facts',
    'Events',
    'Preferences',
    'Struggles',
    'Growth',
    'Rituals',
    'Jokes'
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeData());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _loadProfileInfo();
    if (mounted) {
      await ref.read(memoriesProvider.notifier).load(null, 'recent');
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _loadProfileInfo() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final profile = await apiService.getProfile();
      if (mounted) {
        setState(() {
          _partnerName = profile['partner']?['name'] ?? 'Companion';
          _totalMemoryCount = profile['partner']?['memory_count'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Failed to load profile details: $e');
    }
  }

  void _onScroll() {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll > 0 && currentScroll / maxScroll >= 0.8) {
      ref.read(memoriesProvider.notifier).loadMore();
    }
  }

  void _onCategorySelected(String category) {
    if (_selectedCategory == category) return;
    
    setState(() {
      _selectedCategory = category;
      _isInitialLoading = true;
    });

    String? type;
    if (category != 'All') {
      final map = {
        'Feelings': 'feeling',
        'Facts': 'fact',
        'Events': 'event',
        'Preferences': 'preference',
        'Struggles': 'struggle',
        'Growth': 'growth',
        'Rituals': 'ritual',
        'Jokes': 'joke',
      };
      type = map[category];
    }
    
    ref.read(memoriesProvider.notifier).load(type, 'recent').then((_) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    });
  }

  Future<void> _togglePin(Memory memory) async {
    HapticFeedback.mediumImpact();
    // MemoriesNotifier handles optimistic update & revert automatically
    await ref.read(memoriesProvider.notifier).pin(memory.id);
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'confirm_delete',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: Dialog(
              backgroundColor: EdenColors.edenSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Forget this memory?',
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: EdenColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This moment will disappear from their presence and context forever.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: EdenColors.textSecondary,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(
                              'Keep',
                              style: GoogleFonts.jost(
                                fontSize: 15,
                                color: EdenColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Material(
                              color: EdenColors.semanticError.withValues(alpha: 0.15),
                              child: InkWell(
                                onTap: () => Navigator.of(context).pop(true),
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: EdenColors.semanticError.withValues(alpha: 0.3), 
                                      width: 0.8,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Forget',
                                      style: GoogleFonts.jost(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: EdenColors.semanticError,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final memories = ref.watch(memoriesProvider);
    final partnerDisplay = _partnerName ?? 'Companion';

    return Scaffold(
      backgroundColor: EdenColors.edenSurface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: "What [partnerName] remembers" (CormorantGaramond 36sp, left-aligned)
            Padding(
              padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 48.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What $partnerDisplay remembers',
                    style: EdenTypography.displayLg.copyWith(
                      color: EdenColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_totalMemoryCount memories total',
                    style: EdenTypography.bodySm.copyWith(
                      color: EdenColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Filter pills (horizontal scroll, no scrollbar)
            Padding(
              padding: const EdgeInsets.only(top: 9.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: PillOption(
                        text: cat,
                        isSelected: isSelected,
                        isFullWidth: false,
                        onTap: () => _onCategorySelected(cat),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Memory list
            Expanded(
              child: _isInitialLoading
                  ? _buildShimmerLoadingState()
                  : memories.isEmpty
                      ? _buildEmptyState()
                      : _buildMemoryList(memories),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryList(List<Memory> memories) {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final memory = memories[index];
        final key = _cardKeys.putIfAbsent(memory.id, () => GlobalKey<MemoryCardState>());

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Dismissible(
            key: Key(memory.id.toString()),
            direction: DismissDirection.endToStart,
            background: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: EdenColors.semanticError,
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            confirmDismiss: (direction) async {
              // Play shake animation for confirmation feedback
              final cardState = key.currentState;
              if (cardState != null) {
                await cardState.shake();
              }
              // Show dialog
              if (!context.mounted) return false;
              final confirm = await _showDeleteConfirmation(context);
              if (confirm == true) {
                ref.read(memoriesProvider.notifier).delete(memory.id);
                setState(() {
                  _totalMemoryCount = _totalMemoryCount > 0 ? _totalMemoryCount - 1 : 0;
                });
                return true;
              }
              return false;
            },
            child: MemoryCard(
              key: key,
              memory: memory,
              onLongPress: () => _togglePin(memory),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerLoadingState() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerLoader(width: 80, height: 12, borderRadius: 4),
                const SizedBox(height: 12),
                const ShimmerLoader(width: double.infinity, height: 16, borderRadius: 4),
                const SizedBox(height: 6),
                const ShimmerLoader(width: 200, height: 16, borderRadius: 4),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ShimmerLoader(width: 100, height: 12, borderRadius: 4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(
          'Nothing here yet.',
          style: EdenTypography.bodySm.copyWith(
            color: EdenColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
