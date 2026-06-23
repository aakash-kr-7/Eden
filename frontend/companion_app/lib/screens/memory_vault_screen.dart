import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/eden_theme.dart';
import '../services/biometric_service.dart';
import '../models/models.dart';
import '../main.dart';

class MemoryVaultScreen extends ConsumerStatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  ConsumerState<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends ConsumerState<MemoryVaultScreen> {
  final List<Memory> _memories = [];
  bool _isLoading = true;
  bool _isLocked = false;
  String _pinInput = '';
  String? _errorMessage;

  String _selectedType = 'all';
  String _selectedSort = 'recent'; // 'recent' | 'salience'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVaultLock());
  }

  Future<void> _checkVaultLock() async {
    final enabled = await BiometricService.isVaultEnabled();
    if (!enabled) {
      _loadMemories();
      return;
    }

    // Try native biometrics first
    final canBio = await BiometricService.canAuthenticate();
    if (canBio) {
      final success = await BiometricService.authenticate();
      if (success) {
        _loadMemories();
        return;
      }
    }

    // Fallback to PIN keypad lock state
    setState(() {
      _isLocked = true;
      _isLoading = false;
    });
  }

  Future<void> _loadMemories() async {
    setState(() {
      _isLoading = true;
      _isLocked = false;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final typeFilter = _selectedType == 'all' ? null : _selectedType;
      final list = await apiService.getMemories(type: typeFilter, sort: _selectedSort);
      
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
          _errorMessage = 'failed to load memories. try again.';
        });
      }
    }
  }

  Future<void> _handlePinKeyPress(String digit) async {
    HapticFeedback.lightImpact();
    if (_pinInput.length >= 4) return;

    setState(() {
      _pinInput += digit;
    });

    if (_pinInput.length == 4) {
      final correct = await BiometricService.verifyVaultPin(_pinInput);
      if (correct) {
        _loadMemories();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _pinInput = '';
          _errorMessage = 'Incorrect PIN. Try again.';
        });
      }
    }
  }

  void _handlePinBackspace() {
    if (_pinInput.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _pinInput = _pinInput.substring(0, _pinInput.length - 1);
        _errorMessage = null;
      });
    }
  }

  Future<void> _togglePin(Memory memory) async {
    HapticFeedback.lightImpact();
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.pinMemory(memory.id);
      _loadMemories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pin memory: $e'),
            backgroundColor: EdenTheme.destructive,
          ),
        );
      }
    }
  }

  Future<void> _deleteMemory(Memory memory) async {
    HapticFeedback.mediumImpact();
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EdenTheme.bgSurface,
        title: const Text('Delete Memory', style: EdenTheme.displaySmall),
        content: const Text(
          'Are you sure you want to forget this? This cannot be undone.',
          style: EdenTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Forget', style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.destructive)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteMemory(memory.id);
      
      if (mounted) {
        setState(() {
          _memories.removeWhere((m) => m.id == memory.id);
        });
      }
    } catch (e) {
      if (mounted) {
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
    if (_isLocked) {
      return _buildKeypadLockScreen();
    }

    return Scaffold(
      backgroundColor: EdenTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Memory Vault'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFiltersAndSorting(),
            Expanded(child: _buildMemoriesList()),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadLockScreen() {
    return Scaffold(
      backgroundColor: EdenTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 48, color: EdenTheme.accentPrimary),
            const SizedBox(height: 24),
            const Text(
              'Vault Locked',
              style: EdenTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your 4-digit PIN to access memories.',
              style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textSecondary),
            ),
            const SizedBox(height: 36),
            // Pin indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final hasDigit = index < _pinInput.length;
                return Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasDigit ? EdenTheme.accentPrimary : Colors.transparent,
                    border: Border.all(color: EdenTheme.accentPrimary, width: 1.5),
                  ),
                );
              }),
            ),
            const SizedBox(height: 48),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: EdenTheme.bodySmall.copyWith(color: EdenTheme.destructive),
              ),
              const SizedBox(height: 24),
            ],
            // Keypad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['1', '2', '3'].map((d) => _buildKeypadButton(d)).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['4', '5', '6'].map((d) => _buildKeypadButton(d)).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['7', '8', '9'].map((d) => _buildKeypadButton(d)).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back to previous screen
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: EdenTheme.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      _buildKeypadButton('0'),
                      IconButton(
                        icon: const Icon(Icons.backspace_outlined, color: EdenTheme.textSecondary),
                        onPressed: _handlePinBackspace,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadButton(String digit) {
    return GestureDetector(
      onTap: () => _handlePinKeyPress(digit),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: EdenTheme.bgSurface,
          border: Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.08)),
        ),
        child: Center(
          child: Text(
            digit,
            style: EdenTheme.displaySmall,
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersAndSorting() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
      child: Column(
        children: [
          Row(
            children: [
              _buildFilterChip('all', 'All'),
              const SizedBox(width: 8),
              _buildFilterChip('fact', 'Facts'),
              const SizedBox(width: 8),
              _buildFilterChip('feeling', 'Feelings'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_memories.length} moments remembered',
                style: EdenTheme.bodySmall.copyWith(color: EdenTheme.textSecondary),
              ),
              DropdownButton<String>(
                value: _selectedSort,
                dropdownColor: EdenTheme.bgSurface,
                underline: const SizedBox(),
                icon: const Icon(Icons.swap_vert_rounded, size: 16, color: EdenTheme.accentSecondary),
                style: EdenTheme.bodySmall.copyWith(color: EdenTheme.accentSecondary, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'recent', child: Text('Sort by Recent')),
                  DropdownMenuItem(value: 'salience', child: Text('Sort by Salience')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedSort = val);
                    _loadMemories();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final bool isSelected = _selectedType == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedType = value);
        _loadMemories();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? EdenTheme.accentPrimary : EdenTheme.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? EdenTheme.accentPrimary : EdenTheme.textSecondary.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: EdenTheme.bodySmall.copyWith(
            color: isSelected ? EdenTheme.bgPrimary : EdenTheme.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMemoriesList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(EdenTheme.accentPrimary)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.destructive)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMemories,
              style: ElevatedButton.styleFrom(backgroundColor: EdenTheme.accentPrimary),
              child: const Text('Retry', style: TextStyle(color: EdenTheme.bgPrimary)),
            )
          ],
        ),
      );
    }

    if (_memories.isEmpty) {
      return Center(
        child: Text(
          'no memories recorded yet.\nkeep talking to build your shared vault.',
          textAlign: TextAlign.center,
          style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textSecondary, fontStyle: FontStyle.italic),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final memory = _memories[index];
        final formattedDate = DateFormat('MMM d, y').format(memory.createdAt);
        final bool isPinned = memory.salience > 0.9;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EdenTheme.bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.08), width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: EdenTheme.bgElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      memory.memoryType.toUpperCase(),
                      style: EdenTheme.labelSmall.copyWith(fontSize: 8, color: EdenTheme.accentSecondary),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 16,
                          color: isPinned ? EdenTheme.accentPrimary : EdenTheme.textSecondary,
                        ),
                        onPressed: () => _togglePin(memory),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: EdenTheme.textSecondary),
                        onPressed: () => _deleteMemory(memory),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                memory.content,
                style: EdenTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedDate,
                    style: EdenTheme.labelSmall,
                  ),
                  if (memory.tags.isNotEmpty)
                    Text(
                      '#${memory.tags.join(" #")}',
                      style: EdenTheme.labelSmall.copyWith(color: EdenTheme.accentPrimary.withValues(alpha: 0.7)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
