import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_theme.dart';
import '../services/biometric_service.dart';
import '../main.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _vaultEnabled = false;
  bool _notificationsEnabled = true;
  String _userEmail = '';
  String _userName = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final user = ref.read(authServiceProvider).currentUser;
    final vault = await BiometricService.isVaultEnabled();

    setState(() {
      _userEmail = user?.email ?? '';
      _userName = user?.displayName ?? 'Eden User';
      _vaultEnabled = vault;
      _isLoading = false;
    });
  }

  Future<void> _toggleVault(bool enabled) async {
    HapticFeedback.lightImpact();
    
    if (enabled) {
      // If turning on, prompt for PIN setup
      final pinController = TextEditingController();
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: EdenTheme.bgSurface,
          title: const Text('Setup Vault PIN', style: EdenTheme.displaySmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a 4-digit PIN to secure your vault.', style: EdenTheme.bodyMedium),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                style: EdenTheme.bodyLarge,
                decoration: const InputDecoration(
                  hintText: 'PIN',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Enable', style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.accentPrimary)),
            ),
          ],
        ),
      );

      if (confirm == true && pinController.text.trim().length == 4) {
        await BiometricService.saveVaultPin(pinController.text.trim());
        await BiometricService.setVaultEnabled(true);
        setState(() => _vaultEnabled = true);
      }
    } else {
      // Turning off vault security
      await BiometricService.clearVault();
      setState(() => _vaultEnabled = false);
    }
  }

  Future<void> _handleSignOut() async {
    HapticFeedback.mediumImpact();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EdenTheme.bgSurface,
        title: const Text('Sign Out', style: EdenTheme.displaySmall),
        content: const Text('Are you sure you want to sign out?', style: EdenTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Sign Out', style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.destructive)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(authServiceProvider).signOut();
      if (mounted) {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: EdenTheme.bgPrimary,
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(EdenTheme.accentPrimary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: EdenTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          _buildSectionHeader('PROFILE'),
          const SizedBox(height: 12),
          _buildProfileCard(),
          const SizedBox(height: 28),
          
          _buildSectionHeader('PREFERENCES'),
          const SizedBox(height: 12),
          _buildPreferenceTile(
            icon: Icons.notifications_none_rounded,
            title: 'Push Notifications',
            subtitle: 'Get alerts when partner reaches out',
            trailing: Switch.adaptive(
              value: _notificationsEnabled,
              activeColor: EdenTheme.accentPrimary,
              onChanged: (val) {
                setState(() => _notificationsEnabled = val);
                if (val) {
                  ref.read(notificationServiceProvider).requestPermission();
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildPreferenceTile(
            icon: Icons.lock_outline_rounded,
            title: 'Vault Pin Lock',
            subtitle: 'Secure memory vault access',
            trailing: Switch.adaptive(
              value: _vaultEnabled,
              activeColor: EdenTheme.accentPrimary,
              onChanged: _toggleVault,
            ),
          ),
          
          const SizedBox(height: 48),
          
          // Sign Out Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: _handleSignOut,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: EdenTheme.destructive, width: 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Sign Out',
                style: EdenTheme.bodyMedium.copyWith(color: EdenTheme.destructive, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: EdenTheme.labelSmall.copyWith(color: EdenTheme.accentSecondary),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EdenTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.08), width: 0.6),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: EdenTheme.bgElevated,
            child: Text(
              _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
              style: EdenTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold, color: EdenTheme.accentPrimary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userName, style: EdenTheme.emphasisLarge),
                const SizedBox(height: 4),
                Text(_userEmail, style: EdenTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: EdenTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.08), width: 0.6),
      ),
      child: Row(
        children: [
          Icon(icon, color: EdenTheme.textSecondary, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: EdenTheme.emphasisMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: EdenTheme.bodySmall),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
