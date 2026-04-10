import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import 'privacy_security_page.dart';
import 'help_support_page.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  XFile? _selectedImage;
  String? _photoUrl;
  bool _uploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickImage() async {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l10n.takePhoto),
              onTap: () {
                Navigator.pop(context);
                _getImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.chooseFromGallery),
              onTap: () {
                Navigator.pop(context);
                _getImage(ImageSource.gallery);
              },
            ),
            if (_selectedImage != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  l10n.removePhoto,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                    _photoUrl = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _getImage(ImageSource source) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _uploadingImage = true;
        });

        final String? downloadUrl = await ImageService.uploadUserImage(
          image: image,
          userId: authProvider.user!.id,
        );

        if (mounted) {
          setState(() {
            _selectedImage = image;
            _photoUrl = downloadUrl;
            _uploadingImage = false;
          });
        }

        if (downloadUrl == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.uploadFailedPhotoOptional)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.error}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final user = authProvider.user;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Profile Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundImage: _photoUrl != null
                              ? NetworkImage(_photoUrl!)
                              : null,
                          backgroundColor: Colors.grey[300],
                          child: _selectedImage != null
                              ? Stack(
                                  children: [
                                    ClipOval(
                                      child: Image.file(
                                        File(_selectedImage!.path),
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (_uploadingImage)
                                      const Positioned(
                                        bottom: 4,
                                        right: 4,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                  ],
                                )
                              : _uploadingImage
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 2,
                                    )
                                  : const Icon(
                                      Icons.add_a_photo,
                                      size: 40,
                                      color: Colors.grey,
                                    ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user?.name ?? l10n.profile,
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
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _showEditProfileDialog(context),
                        icon: const Icon(Icons.edit),
                        label: Text(l10n.editProfile),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Account Settings
              _buildSection(
                context,
                l10n.account,
                [
                  _buildTile(context, Icons.person, l10n.editProfile,
                      () => _showEditProfileDialog(context)),
                  _buildTile(context, Icons.lock, l10n.changePassword,
                      () => _showChangePasswordDialog(context)),
                  _buildTile(context, Icons.notifications, l10n.notifications,
                      () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacySecurityPage(),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // App Settings
              _buildSection(
                context,
                l10n.app,
                [
                  _buildTile(context, Icons.language, l10n.language,
                      () => _showLanguageDialog(context)),
                  _buildTile(context, Icons.location_on, l10n.locationSettings,
                      () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacySecurityPage(),
                      ),
                    );
                  }),
                  _buildTile(context, Icons.security, l10n.privacySecurity, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacySecurityPage(),
                      ),
                    );
                  }),
                  _buildTile(context, Icons.help, l10n.helpSupport, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HelpSupportPage(),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // Admin Panel
              if (Provider.of<AuthProvider>(context).isAdmin)
                _buildSection(
                  context,
                  l10n.adminPanel,
                  [
                    _buildTile(
                      context,
                      Icons.admin_panel_settings,
                      l10n.adminPanelTitle,
                      () => Navigator.pushNamed(context, '/admin-dashboard'),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // About
              _buildSection(
                context,
                l10n.about,
                [
                  ListTile(
                    leading: const Icon(Icons.info),
                    title: Text(l10n.appVersion),
                    subtitle: Text('v1.0.0'),
                  ),
                  _buildTile(
                      context, Icons.description, l10n.termsOfService, () {}),
                  _buildTile(
                      context, Icons.privacy_tip, l10n.privacyPolicy, () {}),
                ],
              ),
              const SizedBox(height: 32),

              // Logout Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => _showLogoutDialog(context),
                  child: Text(
                    l10n.logout,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E40AF),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTile(
      BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1E40AF)),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _showEditProfileDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    final nameController = TextEditingController(text: user?.name ?? '');
    final phoneController = TextEditingController(text: user?.phone ?? '');

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editProfile),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: l10n.name,
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.phone,
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
              if (!dialogContext.mounted || !mounted) return;
              Navigator.pop(dialogContext);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.profileUpdatedSuccess),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(authProvider.error ?? l10n.error),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changePassword),
        content: Text(l10n.enterEmailToReceiveOtp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguageDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.selectLanguage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Radio<String>(
                value: 'en',
                groupValue: localeProvider.locale.languageCode,
                onChanged: null,
              ),
              title: Text(l10n.english),
              onTap: () {
                localeProvider.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Radio<String>(
                value: 'ps',
                groupValue: localeProvider.locale.languageCode,
                onChanged: null,
              ),
              title: Text(l10n.pashto),
              onTap: () {
                localeProvider.setLocale(const Locale('ps'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Radio<String>(
                value: 'fa',
                groupValue: localeProvider.locale.languageCode,
                onChanged: null,
              ),
              title: Text(l10n.dari),
              onTap: () {
                localeProvider.setLocale(const Locale('fa'));
                Navigator.pop(context);
              },
            ),
          ],
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

  Future<void> _showLogoutDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await authProvider.logout();
              if (!dialogContext.mounted || !mounted) return;
              Navigator.pop(dialogContext);
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}
