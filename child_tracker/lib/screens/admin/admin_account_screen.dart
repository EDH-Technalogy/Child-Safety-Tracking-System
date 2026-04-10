import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/image_service.dart';
import '../../services/admin_api_service.dart';
import '../../utils/camera_capture_helper.dart';
import '../../utils/constants.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/photo_provider.dart';
import '../../widgets/admin_drawer.dart';

class AdminAccountScreen extends StatefulWidget {
  const AdminAccountScreen({super.key});

  @override
  State<AdminAccountScreen> createState() => _AdminAccountScreenState();
}

class _AdminAccountScreenState extends State<AdminAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _adminApi = AdminApiService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _uploadingImage = false;
  String? _error;
  String _photoUrl = '';
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _persistProfileLocally(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(profile));
    await prefs.setString(
        AppConstants.userIdKey, profile['id']?.toString() ?? '');
    await prefs.setString(
      AppConstants.userNameKey,
      profile['name']?.toString() ?? '',
    );
    await prefs.setString(
      AppConstants.userEmailKey,
      profile['email']?.toString() ?? '',
    );
    await prefs.setString(
      AppConstants.userPhoneKey,
      profile['phone']?.toString() ?? '',
    );
    await prefs.setString(
      AppConstants.userRoleKey,
      profile['role']?.toString() ?? 'admin',
    );

    if (!mounted) return;
    await Provider.of<AuthProvider>(context, listen: false)
        .syncSessionUserData(profile);
  }

  void _applyProfile(Map<String, dynamic> profile) {
    _profile = profile;
    _photoUrl = profile['photo']?.toString() ?? '';
    _nameController.text = profile['name']?.toString() ?? '';
    _emailController.text = profile['email']?.toString() ?? '';
    _phoneController.text = profile['phone']?.toString() ?? '';
    _usernameController.text = profile['username']?.toString() ?? '';
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = await _adminApi.getAdminProfile();
      await _persistProfileLocally(profile);

      if (!mounted) return;
      setState(() {
        _applyProfile(profile);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = localizeErrorMessage(context.l10n, e);
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final updatedProfile = await _adminApi.updateAdminProfile(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        username: _usernameController.text.trim(),
        photo: _photoUrl,
      );

      await _persistProfileLocally(updatedProfile);

      if (!mounted) return;
      setState(() {
        _applyProfile(updatedProfile);
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.adminAccountUpdatedSuccessfully),
          backgroundColor: AppColors.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = localizeErrorMessage(context.l10n, e);
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_error ?? context.l10n.failedToUpdateAdminAccount),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Future<void> _persistPhotoChange(String nextPhotoUrl) async {
    debugPrint(
      '[AdminAccountScreen] persisting admin photo hasPhoto=${nextPhotoUrl.isNotEmpty}',
    );

    final updatedProfile = await _adminApi.updateAdminPhoto(nextPhotoUrl);

    debugPrint(
      '[AdminAccountScreen] admin photo saved persistedValue=${(updatedProfile['photo'] ?? '').toString().isNotEmpty}',
    );

    await _persistProfileLocally(updatedProfile);

    if (!mounted) return;
    setState(() {
      _applyProfile(updatedProfile);
    });
  }

  Future<void> _removePhoto() async {
    final previousPhotoUrl = _photoUrl;

    setState(() {
      _uploadingImage = true;
      _error = null;
    });

    try {
      await _persistPhotoChange('');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photoUrl = previousPhotoUrl;
        _uploadingImage = false;
        _error = localizeErrorMessage(context.l10n, e);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_error ?? context.l10n.failedToRemoveProfilePhoto),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _uploadingImage = false;
    });
  }

  Future<void> _pickImage() async {
    final l10n = context.l10n;
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
            if (_photoUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  l10n.removePhoto,
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _detectMimeType(XFile image) {
    final path = image.path.toLowerCase();
    if (path.endsWith('.png')) {
      return 'image/png';
    }
    if (path.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  String _buildInlinePhotoDataUrl(XFile image, List<int> bytes) {
    return 'data:${_detectMimeType(image)};base64,${base64Encode(bytes)}';
  }

  Future<XFile?> _pickCameraImage() {
    return pickImageFromCamera(context, _imagePicker);
  }

  Future<void> _getImage(ImageSource source) async {
    final adminId = (_profile?['id'] ?? '').toString();
    if (adminId.isEmpty) {
      return;
    }

    try {
      final image = source == ImageSource.camera
          ? await _pickCameraImage()
          : await _imagePicker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 800,
              maxHeight: 800,
              imageQuality: 85,
            );

      if (image == null) return;

      debugPrint(
        '[AdminAccountScreen] image source=$source recordType=admin targetId=$adminId',
      );

      setState(() {
        _uploadingImage = true;
      });

      final downloadUrl = await ImageService.uploadUserImage(
        image: image,
        userId: adminId,
      );
      final imageBytes = await image.readAsBytes();
      final nextPhotoUrl =
          downloadUrl ?? _buildInlinePhotoDataUrl(image, imageBytes);

      debugPrint(
        '[AdminAccountScreen] upload result persistentUrl=${downloadUrl != null} nextPhotoLength=${nextPhotoUrl.length}',
      );

      await _persistPhotoChange(nextPhotoUrl);

      if (downloadUrl == null) {
        debugPrint(
          '[AdminAccountScreen] firebase upload unavailable, using inline photo fallback',
        );
      }

      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
        _error = localizeErrorMessage(context.l10n, e);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_error ?? context.l10n.imageUploadFailed),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Widget _buildReadOnlyTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primaryColor),
      title: Text(title),
      subtitle: Text(value.isEmpty ? context.l10n.notSet : value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authUser = context.watch<AuthProvider>().user;
    final profile = _profile;
    final photoUrl = _photoUrl.isNotEmpty
        ? _photoUrl
        : ((authUser?.photo?.toString() ?? '').isNotEmpty
            ? authUser!.photo!.toString()
            : (profile?['photo']?.toString() ?? ''));
    final photoProvider = buildPhotoProvider(photoUrl);
    final displayName = (profile?['name']?.toString().trim().isNotEmpty ?? false)
        ? profile!['name'].toString().trim()
        : (authUser?.name ?? '');
    final role = profile?['role']?.toString() ?? authUser?.role ?? 'admin';
    final status =
        profile?['status']?.toString() ?? authUser?.status ?? 'active';

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.account),
        backgroundColor: AppColors.primaryColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && profile == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${l10n.error}: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadProfile,
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _pickImage,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 42,
                                      backgroundColor: Colors.white,
                                      backgroundImage: photoProvider,
                                      child: photoUrl.isEmpty
                                          ? Text(
                                              displayName.isNotEmpty
                                                  ? displayName[0].toUpperCase()
                                                  : 'A',
                                              style: const TextStyle(
                                                fontSize: 28,
                                                color: AppColors.primaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                          color: AppColors.primaryColor,
                                          shape: BoxShape.circle,
                                        ),
                                        child: _uploadingImage
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    Colors.white,
                                                  ),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.camera_alt,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                displayName.isNotEmpty
                                    ? displayName
                                    : l10n.admin,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profile?['email']?.toString() ?? '',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Chip(
                                    label: Text(localizeRoleLabel(l10n, role)),
                                    backgroundColor:
                                        AppColors.primaryColor.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                  Chip(
                                    label:
                                        Text(localizeStatusLabel(l10n, status)),
                                    backgroundColor:
                                        AppColors.successColor.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  l10n.editProfile,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _nameController,
                                  decoration: InputDecoration(
                                    labelText: l10n.name,
                                    prefixIcon: const Icon(Icons.person),
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
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: l10n.email,
                                    prefixIcon: const Icon(Icons.email),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return l10n.emailRequired;
                                    }
                                    if (!value.contains('@')) {
                                      return l10n.enterValidEmail;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: l10n.phone,
                                    prefixIcon: const Icon(Icons.phone),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: InputDecoration(
                                    labelText: l10n.username,
                                    prefixIcon: Icon(Icons.alternate_email),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: _isSaving ? null : _saveProfile,
                                  child: _isSaving
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : Text(l10n.save),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildReadOnlyTile(
                                icon: Icons.badge_outlined,
                                title: l10n.adminId,
                                value: profile?['id']?.toString() ?? '',
                              ),
                              _buildReadOnlyTile(
                                icon: Icons.shield_outlined,
                                title: l10n.role,
                                value: localizeRoleLabel(l10n, role),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
