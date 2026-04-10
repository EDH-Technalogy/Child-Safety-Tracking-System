import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/photo_provider.dart';
import '../../widgets/admin_drawer.dart';
import '../help_support_page.dart';
import '../location_settings_page.dart';
import '../notification_settings_page.dart';
import '../privacy_security_page.dart';
import '../static_content_page.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.settings),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final user = authProvider.user;
          final photoProvider = buildPhotoProvider(user?.photo);
          final displayName = (user?.name ?? l10n.admin).trim();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Profile Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white,
                        backgroundImage: photoProvider,
                        child: photoProvider == null
                            ? Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'A',
                                style: const TextStyle(
                                  fontSize: 32,
                                  color: AppColors.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        displayName.isNotEmpty ? displayName : l10n.admin,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          l10n.administrator,
                          style: const TextStyle(
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _showEditProfileDialog(),
                        child: Text(l10n.editProfile),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Account Settings
              _SettingsSection(
                title: l10n.account,
                children: [
                  _SettingsTile(
                    icon: Icons.person,
                    title: l10n.editProfile,
                    onTap: () => _showEditProfileDialog(),
                  ),
                  _SettingsTile(
                    icon: Icons.lock,
                    title: l10n.changePassword,
                    onTap: () => _showChangePasswordDialog(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // App Settings
              _SettingsSection(
                title: l10n.app,
                children: [
                  _SettingsTile(
                    icon: Icons.location_on,
                    title: l10n.locationSettings,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LocationSettingsPage(),
                        ),
                      );
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.security,
                    title: l10n.privacySecurity,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacySecurityPage(),
                        ),
                      );
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.help,
                    title: l10n.helpSupport,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HelpSupportPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // System Settings (Admin only)
              _SettingsSection(
                title: l10n.systemSection,
                children: [
                  _SettingsTile(
                    icon: Icons.tune,
                    title: l10n.systemConfiguration,
                    subtitle: l10n.configureDefaultSettings,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacySecurityPage(),
                        ),
                      );
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.notifications_active,
                    title: l10n.notificationSettings,
                    subtitle: l10n.configureAlertsAndNotifications,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationSettingsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // About
              _SettingsSection(
                title: l10n.about,
                children: [
                  _SettingsTile(
                    icon: Icons.info,
                    title: l10n.aboutThisAppTitle,
                    subtitle: '${l10n.appVersion}: ${AppConstants.appVersion}',
                    onTap: () {
                      Navigator.pushNamed(context, '/about');
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.description,
                    title: l10n.termsOfService,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StaticContentPage(
                            title: l10n.termsOfService,
                            body: l10n.termsOfServiceBody,
                          ),
                        ),
                      );
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.privacy_tip,
                    title: l10n.privacyPolicy,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StaticContentPage(
                            title: l10n.privacyPolicy,
                            body: l10n.privacyPolicyBody,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Logout
              ElevatedButton(
                onPressed: () => _showLogoutDialog(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  l10n.logout,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditProfileDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    final nameController = TextEditingController(text: user?.name ?? '');
    final phoneController = TextEditingController(text: user?.phone ?? '');

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editProfileTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: l10n.name,
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.phone,
                prefixIcon: const Icon(Icons.phone),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await authProvider.updateProfile(
                name: nameController.text,
                phone: phoneController.text,
              );
              if (mounted && dialogContext.mounted) {
                Navigator.pop(dialogContext);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.profileUpdatedSuccess),
                      backgroundColor: AppColors.successColor,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        authProvider.error != null
                            ? localizeRawMessage(l10n, authProvider.error!)
                            : l10n.profileUpdatedFailed,
                      ),
                      backgroundColor: AppColors.errorColor,
                    ),
                  );
                }
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changePasswordTitle),
        content: Text(
          l10n.forgotPassword,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logoutTitle),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (mounted && dialogContext.mounted) {
                Navigator.pop(dialogContext);
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryColor),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
