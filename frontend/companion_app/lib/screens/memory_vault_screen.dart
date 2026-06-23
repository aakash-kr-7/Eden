import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_theme.dart';
import '../models/models.dart';
import '../main.dart';

class MemoryVaultScreen extends ConsumerStatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  ConsumerState<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends ConsumerState<MemoryVaultScreen> with SingleTickerProviderStateMixin {
  final List<Memory> _memories = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _partnerName;

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

  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeScreen());
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadPartnerName();
    await _loadMemories();
  }

  Future<void> _loadPartnerName() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final profile = await apiService.getProfile();
      if (mounted) {
        setState(() {
          _partnerName = profile['partner']?['name'] ?? 'Companion';
        });
      }
    } catch (e) {
      debugPrint('Failed to load partner details: $e');
    }
  }

  Future<void> _loadMemories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      // Map category labels to types expected by API
      String? backendType;
      if (_selectedCategory != 'All') {
        // Map singular lowercase forms
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
        backendType = map[_selectedCategory];
      }

      final list = await apiService.getMemories(type: backendType, sort: 'recent');
      
      if (mounted) {
        setState(() {
          _memories.clear();
          _memories.addAll(list);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'failed to retrieve memories';
        });
      }
    }
  }

  Future<void> _togglePin(Memory memory) async {
    HapticFeedback.lightImpact();
    
    // Optimistic UI update
    final int idx = _memories.indexWhere((m) => m.id == memory.id);
    if (idx == -1) return;

    final originalSalience = memory.salience;
    // Pinned status is inferred from salience > 0.9 or can be set directly.
    final updatedMemory = Memory(
      id: memory.id,
      content: memory.content,
      memoryType: memory.memoryType,
      // If currently pinned, lower salience to unpin; if not, raise it to pin.
      salience: originalSalience > 0.9 ? 0.5 : 1.0,
      emotionalValence: memory.emotionalValence,
      tags: memory.tags,
      isPhysical: memory.isPhysical,
      createdAt: memory.createdAt,
    );

    setState(() {
      _memories[idx] = updatedMemory;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.pinMemory(memory.id);
      // Reload to ensure DB state matches
      _loadMemories();
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          _memories[idx] = memory;
        });
      }
    }
  }

  Future<void> _deleteMemory(Memory memory) async {
    HapticFeedback.mediumImpact();
    
    final bool? confirm = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'confirm_delete',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: Dialog(
              backgroundColor: EdenTheme.bgSurface,
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
                        color: EdenTheme.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This moment will disappear from their presence and context forever.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: EdenTheme.textSecondary,
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
                                color: EdenTheme.textSecondary,
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
                              color: EdenTheme.destructive.withValues(alpha: 0.15),
                              child: InkWell(
                                onTap: () => Navigator.of(context).pop(true),
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: EdenTheme.destructive.withValues(alpha: 0.3), width: 0.8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Forget',
                                      style: GoogleFonts.jost(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: EdenTheme.destructive,
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

    if (confirm != true) return;

    // Optimistic UI delete
    final originalIdx = _memories.indexWhere((m) => m.id == memory.id);
    if (originalIdx != -1) {
      setState(() {
        _memories.removeAt(originalIdx);
      });
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteMemory(memory.id);
    } catch (e) {
      // Revert optimistic delete on error
      if (mounted && originalIdx != -1) {
        _loadMemories();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to forget memory: $e'),
            backgroundColor: EdenTheme.destructive,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleName = _partnerName ?? 'Companion';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Intimate Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text(
                'What $titleName remembers',
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: EdenTheme.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ),

            // Horizontal Category Filter Row
            _buildCategoryRow(),

            // Memory Content Area
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildMainContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: _categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: GestureDetector(
              onTap: () {
                if (_selectedCategory != cat) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedCategory = cat;
                  });
                  _loadMemories();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? EdenTheme.bgSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? EdenTheme.textPrimary.withValues(alpha: 0.08) : Colors.transparent,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  cat,
                  style: GoogleFonts.jost(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w300,
                    color: isSelected ? EdenTheme.textPrimary : EdenTheme.textSecondary.withValues(alpha: 0.7),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return _buildSkeletonLoader();
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: GoogleFonts.plusJakartaSans(color: EdenTheme.destructive, fontSize: 15),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _initializeScreen,
                child: Text(
                  'retry',
                  style: GoogleFonts.jost(color: EdenTheme.accentSecondary, letterSpacing: 1.0),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_memories.isEmpty) {
      return Center(
        key: const ValueKey('empty_vault'),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'Nothing here yet. Memories appear as your relationship grows.',
            textAlign: TextAlign.center,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 18,
              fontWeight: FontWeight.w300,
              color: EdenTheme.textSecondary.withValues(alpha: 0.65),
              height: 1.45,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      key: ValueKey('memory_list_$_selectedCategory'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final memory = _memories[index];
        return _buildMemoryCard(memory);
      },
    );
  }

  Widget _buildMemoryCard(Memory memory) {
    final formattedDate = DateFormat('MMMM d, y').format(memory.createdAt);
    final isPinned = memory.salience > 0.9;

    return Dismissible(
      key: Key(memory.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: EdenTheme.destructive.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: EdenTheme.destructive,
          size: 22,
        ),
      ),
      confirmDismiss: (direction) async {
        await _deleteMemory(memory);
        return false; // Let the state handling inside _deleteMemory remove the item if confirmed
      },
      child: GestureDetector(
        onLongPress: () => _togglePin(memory),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Color(0x0F8A8799), // extremely subtle bottom divider line instead of outer card borders
                width: 0.8,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Memory text
              Text(
                memory.content,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: EdenTheme.textPrimary.withValues(alpha: 0.9),
                  height: 1.48,
                ),
              ),
              const SizedBox(height: 12),
              
              // Meta Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Type label in text-tertiary
                  Text(
                    memory.memoryType.toLowerCase(),
                    style: GoogleFonts.jost(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: EdenTheme.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Dot separator
                  Container(
                    width: 2.5,
                    height: 2.5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: EdenTheme.textTertiary,
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Date in text-tertiary
                  Text(
                    formattedDate,
                    style: GoogleFonts.jost(
                      fontSize: 11,
                      color: EdenTheme.textTertiary,
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Pin Dot indicator
                  if (isPinned)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: EdenTheme.accentPrimary, // Small Presence Dot
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: 4,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            final double value = _shimmerController.value;
            final double opacity = 0.08 + (value * 0.08);
            return Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.only(bottom: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Color(0x0A8A8799),
                    width: 0.8,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 15,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: EdenTheme.textPrimary.withValues(alpha: opacity),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 15,
                    width: MediaQuery.of(context).size.width * 0.7,
                    decoration: BoxDecoration(
                      color: EdenTheme.textPrimary.withValues(alpha: opacity),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        height: 11,
                        width: 50,
                        decoration: BoxDecoration(
                          color: EdenTheme.textTertiary.withValues(alpha: opacity * 1.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        height: 11,
                        width: 70,
                        decoration: BoxDecoration(
                          color: EdenTheme.textTertiary.withValues(alpha: opacity * 1.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
