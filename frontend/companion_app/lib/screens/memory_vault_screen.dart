// FILE: screens/memory_vault_screen.dart
// PURPOSE: Displays saved memories while preserving provider-driven memory operations.
// RESPONSIBILITIES: Render memory browsing UI and delegate actions to memory state.
// NEVER: Contain backend rule changes or app-wide route setup.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../models/models.dart';
import '../providers/memory_provider.dart';
import '../theme/eden_colors.dart';
import '../theme/glass_theme.dart';
import '../components/glass.dart';

class MemoryVaultScreen extends ConsumerStatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  ConsumerState<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends ConsumerState<MemoryVaultScreen> {
  final ScrollController _scrollController = ScrollController();

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
    'Jokes',
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
            child: LiquidGlass.withOwnLayer(
              shape: GlassTheme.shape,
              settings: GlassTheme.prominent,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Forget this memory?',
                      style: _displayStyle(26),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This moment will disappear from their presence and context forever.',
                      style: _bodyStyle(14, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text('Keep',
                                style: _bodyStyle(15, color: Colors.white70)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _GlassActionButton(
                            label: 'Forget',
                            glowColor: EdenColors.orangeGlow,
                            onTap: () => Navigator.of(context).pop(true),
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
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What $partnerDisplay remembers',
                          style: _displayStyle(36),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$_totalMemoryCount memories total',
                          style: _bodyStyle(12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: _GlassCategoryPill(
                        text: cat,
                        selected: isSelected,
                        onTap: () => _onCategorySelected(cat),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isInitialLoading
                  ? _buildLoadingState()
                  : memories.isEmpty
                      ? _buildEmptyState()
                      : _buildMemoryGrid(memories),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryGrid(List<Memory> memories) {
    return GridView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final memory = memories[index];
        return Dismissible(
          key: Key(memory.id.toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: EdenColors.orangeGlow.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 24),
          ),
          confirmDismiss: (direction) async {
            final confirm = await _showDeleteConfirmation(context);
            if (confirm == true) {
              ref.read(memoriesProvider.notifier).delete(memory.id);
              setState(() {
                _totalMemoryCount =
                    _totalMemoryCount > 0 ? _totalMemoryCount - 1 : 0;
              });
              return true;
            }
            return false;
          },
          child: _MemoryGlassCard(
            memory: memory,
            onTap: () => _openMemoryDetail(memory),
            onLongPress: () => _togglePin(memory),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        return LiquidGlass.withOwnLayer(
          shape: GlassTheme.shape,
          settings: GlassTheme.card,
          child: const SizedBox.expand(),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: LiquidGlass.withOwnLayer(
        shape: GlassTheme.shape,
        settings: GlassTheme.card,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text('Nothing here yet.',
              style: _bodyStyle(14, color: Colors.white70)),
        ),
      ),
    );
  }

  void _openMemoryDetail(Memory memory) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MemoryDetailScreen(
          memory: memory,
          onTogglePin: () => _togglePin(memory),
        ),
      ),
    );
  }
}

class _MemoryGlassCard extends StatelessWidget {
  const _MemoryGlassCard({
    required this.memory,
    required this.onTap,
    required this.onLongPress,
  });

  final Memory memory;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass.withOwnLayer(
      shape: GlassTheme.shape,
      settings: GlassTheme.card,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _memoryTitle(memory),
                      style: _bodyStyle(13, color: Colors.white70).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (memory.isPinned)
                    const Icon(Icons.push_pin_rounded,
                        size: 15, color: Colors.white70),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  memory.memoryText,
                  style: _bodyStyle(15),
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _formatDate(memory.createdAt),
                style: _bodyStyle(11, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryDetailScreen extends StatelessWidget {
  const _MemoryDetailScreen({
    required this.memory,
    required this.onTogglePin,
  });

  final Memory memory;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: LiquidGlass.withOwnLayer(
            shape: GlassTheme.shape,
            settings: GlassTheme.prominent,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onTogglePin,
                        icon: Icon(
                          memory.isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(_memoryTitle(memory), style: _displayStyle(32)),
                  const SizedBox(height: 12),
                  Text(_formatDate(memory.createdAt),
                      style: _bodyStyle(12, color: Colors.white60)),
                  const SizedBox(height: 28),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(memory.memoryText, style: _bodyStyle(18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCategoryPill extends StatelessWidget {
  const _GlassCategoryPill({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      settings: selected ? GlassTheme.button : GlassTheme.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            text,
            style:
                _bodyStyle(13, color: selected ? Colors.white : Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    required this.label,
    required this.glowColor,
    required this.onTap,
  });

  final String label;
  final Color glowColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassGlow(
      glowColor: glowColor,
      glowRadius: 0.8,
      child: FakeGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 18),
        settings: GlassTheme.button,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(label, style: _bodyStyle(15)),
            ),
          ),
        ),
      ),
    );
  }
}

String _memoryTitle(Memory memory) {
  return memory.memoryType.name;
}

String _formatDate(DateTime date) {
  return '${date.month}/${date.day}/${date.year}';
}

TextStyle _displayStyle(double size, {Color color = Colors.white}) {
  return TextStyle(
    fontFamily: 'CormorantGaramond',
    fontWeight: FontWeight.w300,
    fontSize: size,
    color: color,
    height: 1.12,
  );
}

TextStyle _bodyStyle(double size, {Color color = Colors.white}) {
  return TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontWeight: FontWeight.w400,
    fontSize: size,
    color: color,
    height: 1.45,
  );
}
