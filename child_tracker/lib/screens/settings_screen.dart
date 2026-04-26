import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/photo_provider.dart';
import 'location_settings_page.dart';
import 'notification_settings_page.dart';
import 'privacy_security_page.dart';
import 'help_support_page.dart';
import 'static_content_page.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_service.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  XFile? _selectedImage;
  String? _photoUrl;
  bool _uploadingImage = false;
  bool _loadingProfile = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCurrentProfile();
    });
  }

  Future<void> _loadCurrentProfile() async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user == null) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[SettingsScreen] account opened userId=${user.id} role=${user.role}',
      );
    }

    setState(() {
      _loadingProfile = true;
    });

    await authProvider.getProfile();

    if (!mounted) return;
    setState(() {
      _loadingProfile = false;
    });

    final error = authProvider.error;
    if (error != null && error.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizeRawMessage(l10n, error)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  void _showStatusSnackBar({
    required String message,
    required bool success,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? AppColors.successColor : AppColors.errorColor,
      ),
    );
  }

  Future<bool> _persistPhotoChange(String photoUrl) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user == null) {
      return false;
    }

    final success = await authProvider.updateProfile(
      name: user.name,
      phone: user.phone,
      photo: photoUrl,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.error != null
                ? localizeRawMessage(l10n, authProvider.error!)
                : l10n.failedToUpdateProfilePhoto,
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }

    return success;
  }

  Future<void> _pickImage() async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentPhotoUrl = (_photoUrl?.isNotEmpty ?? false)
        ? _photoUrl!
        : (authProvider.user?.photo ?? '');
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l10n.camera),
              onTap: () {
                Navigator.pop(context);
                _getImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.gallery),
              onTap: () {
                Navigator.pop(context);
                _getImage(ImageSource.gallery);
              },
            ),
            if (_selectedImage != null || currentPhotoUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  l10n.delete,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  final authProvider =
                      Provider.of<AuthProvider>(context, listen: false);
                  final previousPhotoUrl = (_photoUrl?.isNotEmpty ?? false)
                      ? _photoUrl!
                      : (authProvider.user?.photo ?? '');
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                    _photoUrl = '';
                  });
                  final success = await _persistPhotoChange('');
                  if (!success && mounted) {
                    setState(() {
                      _photoUrl =
                          previousPhotoUrl.isNotEmpty ? previousPhotoUrl : null;
                    });
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _getImage(ImageSource source) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        final previousPhotoUrl = (_photoUrl?.isNotEmpty ?? false)
            ? _photoUrl!
            : (authProvider.user?.photo ?? '');

        setState(() {
          _selectedImage = image;
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
          setState(() {
            _selectedImage = null;
            _photoUrl = previousPhotoUrl.isNotEmpty ? previousPhotoUrl : null;
          });
        } else if (downloadUrl != null) {
          final success = await _persistPhotoChange(downloadUrl);
          if (!success && mounted) {
            setState(() {
              _photoUrl = previousPhotoUrl.isNotEmpty ? previousPhotoUrl : null;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${localizeErrorMessage(l10n, e)}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = context.watch<LocaleProvider>();
    final currentLanguageLabel =
        _languageLabel(l10n, localeProvider.locale.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final user = authProvider.user;

          if (user == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${l10n.login}: ${l10n.account}'),
              ),
            );
          }

          final effectivePhotoUrl = (_photoUrl?.isNotEmpty ?? false)
              ? _photoUrl!
              : (user.photo ?? '');
          final photoProvider = _selectedImage == null
              ? buildPhotoProvider(effectivePhotoUrl)
              : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_loadingProfile) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                      ],
                      GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundImage: photoProvider,
                          backgroundColor: Colors.grey[300],
                          child: _selectedImage != null || _uploadingImage
                              ? Stack(
                                  children: [
                                    if (_selectedImage != null)
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
                                            strokeWidth: 2),
                                      ),
                                  ],
                                )
                              : photoProvider != null
                                  ? null
                                  : const Icon(Icons.add_a_photo,
                                      size: 40, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.name.isNotEmpty ? user.name : l10n.user,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style:
                            const TextStyle(fontSize: 14, color: Colors.grey),
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
              _buildSection(context, l10n.account, [
                _buildTile(context, Icons.person, l10n.editProfile,
                    () => _showEditProfileDialog(context)),
                _buildTile(context, Icons.lock, l10n.changePassword,
                    () => _showChangePasswordDialog(context)),
                _buildTile(context, Icons.notifications, l10n.notifications,
                    () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationSettingsPage()));
                }),
              ]),
              const SizedBox(height: 16),
              _buildSection(context, l10n.app, [
                _buildTile(context, Icons.language, l10n.language,
                    () => _showLanguageDialog(context),
                    subtitle: currentLanguageLabel),
                _buildTile(context, Icons.location_on, l10n.locationSettings,
                    () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LocationSettingsPage()));
                }),
                _buildTile(context, Icons.security, l10n.privacySecurity, () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PrivacySecurityPage()));
                }),
                _buildTile(context, Icons.help, l10n.helpSupport, () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HelpSupportPage()));
                }),
                _buildTile(context, Icons.info_outline, l10n.about, () {
                  Navigator.pushNamed(context, '/about');
                }),
                _buildTile(context, Icons.description, l10n.termsOfService, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StaticContentPage(
                        title: l10n.termsOfService,
                        body: l10n.termsOfServiceBody,
                      ),
                    ),
                  );
                }),
                _buildTile(context, Icons.privacy_tip, l10n.privacyPolicy, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StaticContentPage(
                        title: l10n.privacyPolicy,
                        body: l10n.privacyPolicyBody,
                      ),
                    ),
                  );
                }),
              ]),
              const SizedBox(height: 16),
              if (authProvider.isAdmin)
                _buildSection(context, l10n.adminPanel, [
                  _buildTile(
                      context,
                      Icons.admin_panel_settings,
                      l10n.adminPanel,
                      () => Navigator.pushNamed(context, '/admin-dashboard')),
                ]),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () => _showLogoutDialog(context),
                  child: Text(l10n.logout,
                      style:
                          const TextStyle(fontSize: 16, color: Colors.white)),
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
            child: Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E40AF))),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1E40AF)),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _showEditProfileDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user == null) {
      _showStatusSnackBar(message: l10n.loginFailed, success: false);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[SettingsScreen.editProfile] opened userId=${user.id} role=${user.role}',
      );
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone);
    final emailController = TextEditingController(text: user.email);

    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(l10n.editProfile),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    enabled: !isSubmitting,
                    decoration: InputDecoration(
                      labelText: l10n.name,
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.enterName;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneController,
                    enabled: !isSubmitting,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.phone,
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.enterPhone;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    enabled: !isSubmitting,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: l10n.email,
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) {
                        return l10n.emailRequired;
                      }
                      if (!email.contains('@') || !email.contains('.')) {
                        return l10n.enterValidEmail;
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() != true) {
                          if (kDebugMode) {
                            debugPrint(
                              '[SettingsScreen.editProfile] validation failed userId=${user.id}',
                            );
                          }
                          return;
                        }

                        final payloadFields = <String>[
                          'name',
                          'phone',
                          'email',
                        ];

                        if (kDebugMode) {
                          debugPrint(
                            '[SettingsScreen.editProfile] submit userId=${user.id} role=${user.role} fields=$payloadFields',
                          );
                        }

                        setDialogState(() {
                          isSubmitting = true;
                        });

                        final success = await authProvider.updateProfile(
                          name: nameController.text.trim(),
                          phone: phoneController.text.trim(),
                          email: emailController.text.trim(),
                        );

                        if (!mounted || !dialogContext.mounted) return;

                        setDialogState(() {
                          isSubmitting = false;
                        });

                        if (success) {
                          Navigator.pop(dialogContext);
                          _showStatusSnackBar(
                            message: l10n.profileUpdatedSuccess,
                            success: true,
                          );
                          return;
                        }

                        _showStatusSnackBar(
                          message: authProvider.error != null
                              ? localizeRawMessage(l10n, authProvider.error!)
                              : l10n.profileUpdatedFailed,
                          success: false,
                        );
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;

    if (user == null) {
      _showStatusSnackBar(message: l10n.loginFailed, success: false);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[SettingsScreen.changePassword] opened userId=${user.id} role=${user.role}',
      );
    }

    final formKey = GlobalKey<FormState>();
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isSubmitting = false;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(l10n.changePasswordTitle),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentPasswordController,
                    enabled: !isSubmitting,
                    obscureText: obscureCurrent,
                    decoration: InputDecoration(
                      labelText: _currentPasswordLabel(context),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureCurrent
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscureCurrent = !obscureCurrent;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return _currentPasswordRequiredLabel(context);
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: newPasswordController,
                    enabled: !isSubmitting,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: l10n.newPassword,
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNew ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscureNew = !obscureNew;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.passwordRequired;
                      }
                      if (value.length < 6) {
                        return l10n.passwordMinSix;
                      }
                      if (value == currentPasswordController.text) {
                        return _newPasswordMustDifferLabel(context);
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmPasswordController,
                    enabled: !isSubmitting,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: l10n.confirmPassword,
                      prefixIcon: const Icon(Icons.verified_user_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscureConfirm = !obscureConfirm;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.passwordRequired;
                      }
                      if (value != newPasswordController.text) {
                        return l10n.passwordsDoNotMatch;
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() != true) {
                          if (kDebugMode) {
                            debugPrint(
                              '[SettingsScreen.changePassword] validation failed userId=${user.id}',
                            );
                          }
                          return;
                        }

                        if (kDebugMode) {
                          debugPrint(
                            '[SettingsScreen.changePassword] submit userId=${user.id} role=${user.role} passwordLengths=current:${currentPasswordController.text.length},new:${newPasswordController.text.length},confirm:${confirmPasswordController.text.length}',
                          );
                        }

                        setDialogState(() {
                          isSubmitting = true;
                        });

                        final success = await authProvider.changePassword(
                          currentPassword: currentPasswordController.text,
                          newPassword: newPasswordController.text,
                          confirmPassword: confirmPasswordController.text,
                        );

                        if (!mounted || !dialogContext.mounted) return;

                        setDialogState(() {
                          isSubmitting = false;
                        });

                        if (success) {
                          Navigator.pop(dialogContext);
                          _showStatusSnackBar(
                            message: l10n.passwordChangedSuccessfully,
                            success: true,
                          );
                          return;
                        }

                        _showStatusSnackBar(
                          message: authProvider.error != null
                              ? localizeRawMessage(l10n, authProvider.error!)
                              : l10n.error,
                          success: false,
                        );
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  String _currentPasswordLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'fa':
        return 'رمز عبور فعلی';
      case 'ps':
        return 'اوسنی پاسورډ';
      default:
        return 'Current Password';
    }
  }

  String _currentPasswordRequiredLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'fa':
        return 'لطفاً رمز عبور فعلی را وارد کنید';
      case 'ps':
        return 'مهرباني وکړئ اوسنی پاسورډ دننه کړئ';
      default:
        return 'Please enter current password';
    }
  }

  String _newPasswordMustDifferLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'fa':
        return 'رمز عبور جدید باید متفاوت باشد';
      case 'ps':
        return 'نوی پاسورډ باید توپیر ولري';
      default:
        return 'New password must be different';
    }
  }

  Future<void> _showLanguageDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog(
      context: context,
      builder: (dialogContext) => Consumer<LocaleProvider>(
        builder: (dialogContext, localeProvider, child) {
          Future<void> selectLocale(Locale locale) async {
            final selectedCode = locale.languageCode;

            debugPrint(
              '[SettingsScreen.language] selected=$selectedCode current=${localeProvider.locale.languageCode}',
            );

            await localeProvider.setLocale(locale);

            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
          }

          return AlertDialog(
            title: Text(l10n.selectLanguage),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _languageOptionTile(
                  value: 'en',
                  title: l10n.english,
                  groupValue: localeProvider.locale.languageCode,
                  onSelected: () => selectLocale(const Locale('en')),
                ),
                _languageOptionTile(
                  value: 'ps',
                  title: l10n.pashto,
                  groupValue: localeProvider.locale.languageCode,
                  onSelected: () => selectLocale(const Locale('ps')),
                ),
                _languageOptionTile(
                  value: 'fa',
                  title: l10n.dari,
                  groupValue: localeProvider.locale.languageCode,
                  onSelected: () => selectLocale(const Locale('fa')),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _languageOptionTile({
    required String value,
    required String title,
    required String groupValue,
    required VoidCallback onSelected,
  }) {
    return ListTile(
      leading: Radio<String>(
        value: value,
        groupValue: groupValue,
        onChanged: (_) => onSelected(),
      ),
      title: Text(title),
      onTap: onSelected,
    );
  }

  String _languageLabel(AppLocalizations l10n, String languageCode) {
    switch (languageCode) {
      case 'ps':
        return l10n.pashto;
      case 'fa':
        return l10n.dari;
      default:
        return l10n.english;
    }
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
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await authProvider.logout();
              if (!mounted || !dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              Navigator.pushReplacementNamed(this.context, '/login');
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}
