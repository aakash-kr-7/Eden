// ═══════════════════════════════════════════════════════════════════
// FILE: screens/settings_screen.dart
// PURPOSE: User preferences, relationship info, privacy controls, account.
// CONTEXT: Accessed from chat screen via subtle settings icon.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/eden_theme.dart';
import '../theme/eden_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/eden_button.dart';
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
  String _relationshipStage = 'new';
  int _daysTogether = 0;
  int _memoryCount = 0;

  // Preferences
  String _communicationPace = 'balanced';
  bool _notifProactive = true;
  bool _notifFollowUp = true;
  bool _notifAnniversaries = true;
  bool _notifAbsenceCheck = true;

  // Account
  String _displayName = '';
  bool _isEditingName = false;
  final _nameController = TextEditingController();

  // Delete inline confirmation
  bool _isDeleteExpanded = false;
  final _deleteConfirmController = TextEditingController();
  bool _isDeleteActive = false;

  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    
    _deleteConfirmController.addListener(() {
      final matches = _deleteConfirmController.text.trim() == 'delete';
      if (_isDeleteActive != matches) {
        setState(() {
          _isDeleteActive = matches;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProfileData());
  }

  @override
  void dispose() {
    _bgController.dispose();
    _nameController.dispose();
    _deleteConfirmController.dispose();
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
        final primary = await apiService.getRelationshipSummary();
        final notifPrefs = await apiService.getNotificationPreferences();

        setState(() {
          _displayName = user['display_name'] ?? user['preferred_name'] ?? 'User';
          _nameController.text = _displayName;

          _partnerName = partner['name'] ?? 'Companion';
          _relationshipStage = primary.stage;
          _daysTogether = primary.daysTogether;
          _memoryCount = primary.totalMemories;

          _communicationPace = profile['preferences']?['proactive_cadence'] ?? 'balanced';
          
          _notifProactive = notifPrefs['proactive'] ?? true;
          _notifFollowUp = notifPrefs['emotional_followup'] ?? true;
          _notifAnniversaries = notifPrefs['anniversaries'] ?? true;
          _notifAbsenceCheck = notifPrefs['absence_check'] ?? true;

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

  Future<void> _updateNotifPrefs({
    bool? proactive,
    bool? emotionalFollowup,
    bool? anniversaries,
  }) async {
    HapticFeedback.selectionClick();
    final nextProactive = proactive ?? _notifProactive;
    final nextFollowUp = emotionalFollowup ?? _notifFollowUp;
    final nextAnniversaries = anniversaries ?? _notifAnniversaries;
    
    final previousProactive = _notifProactive;
    final previousFollowUp = _notifFollowUp;
    final previousAnniversaries = _notifAnniversaries;

    setState(() {
      _notifProactive = nextProactive;
      _notifFollowUp = nextFollowUp;
      _notifAnniversaries = nextAnniversaries;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateNotificationPreferences(
        proactive: nextProactive,
        emotionalFollowup: nextFollowUp,
        anniversaries: nextAnniversaries,
        absenceCheck: _notifAbsenceCheck,
      );
    } catch (e) {
      setState(() {
        _notifProactive = previousProactive;
        _notifFollowUp = previousFollowUp;
        _notifAnniversaries = previousAnniversaries;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update notification preferences: $e'), backgroundColor: EdenTheme.destructive),
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

  Future<void> _handleDeleteAccount() async {
    HapticFeedback.heavyImpact();
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

  Future<void> _handleExportData() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final apiService = ref.read(apiServiceProvider);
      final userId = ref.read(authServiceProvider).currentUserId ?? '';
      final data = await apiService.exportData(userId);
      
      setState(() => _isLoading = false);

      if (mounted) {
        final jsonString = const JsonEncoder.withIndent('  ').convert(data);
        await Share.share(jsonString, subject: 'My Eden Data Export');
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
              backgroundColor: EdenColors.edenSurface,
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
                        color: EdenColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      content,
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
                              'Cancel',
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
                                    border: Border.all(color: EdenColors.semanticError.withValues(alpha: 0.3), width: 0.8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      confirmLabel,
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
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: EdenColors.edenSurface,
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(EdenColors.edenIris)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: EdenColors.edenSurface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, style: GoogleFonts.plusJakartaSans(color: EdenColors.semanticError)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _fetchProfileData,
                child: Text('retry', style: GoogleFonts.jost(color: EdenColors.edenGold)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: EdenColors.edenSurface,
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
                        EdenColors.presenceBlue.withValues(alpha: 0.03 + (pulse * 0.015)),
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
                          EdenColors.warmViolet.withValues(alpha: 0.02 + ((1 - pulse) * 0.015)),
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
                // Header (Functional, no CormorantGaramond, PlusJakartaSans Bold, 24sp)
                Text(
                  'Settings',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: EdenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),

                // Section 1: "your connection"
                _buildSectionLabel('your connection'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      SettingsRow(
                        label: 'Partner',
                        right: Text(
                          _partnerName,
                          style: GoogleFonts.plusJakartaSans(color: EdenColors.textSecondary),
                        ),
                      ),
                      _buildDivider(),
                      SettingsRow(
                        label: 'Relationship stage',
                        right: _buildStagePill(_relationshipStage),
                      ),
                      _buildDivider(),
                      SettingsRow(
                        label: 'Days together',
                        right: Text(
                          '$_daysTogether days',
                          style: GoogleFonts.plusJakartaSans(color: EdenColors.textSecondary),
                        ),
                      ),
                      _buildDivider(),
                      SettingsRow(
                        label: 'Memory count',
                        onTap: () => context.push('/memories').then((_) => _fetchProfileData()),
                        right: Row(
                          children: [
                            Text(
                              '$_memoryCount items',
                              style: GoogleFonts.plusJakartaSans(color: EdenColors.textSecondary),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: EdenColors.textTertiary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Section 2: "how you talk"
                _buildSectionLabel('how you talk'),
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
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: EdenColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildSegmentedPaceSelector(),
                          ],
                        ),
                      ),
                      _buildDivider(),
                      _buildToggleRow(
                        title: 'Proactive',
                        value: _notifProactive,
                        onChanged: (val) => _updateNotifPrefs(proactive: val),
                      ),
                      _buildDivider(),
                      _buildToggleRow(
                        title: 'Follow-ups',
                        value: _notifFollowUp,
                        onChanged: (val) => _updateNotifPrefs(emotionalFollowup: val),
                      ),
                      _buildDivider(),
                      _buildToggleRow(
                        title: 'Anniversaries',
                        value: _notifAnniversaries,
                        onChanged: (val) => _updateNotifPrefs(anniversaries: val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Section 3: "your data"
                _buildSectionLabel('your data'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      SettingsRow(
                        label: 'Your memories',
                        onTap: () => context.push('/memories').then((_) => _fetchProfileData()),
                        right: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: EdenColors.textTertiary),
                      ),
                      _buildDivider(),
                      SettingsRow(
                        label: 'Export my data',
                        onTap: _handleExportData,
                        right: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: EdenColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Section 4: "account"
                _buildSectionLabel('account'),
                _buildSettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Display Name Editable Row
                      _buildEditableNameRow(),
                      _buildDivider(),
                      
                      // Delete everything expanding row
                      _buildDeleteEverythingRow(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Sign out button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: EdenSecondaryButton(
                    text: 'Sign out',
                    textColor: EdenColors.textSecondary,
                    onTap: _handleSignOut,
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
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 12),
      child: Text(
        label,
        style: GoogleFonts.jost(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: EdenColors.textSecondary.withValues(alpha: 0.65),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    return GlassCard(
      child: child,
    );
  }

  Widget _buildStagePill(String stage) {
    Color color = EdenColors.textTertiary;
    String label = stage.toLowerCase();
    
    if (label == 'familiar' || label == 'warming' || label == 'settled') {
      color = EdenColors.edenSage;
    } else if (label == 'close') {
      color = EdenColors.edenIris;
    } else if (label == 'bonded' || label == 'intimate') {
      color = EdenColors.edenBlush;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999), // radius-pill
        border: Border.all(color: color.withValues(alpha: 0.20), width: 1.0),
      ),
      child: Text(
        label,
        style: GoogleFonts.jost(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSegmentedPaceSelector() {
    final paceOptions = [
      {'label': 'Slow', 'value': 'gentle'},
      {'label': 'Balanced', 'value': 'balanced'},
      {'label': 'Quick', 'value': 'frequent'},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: EdenColors.glassLight,
        borderRadius: BorderRadius.circular(14), // radius-md
        border: Border.all(color: EdenColors.glassBorder, width: 1.0),
      ),
      child: Row(
        children: paceOptions.map((opt) {
          final isSelected = _communicationPace == opt['value'];
          return Expanded(
            child: GestureDetector(
              onTap: () => _updateCommunicationPace(opt['value']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? EdenColors.edenIrisDim : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? EdenColors.edenIris : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    opt['label']!,
                    style: GoogleFonts.jost(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                      color: isSelected ? EdenColors.textAccent : EdenColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: EdenColors.textPrimary,
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: EdenColors.edenIris,
            activeTrackColor: EdenColors.edenIrisDim,
            inactiveThumbColor: EdenColors.textSecondary,
            inactiveTrackColor: Colors.transparent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildEditableNameRow() {
    if (_isEditingName) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                style: GoogleFonts.plusJakartaSans(color: EdenColors.textPrimary, fontSize: 14),
                cursorColor: EdenColors.edenIris,
                autofocus: true,
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: EdenColors.edenIris, width: 0.8),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: EdenColors.edenIris, width: 1.2),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, color: EdenColors.semanticSuccess, size: 20),
              onPressed: _updateDisplayName,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: EdenColors.semanticError, size: 20),
              onPressed: () {
                setState(() {
                  _nameController.text = _displayName;
                  _isEditingName = false;
                });
              },
            ),
          ],
        ),
      );
    }

    return SettingsRow(
      label: 'Display name',
      onTap: () => setState(() => _isEditingName = true),
      right: Row(
        children: [
          Text(
            _displayName,
            style: GoogleFonts.plusJakartaSans(color: EdenColors.textSecondary),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_outlined, size: 14, color: EdenColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildDeleteEverythingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isDeleteExpanded = !_isDeleteExpanded;
              if (!_isDeleteExpanded) {
                _deleteConfirmController.clear();
              }
            });
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Delete everything',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: EdenColors.textSecondary,
                  ),
                ),
                Icon(
                  _isDeleteExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: EdenColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_isDeleteExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will permanently erase all settings, connection details, and conversation history. This cannot be undone.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: EdenColors.semanticError.withValues(alpha: 0.8),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Type "delete" below to confirm:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: EdenColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _deleteConfirmController,
                  style: GoogleFonts.plusJakartaSans(color: EdenColors.textPrimary, fontSize: 14),
                  cursorColor: EdenColors.semanticError,
                  decoration: InputDecoration(
                    hintText: 'delete',
                    hintStyle: GoogleFonts.plusJakartaSans(color: EdenColors.textTertiary, fontSize: 14),
                    filled: true,
                    fillColor: EdenColors.edenVoid,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: EdenColors.semanticError, width: 1.0),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: EdenColors.edenRim, width: 1.0),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _isDeleteActive ? _handleDeleteAccount : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isDeleteActive ? EdenColors.semanticError : EdenColors.semanticError.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isDeleteActive ? EdenColors.semanticError : EdenColors.semanticError.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Erase All Data',
                        style: GoogleFonts.jost(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _isDeleteActive ? Colors.white : EdenColors.semanticError.withValues(alpha: 0.4),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 0.6,
      width: double.infinity,
      color: EdenColors.glassBorder,
    );
  }
}

class SettingsRow extends StatefulWidget {
  final String label;
  final Widget? right;
  final VoidCallback? onTap;
  final bool isDestructive;

  const SettingsRow({
    super.key,
    required this.label,
    this.right,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _isTapped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _isTapped = true) : null,
      onTapUp: widget.onTap != null ? (_) {
        setState(() => _isTapped = false);
        HapticFeedback.lightImpact();
        widget.onTap!();
      } : null,
      onTapCancel: widget.onTap != null ? () => setState(() => _isTapped = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 56.0,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        color: _isTapped ? EdenColors.glassLight : Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: widget.isDestructive ? EdenColors.semanticError : EdenColors.textPrimary,
              ),
            ),
            if (widget.right != null) widget.right!,
          ],
        ),
      ),
    );
  }
}
