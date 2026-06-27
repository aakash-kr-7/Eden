// FILE: screens/memory_vault_screen.dart
// PURPOSE: Present the memory vault as a calm archive while preserving existing memory provider behavior.
// RESPONSIBILITIES: Render memory browsing, filtering, pinning, deletion, and detail presentation.
// NEVER: Change backend memory contracts, provider interfaces, or app-wide routing rules.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../models/models.dart';
import '../providers/memory_provider.dart';
import '../theme/nocturne.dart';

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

  final List<String> _categories = const [
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
    if (!_scrollController.hasClients) return;

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
      const map = {
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
      barrierColor: Colors.black.withValues(alpha: 0.82),
      transitionDuration: Nocturne.durationStandard,
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Nocturne.space8),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: ScaleTransition(
                scale: Tween<double>(
                  begin: 0.96,
                  end: 1,
                ).animate(
                  CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(Nocturne.space8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C0D0F),
                    borderRadius: BorderRadius.circular(Nocturne.radiusXl),
                    border: Border.all(color: Nocturne.borderStrong),
                    boxShadow: Nocturne.elevationHigh,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Forget this memory?',
                        style: Nocturne.displayMd,
                      ),
                      const SizedBox(height: Nocturne.space4),
                      Text(
                        'This moment will disappear from their archive and living context.',
                        style: Nocturne.bodyLg.copyWith(
                          color: Nocturne.textSecondary,
                        ),
                      ),
                      const SizedBox(height: Nocturne.space8),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogButton(
                              label: 'Keep',
                              onTap: () => Navigator.of(context).pop(false),
                            ),
                          ),
                          const SizedBox(width: Nocturne.space4),
                          Expanded(
                            child: _DialogButton(
                              label: 'Forget',
                              destructive: true,
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
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final memories = ref.watch(memoriesProvider);
    final notifier = ref.read(memoriesProvider.notifier);
    final pinned = memories.where((memory) => memory.isPinned).toList();
    final archive = memories.where((memory) => !memory.isPinned).toList();
    final partnerDisplay = _partnerName ?? 'Companion';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            const _VaultBackdrop(),
            CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _VaultHeader(
                    partnerName: partnerDisplay,
                    totalMemoryCount: _totalMemoryCount,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CategoryStrip(
                    categories: _categories,
                    selectedCategory: _selectedCategory,
                    onSelected: _onCategorySelected,
                  ),
                ),
                if (_isInitialLoading)
                  const SliverToBoxAdapter(
                    child: _LoadingSection(),
                  )
                else if (memories.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyVaultState(),
                  )
                else ...[
                  if (pinned.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionHeading(
                        title: 'Pinned',
                        subtitle: 'The moments held closest.',
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Nocturne.space8,
                        0,
                        Nocturne.space8,
                        Nocturne.space8,
                      ),
                      sliver: SliverList.builder(
                        itemCount: pinned.length,
                        itemBuilder: (context, index) {
                          final memory = pinned[index];
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: Nocturne.space5),
                            child: _DismissibleMemoryCard(
                              memory: memory,
                              prominent: true,
                              onOpen: () => _openMemoryDetail(memory),
                              onTogglePin: () => _togglePin(memory),
                              onConfirmDelete: () async {
                                final confirm =
                                    await _showDeleteConfirmation(context);
                                if (confirm == true) {
                                  await ref
                                      .read(memoriesProvider.notifier)
                                      .delete(memory.id);
                                  if (mounted) {
                                    setState(() {
                                      _totalMemoryCount = _totalMemoryCount > 0
                                          ? _totalMemoryCount - 1
                                          : 0;
                                    });
                                  }
                                  return true;
                                }
                                return false;
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (archive.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionHeading(
                        title: 'Archive',
                        subtitle: 'Quieter traces, still kept.',
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Nocturne.space8,
                        0,
                        Nocturne.space8,
                        Nocturne.space9,
                      ),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final memory = archive[index];
                            return _DismissibleMemoryCard(
                              memory: memory,
                              prominent: false,
                              onOpen: () => _openMemoryDetail(memory),
                              onTogglePin: () => _togglePin(memory),
                              onConfirmDelete: () async {
                                final confirm =
                                    await _showDeleteConfirmation(context);
                                if (confirm == true) {
                                  await ref
                                      .read(memoriesProvider.notifier)
                                      .delete(memory.id);
                                  if (mounted) {
                                    setState(() {
                                      _totalMemoryCount = _totalMemoryCount > 0
                                          ? _totalMemoryCount - 1
                                          : 0;
                                    });
                                  }
                                  return true;
                                }
                                return false;
                              },
                            );
                          },
                          childCount: archive.length,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: Nocturne.space5,
                          crossAxisSpacing: Nocturne.space5,
                          childAspectRatio: 0.83,
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: Nocturne.space8,
                        right: Nocturne.space8,
                        bottom: Nocturne.space8,
                      ),
                      child: AnimatedOpacity(
                        opacity: notifier.isLoadingMore ? 1 : 0,
                        duration: Nocturne.durationFast,
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: Nocturne.space4),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
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

class _VaultBackdrop extends StatelessWidget {
  const _VaultBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          const ColoredBox(color: Colors.black),
          Positioned(
            top: -120,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Nocturne.accentWarm.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -80,
            top: 260,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Nocturne.accentCool.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultHeader extends StatelessWidget {
  const _VaultHeader({
    required this.partnerName,
    required this.totalMemoryCount,
    required this.onClose,
  });

  final String partnerName;
  final int totalMemoryCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Nocturne.space8,
        Nocturne.space8,
        Nocturne.space8,
        Nocturne.space7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Memory Vault',
                      style: Nocturne.displayLg.copyWith(fontSize: 40),
                    ),
                    const SizedBox(height: Nocturne.space3),
                    Text(
                      '$partnerName kept in quiet detail',
                      style: Nocturne.bodySm.copyWith(
                        color: Nocturne.textTertiary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                splashRadius: 18,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Nocturne.textSecondary,
                  size: Nocturne.iconXl,
                ),
              ),
            ],
          ),
          const SizedBox(height: Nocturne.space8),
          Wrap(
            spacing: Nocturne.space6,
            runSpacing: Nocturne.space4,
            children: [
              _VaultMetric(
                label: 'Total',
                value: '$totalMemoryCount',
              ),
              const _VaultMetric(
                label: 'Tone',
                value: 'Dark archive',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VaultMetric extends StatelessWidget {
  const _VaultMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Nocturne.space5,
        vertical: Nocturne.space4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C0E),
        borderRadius: BorderRadius.circular(Nocturne.radiusMd),
        border: Border.all(color: Nocturne.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Nocturne.label.copyWith(color: Nocturne.textTertiary),
          ),
          const SizedBox(height: Nocturne.space2),
          Text(value, style: Nocturne.bodyLg),
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Nocturne.space8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: Nocturne.space8),
        child: Row(
          children: categories.map((category) {
            final isSelected = selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: Nocturne.space3),
              child: InkWell(
                onTap: () => onSelected(category),
                borderRadius: BorderRadius.circular(Nocturne.radiusPill),
                child: AnimatedContainer(
                  duration: Nocturne.durationFast,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Nocturne.space5,
                    vertical: Nocturne.space3,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Nocturne.textPrimary
                        : const Color(0xFF0A0B0D),
                    borderRadius: BorderRadius.circular(Nocturne.radiusPill),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : Nocturne.borderSubtle,
                    ),
                  ),
                  child: Text(
                    category,
                    style: Nocturne.bodyMd.copyWith(
                      color:
                          isSelected ? Nocturne.black : Nocturne.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Nocturne.space8,
        0,
        Nocturne.space8,
        Nocturne.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Nocturne.displayMd),
          const SizedBox(height: Nocturne.space2),
          Text(
            subtitle,
            style: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DismissibleMemoryCard extends StatelessWidget {
  const _DismissibleMemoryCard({
    required this.memory,
    required this.prominent,
    required this.onOpen,
    required this.onTogglePin,
    required this.onConfirmDelete,
  });

  final Memory memory;
  final bool prominent;
  final VoidCallback onOpen;
  final VoidCallback onTogglePin;
  final Future<bool> Function() onConfirmDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(memory.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Nocturne.space6),
        decoration: BoxDecoration(
          color: Nocturne.destructive.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(Nocturne.radiusXl),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Nocturne.textPrimary,
          size: Nocturne.iconXl,
        ),
      ),
      confirmDismiss: (_) => onConfirmDelete(),
      child: prominent
          ? _PinnedMemoryCard(
              memory: memory,
              onOpen: onOpen,
              onTogglePin: onTogglePin,
            )
          : _ArchiveMemoryCard(
              memory: memory,
              onOpen: onOpen,
              onTogglePin: onTogglePin,
            ),
    );
  }
}

class _PinnedMemoryCard extends StatelessWidget {
  const _PinnedMemoryCard({
    required this.memory,
    required this.onOpen,
    required this.onTogglePin,
  });

  final Memory memory;
  final VoidCallback onOpen;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1013),
        borderRadius: BorderRadius.circular(Nocturne.radiusXl),
        border: Border.all(color: Nocturne.borderStrong),
        boxShadow: Nocturne.elevationHigh,
      ),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onTogglePin,
        borderRadius: BorderRadius.circular(Nocturne.radiusXl),
        child: Padding(
          padding: const EdgeInsets.all(Nocturne.space7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _memoryTitle(memory),
                      style: Nocturne.label.copyWith(
                        color: Nocturne.accentWarm,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.push_pin_rounded,
                    size: Nocturne.iconMd,
                    color: Nocturne.accentWarm,
                  ),
                ],
              ),
              const SizedBox(height: Nocturne.space6),
              Text(
                memory.memoryText,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: Nocturne.bodyXl.copyWith(height: 1.55),
              ),
              const SizedBox(height: Nocturne.space7),
              Row(
                children: [
                  Text(
                    _formatDate(memory.createdAt),
                    style:
                        Nocturne.bodySm.copyWith(color: Nocturne.textTertiary),
                  ),
                  const Spacer(),
                  _MemoryMetaChip(label: '${memory.recallCount} recalls'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveMemoryCard extends StatelessWidget {
  const _ArchiveMemoryCard({
    required this.memory,
    required this.onOpen,
    required this.onTogglePin,
  });

  final Memory memory;
  final VoidCallback onOpen;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF090A0C),
        borderRadius: BorderRadius.circular(Nocturne.radiusLg),
        border: Border.all(color: Nocturne.borderSubtle),
      ),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onTogglePin,
        borderRadius: BorderRadius.circular(Nocturne.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(Nocturne.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _memoryTitle(memory),
                style: Nocturne.label.copyWith(color: Nocturne.textTertiary),
              ),
              const SizedBox(height: Nocturne.space4),
              Expanded(
                child: Text(
                  memory.memoryText,
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: Nocturne.bodyMd.copyWith(
                    color: Nocturne.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: Nocturne.space4),
              Text(
                _formatDate(memory.createdAt),
                style: Nocturne.bodySm.copyWith(color: Nocturne.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryMetaChip extends StatelessWidget {
  const _MemoryMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Nocturne.space3,
        vertical: Nocturne.space2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(Nocturne.radiusPill),
        border: Border.all(color: Nocturne.borderSubtle),
      ),
      child: Text(
        label,
        style: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
      ),
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Nocturne.space8,
        Nocturne.space7,
        Nocturne.space8,
        Nocturne.space8,
      ),
      child: Column(
        children: List.generate(
          3,
          (index) => Container(
            height: 140,
            margin: const EdgeInsets.only(bottom: Nocturne.space5),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0C0E),
              borderRadius: BorderRadius.circular(Nocturne.radiusXl),
              border: Border.all(color: Nocturne.borderSubtle),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyVaultState extends StatelessWidget {
  const _EmptyVaultState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Nocturne.space9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nothing preserved yet.',
            style: Nocturne.displayMd,
          ),
          const SizedBox(height: Nocturne.space4),
          Text(
            'When something matters enough to keep, it will appear here in the archive.',
            style: Nocturne.bodyLg.copyWith(color: Nocturne.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Nocturne.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Nocturne.space5),
        decoration: BoxDecoration(
          color: destructive ? Nocturne.destructive : const Color(0xFF14171B),
          borderRadius: BorderRadius.circular(Nocturne.radiusLg),
          border: Border.all(
            color: destructive ? Colors.transparent : Nocturne.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: Nocturne.button.copyWith(
              color:
                  destructive ? Nocturne.textPrimary : Nocturne.textSecondary,
            ),
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
        child: Stack(
          children: [
            const _VaultBackdrop(),
            Padding(
              padding: const EdgeInsets.all(Nocturne.space7),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF090A0C),
                  borderRadius: BorderRadius.circular(Nocturne.radiusXl),
                  border: Border.all(
                    color: memory.isPinned
                        ? Nocturne.borderStrong
                        : Nocturne.borderSubtle,
                  ),
                  boxShadow: Nocturne.elevationHigh,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Nocturne.space8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Nocturne.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: onTogglePin,
                            tooltip: memory.isPinned ? 'Unpin' : 'Pin',
                            icon: Icon(
                              memory.isPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              color: memory.isPinned
                                  ? Nocturne.accentWarm
                                  : Nocturne.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Nocturne.space7),
                      Text(
                        _memoryTitle(memory),
                        style: Nocturne.label.copyWith(
                          color: memory.isPinned
                              ? Nocturne.accentWarm
                              : Nocturne.textSecondary,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: Nocturne.space4),
                      Text(_formatDate(memory.createdAt),
                          style: Nocturne.bodySm),
                      const SizedBox(height: Nocturne.space8),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Text(
                            memory.memoryText,
                            style: Nocturne.bodyXl.copyWith(height: 1.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
