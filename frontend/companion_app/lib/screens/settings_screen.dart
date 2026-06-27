// FILE: screens/settings_screen.dart
// PURPOSE: Manages account, profile, and notification settings without backend contract changes.
// RESPONSIBILITIES: Render settings UI and forward mutations through existing services.
// NEVER: Contain backend rule rewrites or app bootstrap logic.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../theme/eden_colors.dart';
import '../theme/glass_theme.dart';
import '../theme/nocturne.dart';
import '../components/glass.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  String _partnerName = '';
  String _relationshipStage = 'new';
  int _daysTogether = 0;
  int _memoryCount = 0;

  String _communicationPace = 'balanced';
  bool _notifProactive = true;
  bool _notifFollowUp = true;
  bool _notifAnniversaries = true;
  bool _notifAbsenceCheck = true;

  String _displayName = '';
  bool _isEditingName = false;
  final _nameController = TextEditingController();

  bool _isDeleteExpanded = false;
  final _deleteConfirmController = TextEditingController();
  bool _isDeleteActive = false;

  @override
  void initState() {
    super.initState();
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
          _displayName =
              user['display_name'] ?? user['preferred_name'] ?? 'User';
          _nameController.text = _displayName;

          _partnerName = partner['name'] ?? 'Companion';
          _relationshipStage = primary.stage;
          _daysTogether = primary.daysTogether;
          _memoryCount = primary.totalMemories;

          _communicationPace =
              profile['preferences']?['proactive_cadence'] ?? 'balanced';

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
        _showSnack('Failed to update name: $e');
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
        _showSnack('Failed to update pace: $e');
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
        _showSnack('Failed to update notification preferences: $e');
      }
    }
  }

  Future<void> _handleSignOut() async {
    HapticFeedback.mediumImpact();
    final bool? confirm = await _showOverlayConfirm(
      title: 'Sign out?',
      content:
          'You will need to sign in again to reconnect with $_partnerName.',
      confirmLabel: 'Sign out',
    );

    if (confirm == true && mounted) {
      await ref.read(authServiceProvider).signOut();
      if (!mounted) return;
      context.go(AppRoute.boot);
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
        context.go(AppRoute.boot);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Failed to delete account: $e');
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
        _showSnack('Failed to compile export: $e');
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
      transitionDuration: Nocturne.durationStandard,
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: anim1, curve: Curves.easeOut),
              ),
              child: LiquidGlass.withOwnLayer(
                shape: GlassTheme.shape,
                settings: GlassTheme.prominent,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: _displayStyle(26),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(content,
                          style: _bodyStyle(14, color: Colors.white70),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text('Cancel',
                                  style: _bodyStyle(15, color: Colors.white70)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _GlassButton(
                              label: confirmLabel,
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
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Nocturne.bgElevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: FakeGlass(
            shape: LiquidOval(),
            settings: GlassTheme.button,
            child: Padding(
              padding: EdgeInsets.all(18.0),
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: LiquidGlass.withOwnLayer(
            shape: GlassTheme.shape,
            settings: GlassTheme.card,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_errorMessage!,
                      style: _bodyStyle(16, color: Colors.white70)),
                  const SizedBox(height: 16),
                  _GlassButton(
                    label: 'retry',
                    glowColor: EdenColors.amberGlow,
                    onTap: _fetchProfileData,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: Nocturne.iconMd, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Nocturne.space8,
                Nocturne.space4,
                Nocturne.space8,
                Nocturne.space9,
              ),
              children: [
                const Text(
                  'Profile',
                  style: Nocturne.displayMd,
                ),
                const SizedBox(height: Nocturne.space7),
                _buildSectionLabel('your connection'),
                _GlassSettingsCard(
                  child: Column(
                    children: [
                      SettingsRow(label: 'Partner', rightText: _partnerName),
                      _divider(),
                      SettingsRow(
                          label: 'Relationship stage',
                          rightText: _relationshipStage.toLowerCase()),
                      _divider(),
                      SettingsRow(
                          label: 'Days together',
                          rightText: '$_daysTogether days'),
                      _divider(),
                      SettingsRow(
                        label: 'Memory count',
                        rightText: '$_memoryCount items',
                        icon: Icons.chevron_right_rounded,
                        onTap: () => context
                            .push(AppRoute.memory)
                            .then((_) => _fetchProfileData()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Nocturne.space4),
                _buildSectionLabel('how you talk'),
                _GlassSettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Nocturne.space5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Communication pace',
                                style: _bodyStyle(13, color: Colors.white70)),
                            const SizedBox(height: Nocturne.space4),
                            _buildSegmentedPaceSelector(),
                          ],
                        ),
                      ),
                      _divider(),
                      _buildToggleRow(
                        title: 'Proactive',
                        value: _notifProactive,
                        onChanged: (val) => _updateNotifPrefs(proactive: val),
                      ),
                      _divider(),
                      _buildToggleRow(
                        title: 'Follow-ups',
                        value: _notifFollowUp,
                        onChanged: (val) =>
                            _updateNotifPrefs(emotionalFollowup: val),
                      ),
                      _divider(),
                      _buildToggleRow(
                        title: 'Anniversaries',
                        value: _notifAnniversaries,
                        onChanged: (val) =>
                            _updateNotifPrefs(anniversaries: val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Nocturne.space4),
                _buildSectionLabel('your data'),
                _GlassSettingsCard(
                  child: Column(
                    children: [
                      SettingsRow(
                        label: 'Your memories',
                        icon: Icons.chevron_right_rounded,
                        onTap: () => context
                            .push(AppRoute.memory)
                            .then((_) => _fetchProfileData()),
                      ),
                      _divider(),
                      SettingsRow(
                        label: 'Export my data',
                        icon: Icons.chevron_right_rounded,
                        onTap: _handleExportData,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Nocturne.space4),
                _buildSectionLabel('account'),
                _GlassSettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildEditableNameRow(),
                      _divider(),
                      _buildDeleteEverythingRow(),
                    ],
                  ),
                ),
                const SizedBox(height: Nocturne.space7),
                _GlassButton(
                  label: 'Sign out',
                  glowColor: EdenColors.amberGlow,
                  onTap: _handleSignOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(
        left: Nocturne.space2,
        bottom: Nocturne.space3,
        top: Nocturne.space4,
      ),
      child: Text(
        label,
        style: Nocturne.label.copyWith(
          color: Nocturne.textTertiary,
          letterSpacing: 0.8,
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

    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      settings: const LiquidGlassSettings(
        blur: 6,
        glassColor: Color(0x18FFFFFF),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: paceOptions.map((opt) {
            final isSelected = _communicationPace == opt['value'];
            return Expanded(
              child: GestureDetector(
                onTap: () => _updateCommunicationPace(opt['value']!),
                child: AnimatedContainer(
                  duration: Nocturne.durationFast,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(Nocturne.radiusSm - 2),
                  ),
                  child: Center(
                    child: Text(
                      opt['label']!,
                      style: _bodyStyle(
                        13,
                        color: isSelected ? Colors.white : Colors.white60,
                      ).copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                      ),
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

  Widget _buildToggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Nocturne.space5,
        vertical: Nocturne.space4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: _bodyStyle(14)),
          _GlassSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildEditableNameRow() {
    if (_isEditingName) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Nocturne.space5,
          vertical: Nocturne.space3,
        ),
        child: Row(
          children: [
            Expanded(
              child: FakeGlass(
                shape: const LiquidRoundedSuperellipse(borderRadius: 16),
                settings: const LiquidGlassSettings(
                  blur: 6,
                  glassColor: Color(0x18FFFFFF),
                ),
                child: TextField(
                  controller: _nameController,
                  style: _bodyStyle(14),
                  cursorColor: EdenColors.electricBlue,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check,
                  color: Colors.white, size: Nocturne.iconLg),
              onPressed: _updateDisplayName,
            ),
            IconButton(
              icon: const Icon(Icons.close,
                  color: Colors.white60, size: Nocturne.iconLg),
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
      rightText: _displayName,
      icon: Icons.edit_outlined,
      onTap: () => setState(() => _isEditingName = true),
    );
  }

  Widget _buildDeleteEverythingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsRow(
          label: 'Delete everything',
          icon: _isDeleteExpanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          onTap: () {
            setState(() {
              _isDeleteExpanded = !_isDeleteExpanded;
              if (!_isDeleteExpanded) {
                _deleteConfirmController.clear();
              }
            });
          },
        ),
        if (_isDeleteExpanded)
          Padding(
            padding: const EdgeInsets.only(
              left: Nocturne.space5,
              right: Nocturne.space5,
              bottom: Nocturne.space5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will permanently erase all settings, connection details, and conversation history. This cannot be undone.',
                  style: _bodyStyle(12, color: Colors.white60),
                ),
                const SizedBox(height: 12),
                Text('Type "delete" below to confirm:',
                    style: _bodyStyle(12, color: Colors.white70)),
                const SizedBox(height: 8),
                FakeGlass(
                  shape: const LiquidRoundedSuperellipse(borderRadius: 16),
                  settings: const LiquidGlassSettings(
                    blur: 6,
                    glassColor: Color(0x18FFFFFF),
                  ),
                  child: TextField(
                    controller: _deleteConfirmController,
                    style: _bodyStyle(14),
                    cursorColor: EdenColors.orangeGlow,
                    decoration: InputDecoration(
                      hintText: 'delete',
                      hintStyle: _bodyStyle(14, color: Colors.white38),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: _isDeleteActive ? 1.0 : 0.4,
                  child: IgnorePointer(
                    ignoring: !_isDeleteActive,
                    child: _GlassButton(
                      label: 'Erase All Data',
                      glowColor: EdenColors.orangeGlow,
                      onTap: _handleDeleteAccount,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      height: 0.6,
      width: double.infinity,
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.rightText,
    this.icon,
    this.onTap,
  });

  final String label;
  final String? rightText;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Nocturne.space5),
          child: Row(
            children: [
              Expanded(child: Text(label, style: _bodyStyle(14))),
              if (rightText != null)
                Flexible(
                  child: Text(
                    rightText!,
                    style: _bodyStyle(14, color: Colors.white60),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, size: Nocturne.iconSm, color: Colors.white60),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassSettingsCard extends StatelessWidget {
  const _GlassSettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass.withOwnLayer(
      shape: GlassTheme.shape,
      settings: GlassTheme.card,
      child: child,
    );
  }
}

class _GlassSwitch extends StatelessWidget {
  const _GlassSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 18),
      settings: const LiquidGlassSettings(
        blur: 6,
        glassColor: Color(0x20FFFFFF),
      ),
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: Nocturne.durationFast,
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(4),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? EdenColors.electricBlue : Colors.white60,
                boxShadow: value
                    ? [
                        BoxShadow(
                          color:
                              EdenColors.electricBlue.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
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
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        settings: GlassTheme.button,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Center(
              child: Text(
                label,
                style: _bodyStyle(15).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _displayStyle(double size, {Color color = Colors.white}) {
  return Nocturne.displayMd.copyWith(
    fontSize: size,
    color: color,
  );
}

TextStyle _bodyStyle(double size, {Color color = Colors.white}) {
  return Nocturne.bodyMd.copyWith(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w500,
  );
}
