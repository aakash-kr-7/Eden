import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_theme.dart';
import '../main.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;

  // Connection data
  String _partnerName = '';
  String _relationshipStage = '';
  int _daysTogether = 0;
  int _memoryCount = 0;

  // Preferences
  String _communicationPace = 'balanced';
  bool _allowProactive = true;
  bool _allowPush = true;

  // Account
  String _displayName = '';
  String _email = '';
  bool _isEditingName = false;
  final _nameController = TextEditingController();

  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProfileData());
  }

  @override
  void dispose() {
    _bgController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfileData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final profile = await apiService.getProfile();
      
      if (mounted) {
        final user = profile['user'] ?? {};
        final partner = profile['partner'] ?? {};
        final prefs = profile['preferences'] ?? {};
        final primary = await apiService.getRelationshipSummary();

        setState(() {
          _displayName = user['display_name'] ?? user['preferred_name'] ?? 'User';
          _email = user['email'] ?? '';
          _nameController.text = _displayName;

          _partnerName = partner['name'] ?? 'Companion';
          _relationshipStage = primary.stage;
          _daysTogether = primary.daysTogether;
          _memoryCount = primary.totalMemories;

          _communicationPace = prefs['proactive_cadence'] ?? 'balanced';
          _allowProactive = prefs['allow_proactive_messages'] == 1 || prefs['allow_proactive_messages'] == true;
          _allowPush = prefs['allow_push_notifications'] == 1 || prefs['allow_push_notifications'] == true;

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'failed to load settings';
        });
      }
    }
  }

  Future<void> _updateDisplayName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == _displayName) {
      setState(() => _isEditingName = false);
      return;
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateProfile(displayName: newName);
      setState(() {
        _displayName = newName;
        _isEditingName = false;
      });
      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update name: $e'), backgroundColor: EdenTheme.destructive),
        );
      }
    }
  }

  Future<void> _updateCommunicationPace(String pace) async {
    if (pace == _communicationPace) return;
    
    // Optimistic state
    final previous = _communicationPace;
    setState(() => _communicationPace = pace);
    HapticFeedback.selectionClick();

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateProfile(communicationPace: pace);
    } catch (e) {
      if (mounted) {
        setState(() => _communicationPace = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update pace: $e'), backgroundColor: EdenTheme.destructive),
        );
      }
    }
  }

  Future<void> _updateToggles({bool? allowProactive, bool? allowPush}) async {
    HapticFeedback.selectionClick();
    
    final originalProactive = _allowProactive;
    final originalPush = _allowPush;

    setState(() {
      if (allowProactive != null) _allowProactive = allowProactive;
      if (allowPush != null) _allowPush = allowPush;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateProfile(
        allowProactive: allowProactive,
        allowPush: allowPush,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _allowProactive = originalProactive;
          _allowPush = originalPush;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update preferences: $e'), backgroundColor: EdenTheme.destructive),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    HapticFeedback.mediumImpact();
    final bool? confirm = await _showOverlayConfirm(
      title: 'Sign out?',
      content: 'You will need to sign in again to reconnect with $_partnerName.',
      confirmLabel: 'Sign out',
    );

    if (confirm == true && mounted) {
      await ref.read(authServiceProvider).signOut();
      if (!mounted) return;
      context.go('/');
    }
  }

  Future<void> _handleClearMemories() async {
    HapticFeedback.mediumImpact();
    final bool? confirm = await _showOverlayConfirm(
      title: 'Clear all memories?',
      content: 'This will erase everything $_partnerName remembers about you. This process is permanent and cannot be undone.',
      confirmLabel: 'Delete All',
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final apiService = ref.read(apiServiceProvider);
        await apiService.deleteAllMemories();
        await _fetchProfileData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Memories cleared.'), backgroundColor: EdenTheme.success),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear memories: $e'), backgroundColor: EdenTheme.destructive),
          );
        }
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    HapticFeedback.heavyImpact();
    
    // Multi-step confirmation
    // Step 1: General warning
    final bool? step1 = await _showOverlayConfirm(
      title: 'Delete your account?',
      content: 'This will completely destroy your profile and all pairings. $_partnerName and any other companions will forget you entirely. This is irreversible.',
      confirmLabel: 'Delete account',
    );

    if (step1 != true) return;
    if (!mounted) return;

    // Step 2: Verification typing check
    final confirmController = TextEditingController();
    final bool? step2 = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'verify_delete',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final text = confirmController.text.trim();
            final isEnabled = text == 'DELETE';

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
                          'Irreversible Action',
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: EdenTheme.destructive,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Please type "DELETE" in capital letters below to permanently destroy your connection database.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: EdenTheme.textSecondary,
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: confirmController,
                          style: GoogleFonts.plusJakartaSans(color: EdenTheme.textPrimary, fontSize: 15),
                          cursorColor: EdenTheme.destructive,
                          textAlign: TextAlign.center,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setModalState(() {}),
                          decoration: InputDecoration(
                            hintText: 'DELETE',
                            hintStyle: GoogleFonts.plusJakartaSans(color: EdenTheme.textTertiary, fontSize: 15),
                            filled: true,
                            fillColor: EdenTheme.bgPrimary.withValues(alpha: 0.4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: Text(
                                  'Cancel',
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
                                  color: isEnabled ? EdenTheme.destructive : EdenTheme.destructive.withValues(alpha: 0.1),
                                  child: InkWell(
                                    onTap: isEnabled ? () => Navigator.of(context).pop(true) : null,
                                    child: Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isEnabled 
                                              ? EdenTheme.destructive 
                                              : EdenTheme.destructive.withValues(alpha: 0.15), 
                                          width: 0.8
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Erase All',
                                          style: GoogleFonts.jost(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: isEnabled ? EdenTheme.bgPrimary : EdenTheme.destructive.withValues(alpha: 0.4),
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
          }
        );
      },
    );

    if (step2 == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final apiService = ref.read(apiServiceProvider);
        await apiService.deleteAccount();
        await ref.read(authServiceProvider).signOut();
        if (mounted) {
          context.go('/');
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete account: $e'), backgroundColor: EdenTheme.destructive),
          );
        }
      }
    }
  }

  Future<void> _handleExportData() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final apiService = ref.read(apiServiceProvider);
      final userId = ref.read(authServiceProvider).currentUserId ?? '';
      final data = await apiService.exportData(userId);
      
      setState(() => _isLoading = false);

      if (mounted) {
        // Show exported JSON data modal with copy option
        final jsonString = const JsonEncoder.withIndent('  ').convert(data);
        _showExportViewer(jsonString);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to compile export: $e'), backgroundColor: EdenTheme.destructive),
        );
      }
    }
  }

  void _showExportViewer(String jsonString) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'export_viewer',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: Dialog(
              backgroundColor: EdenTheme.bgSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Compiled Database',
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        color: EdenTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'All profile variables, preferences, messages, and memories formatted as raw JSON.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: EdenTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // JSON content container
                    Container(
                      height: 320,
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07080B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: EdenTheme.textPrimary.withValues(alpha: 0.05)),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          jsonString,
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 11,
                            color: EdenTheme.textPrimary.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Close',
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
                              color: EdenTheme.bgElevated,
                              child: InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: jsonString));
                                  HapticFeedback.lightImpact();
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copied database to clipboard.')),
                                  );
                                },
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: EdenTheme.textPrimary.withValues(alpha: 0.08), width: 0.8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Copy All',
                                      style: GoogleFonts.jost(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: EdenTheme.textPrimary,
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

  Future<bool?> _showOverlayConfirm({
    required String title,
    required String content,
    required String confirmLabel,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'overlay_confirm',
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
                      title,
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: EdenTheme.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      content,
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
                              'Cancel',
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
                                      confirmLabel,
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
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(EdenTheme.accentPrimary)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, style: GoogleFonts.plusJakartaSans(color: EdenTheme.destructive)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _fetchProfileData,
                child: Text('retry', style: GoogleFonts.jost(color: EdenTheme.accentSecondary)),
              ),
            ],
          ),
        ),
      );
    }

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
      body: Stack(
        children: [
          // Slow background breathe orbs
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                final pulse = _bgController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.6, -0.6 + (pulse * 0.1)),
                      radius: 1.4,
                      colors: [
                        EdenTheme.accentPrimary.withValues(alpha: 0.03 + (pulse * 0.015)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.6, 0.6 - (pulse * 0.1)),
                        radius: 1.5,
                        colors: [
                          EdenTheme.accentSecondary.withValues(alpha: 0.02 + ((1 - pulse) * 0.015)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              children: [
                // Display Name inline editor / Profile Area
                _buildEditableProfileHeader(),
                const SizedBox(height: 36),

                // Connection details (display-only)
                _buildSectionLabel('Your connection'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildDisplayTile('Partner', _partnerName),
                      _buildDivider(),
                      _buildDisplayTile('Relationship stage', _relationshipStage),
                      _buildDivider(),
                      _buildDisplayTile('Days together', '$_daysTogether days'),
                      _buildDivider(),
                      _buildDisplayTile('Memory count', '$_memoryCount items'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Preferences
                _buildSectionLabel('Preferences'),
                _buildSettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Communication pace',
                              style: GoogleFonts.jost(fontSize: 14, color: EdenTheme.textPrimary),
                            ),
                            const SizedBox(height: 12),
                            _buildPaceChips(),
                          ],
                        ),
                      ),
                      _buildDivider(),
                      _buildSwitchTile(
                        title: 'Proactive outreach',
                        subtitle: 'Allow partner to check-in on their own timeline',
                        value: _allowProactive,
                        onChanged: (val) => _updateToggles(allowProactive: val),
                      ),
                      _buildDivider(),
                      _buildSwitchTile(
                        title: 'Push notifications',
                        subtitle: 'Get system notification alerts',
                        value: _allowPush,
                        onChanged: (val) => _updateToggles(allowPush: val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Privacy
                _buildSectionLabel('Privacy'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildActionTile(
                        title: 'Your memories',
                        subtitle: 'Browse the vault of shared moments',
                        onTap: () {
                          context.push('/memories').then((_) => _fetchProfileData());
                        },
                      ),
                      _buildDivider(),
                      _buildActionTile(
                        title: 'Delete all memories',
                        subtitle: 'Clear connection facts and knowledge history',
                        onTap: _handleClearMemories,
                        destructive: true,
                      ),
                      _buildDivider(),
                      _buildActionTile(
                        title: 'Export my data',
                        subtitle: 'Extract database values as raw JSON',
                        onTap: _handleExportData,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Account
                _buildSectionLabel('Account'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildActionTile(
                        title: 'Sign out',
                        onTap: _handleSignOut,
                      ),
                      _buildDivider(),
                      _buildActionTile(
                        title: 'Delete account',
                        subtitle: 'Permanently destroy profile and connection pairing data',
                        onTap: _handleDeleteAccount,
                        destructive: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label,
        style: GoogleFonts.jost(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: EdenTheme.textSecondary.withValues(alpha: 0.65),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: EdenTheme.bgSurface.withValues(alpha: 0.40),
        border: Border.all(color: EdenTheme.textPrimary.withValues(alpha: 0.04), width: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }

  Widget _buildEditableProfileHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: EdenTheme.bgSurface,
          child: Text(
            _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 26,
              fontWeight: FontWeight.w400,
              color: EdenTheme.accentSecondary,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _isEditingName
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: GoogleFonts.plusJakartaSans(color: EdenTheme.textPrimary, fontSize: 16),
                        cursorColor: EdenTheme.accentPrimary,
                        autofocus: true,
                        decoration: const InputDecoration(
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: EdenTheme.accentPrimary, width: 0.8),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: EdenTheme.accentPrimary, width: 1.2),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: EdenTheme.success, size: 20),
                      onPressed: _updateDisplayName,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: EdenTheme.destructive, size: 20),
                      onPressed: () {
                        setState(() {
                          _nameController.text = _displayName;
                          _isEditingName = false;
                        });
                      },
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _displayName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: EdenTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() => _isEditingName = true);
                          },
                          child: Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: EdenTheme.textSecondary.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _email,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: EdenTheme.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDisplayTile(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: EdenTheme.textSecondary),
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: EdenTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaceChips() {
    final options = ['gentle', 'balanced', 'frequent'];
    return Row(
      children: options.map((opt) {
        final isSelected = _communicationPace == opt;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: GestureDetector(
              onTap: () => _updateCommunicationPace(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? EdenTheme.bgSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? EdenTheme.textPrimary.withValues(alpha: 0.08) : Colors.transparent,
                    width: 0.8,
                  ),
                ),
                child: Center(
                  child: Text(
                    opt,
                    style: GoogleFonts.jost(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.w300,
                      color: isSelected ? EdenTheme.textPrimary : EdenTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, color: EdenTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: EdenTheme.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            activeColor: EdenTheme.accentPrimary,
            activeTrackColor: EdenTheme.accentPrimary.withValues(alpha: 0.3),
            inactiveThumbColor: EdenTheme.textSecondary,
            inactiveTrackColor: EdenTheme.bgPrimary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final titleColor = destructive ? EdenTheme.destructive : EdenTheme.textPrimary;
    final subColor = destructive 
        ? EdenTheme.destructive.withValues(alpha: 0.6) 
        : EdenTheme.textSecondary.withValues(alpha: 0.6);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: destructive ? FontWeight.w500 : FontWeight.w400,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: subColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: destructive ? EdenTheme.destructive.withValues(alpha: 0.5) : EdenTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 0.6,
      width: double.infinity,
      color: EdenTheme.textPrimary.withValues(alpha: 0.04),
    );
  }
}
