import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/child_model.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../services/admin_api_service.dart';
import '../services/image_service.dart';
import '../utils/auth_validation.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../utils/photo_provider.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/app_drawer.dart';

class SharedChildFormScreen extends StatefulWidget {
  final bool isEditMode;
  final String? childId;
  final Map<String, dynamic>? initialChild;
  final Map<String, dynamic>? initialDevice;

  const SharedChildFormScreen({
    super.key,
    this.isEditMode = false,
    this.childId,
    this.initialChild,
    this.initialDevice,
  });

  @override
  State<SharedChildFormScreen> createState() => _SharedChildFormScreenState();
}

class _SharedChildFormScreenState extends State<SharedChildFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final AdminApiService _adminApi = AdminApiService();
  final ImagePicker _imagePicker = ImagePicker();
  final _userIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _imeiController = TextEditingController();
  final _simNumberController = TextEditingController();

  XFile? _selectedImage;
  String? _photoUrl;
  String? _existingDeviceId;
  String _deviceFirmware = '1.0.0';
  bool _registerDevice = false;
  bool _uploadingImage = false;
  bool _submitting = false;
  bool _loadingInitialChild = false;
  String? _initialLoadError;

  bool _loadingUsers = false;
  bool _didLoadUsers = false;
  bool _userLoadFailed = false;
  List<Map<String, dynamic>> _availableUsers = const [];

  String? get _effectiveChildId {
    final initialId = widget.initialChild?['id']?.toString().trim() ?? '';
    if (initialId.isNotEmpty) return initialId;

    final childId = widget.childId?.trim() ?? '';
    if (childId.isNotEmpty) return childId;

    return null;
  }

  @override
  void initState() {
    super.initState();
    _applyInitialValues(
      child: widget.initialChild,
      device: widget.initialDevice,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final role = authProvider.isAdmin ? 'admin' : 'user';

      if (kDebugMode) {
        debugPrint(
          '[SharedChildFormScreen] opened role=$role mode=${widget.isEditMode ? "edit" : "add"} childId=${_effectiveChildId ?? "new"}',
        );
      }

      if (authProvider.isAdmin) {
        _loadAvailableUsers();
      }

      if (widget.isEditMode && widget.initialChild == null) {
        _loadInitialChildForEdit();
      }
    });
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _imeiController.dispose();
    _simNumberController.dispose();
    super.dispose();
  }

  void _applyInitialValues({
    Map<String, dynamic>? child,
    Map<String, dynamic>? device,
  }) {
    if (!widget.isEditMode || child == null) return;

    _userIdController.text =
        (child['user_id'] ?? child['userId'] ?? '').toString().trim();
    _nameController.text = (child['name'] ?? '').toString();
    _ageController.text = (child['age'] ?? '').toString();
    _photoUrl = ChildModel.resolvePhotoFromJson(child);

    if (device != null) {
      _existingDeviceId = device['id']?.toString();
      _registerDevice = true;
      _imeiController.text = (device['imei'] ?? '').toString();
      _simNumberController.text = (device['sim_number'] ?? '').toString();
      _deviceFirmware = (device['firmware_version'] ?? '1.0.0').toString();
    } else {
      _existingDeviceId = null;
      _registerDevice = false;
      _imeiController.clear();
      _simNumberController.clear();
      _deviceFirmware = '1.0.0';
    }
  }

  Future<void> _loadInitialChildForEdit() async {
    final childId = _effectiveChildId;
    if (childId == null || childId.isEmpty) {
      setState(() {
        _initialLoadError = context.l10n.childIdRequiredForUpdates;
      });
      return;
    }

    setState(() {
      _loadingInitialChild = true;
      _initialLoadError = null;
    });

    try {
      final childProvider = Provider.of<ChildProvider>(context, listen: false);
      await childProvider.getChildWithDevice(childId);
      final child = childProvider.selectedChild;

      if (!mounted) return;
      if (child == null) {
        throw Exception(context.l10n.noData);
      }

      setState(() {
        _applyInitialValues(
          child: child.toJson(),
          device: child.device?.toJson(),
        );
        _loadingInitialChild = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInitialChild = false;
        _initialLoadError = localizeErrorMessage(context.l10n, e);
      });
    }
  }

  Future<void> _loadAvailableUsers() async {
    setState(() {
      _loadingUsers = true;
      _userLoadFailed = false;
    });

    try {
      final users = await _adminApi.getAllUsers();
      if (!mounted) return;
      setState(() {
        _availableUsers = users
            .map((user) => Map<String, dynamic>.from(user as Map))
            .toList();
        _loadingUsers = false;
        _didLoadUsers = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availableUsers = const [];
        _loadingUsers = false;
        _didLoadUsers = true;
        _userLoadFailed = true;
      });
    }
  }

  Map<String, dynamic>? _resolveLocalUser(String rawValue) {
    final identifier = rawValue.trim();
    if (identifier.isEmpty) return null;

    final normalizedIdentifier = identifier.toLowerCase();
    final matches = _availableUsers.where((user) {
      final id = (user['id'] ?? '').toString().trim();
      final phone = (user['phone'] ?? '').toString().trim();
      final email = (user['email'] ?? '').toString().trim().toLowerCase();
      return id == identifier ||
          phone == identifier ||
          email == normalizedIdentifier;
    }).toList();

    return matches.length == 1 ? matches.first : null;
  }

  String _userDisplayValue(Map<String, dynamic> user) {
    final phone = (user['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;

    final email = (user['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;

    return (user['id'] ?? '').toString();
  }

  String _userPickerTitle(Map<String, dynamic> user) {
    final name = (user['name'] ?? '').toString().trim();
    return name.isNotEmpty ? name : _userDisplayValue(user);
  }

  String _userPickerSubtitle(Map<String, dynamic> user) {
    final l10n = context.l10n;
    final details = <String>[
      if ((user['phone'] ?? '').toString().trim().isNotEmpty)
        '${l10n.phone}: ${user['phone']}',
      if ((user['email'] ?? '').toString().trim().isNotEmpty)
        '${l10n.email}: ${user['email']}',
      if ((user['id'] ?? '').toString().trim().isNotEmpty)
        '${l10n.userId}: ${user['id']}',
    ];

    return details.join(' | ');
  }

  Future<void> _showUserPicker() async {
    final l10n = context.l10n;
    if (_loadingUsers) return;
    if (!_didLoadUsers) {
      await _loadAvailableUsers();
    }
    if (!mounted) return;

    if (_availableUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _userLoadFailed
                ? l10n.unableToLoadParentUsers
                : l10n.noParentUsersAvailable,
          ),
          backgroundColor:
              _userLoadFailed ? AppColors.errorColor : AppColors.warningColor,
        ),
      );
      return;
    }

    final selectedUser = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  l10n.selectParentUser,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _availableUsers.length,
                  itemBuilder: (context, index) {
                    final user = _availableUsers[index];
                    return ListTile(
                      title: Text(_userPickerTitle(user)),
                      subtitle: Text(_userPickerSubtitle(user)),
                      onTap: () => Navigator.pop(context, user),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedUser == null || !mounted) return;
    setState(() {
      _userIdController.text = _userDisplayValue(selectedUser);
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
            if (_selectedImage != null || (_photoUrl?.isNotEmpty ?? false))
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
                    _photoUrl = '';
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  String _detectMimeType(XFile image) {
    final path = image.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _buildInlinePhotoDataUrl(XFile image, List<int> bytes) {
    return 'data:${_detectMimeType(image)};base64,${base64Encode(bytes)}';
  }

  String _resolveImageOwnerId(AuthProvider authProvider) {
    if (!authProvider.isAdmin) {
      return authProvider.user!.id;
    }

    final matchedUser = _resolveLocalUser(_userIdController.text);
    final matchedUserId = (matchedUser?['id'] ?? '').toString().trim();
    if (matchedUserId.isNotEmpty) return matchedUserId;

    final initialOwnerId = (widget.initialChild?['user_id'] ??
            widget.initialChild?['userId'] ??
            '')
        .toString()
        .trim();
    if (initialOwnerId.isNotEmpty) return initialOwnerId;

    return authProvider.user!.id;
  }

  Future<void> _getImage(ImageSource source) async {
    final l10n = context.l10n;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _uploadingImage = true;
      });

      final uploadOwnerId = _resolveImageOwnerId(authProvider);
      final childId = _effectiveChildId ?? '';

      if (kDebugMode) {
        debugPrint(
          '[SharedChildFormScreen] image source=$source role=${authProvider.isAdmin ? "admin" : "user"} ownerId=$uploadOwnerId childId=${childId.isNotEmpty ? childId : "new"}',
        );
      }

      final downloadUrl = await ImageService.uploadChildImage(
        image: image,
        userId: uploadOwnerId,
        childId: childId,
      );
      final nextPhotoUrl = downloadUrl ??
          _buildInlinePhotoDataUrl(image, await image.readAsBytes());

      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _photoUrl = nextPhotoUrl;
        _uploadingImage = false;
      });

      if (downloadUrl == null && kDebugMode) {
        debugPrint(
          '[SharedChildFormScreen] firebase upload unavailable, using inline child photo fallback',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizeErrorMessage(l10n, e)),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  String? _validateAdminTargetUser(AuthProvider authProvider) {
    if (!authProvider.isAdmin) return authProvider.user?.id;

    final enteredUserValue = _userIdController.text.trim();
    if (enteredUserValue.isEmpty) {
      return null;
    }

    final matchedUser = _resolveLocalUser(enteredUserValue);
    final resolvedUserId =
        (matchedUser?['id'] ?? '').toString().trim().isNotEmpty
            ? matchedUser!['id'].toString()
            : enteredUserValue;
    return resolvedUserId;
  }

  Future<void> _saveChild() async {
    final l10n = context.l10n;
    if (_uploadingImage || !_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final role = authProvider.isAdmin ? 'admin' : 'user';

    if (authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.loginFailed),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (authProvider.isAdmin && _loadingUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.waitForParentUsersToLoad),
          backgroundColor: AppColors.warningColor,
        ),
      );
      return;
    }

    final enteredUserValue = authProvider.isAdmin
        ? _userIdController.text.trim()
        : authProvider.user!.id;
    final matchedUser =
        authProvider.isAdmin ? _resolveLocalUser(enteredUserValue) : null;

    if (authProvider.isAdmin && enteredUserValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.userIdRequiredForAdminChildCreation),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (authProvider.isAdmin &&
        _didLoadUsers &&
        !_userLoadFailed &&
        matchedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noMatchingParentUserFound),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    final userId = _validateAdminTargetUser(authProvider);
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterParentUserId),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    final childId = _effectiveChildId ?? '';
    if (widget.isEditMode && childId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.childIdRequiredForUpdates),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[SharedChildFormScreen] save role=$role mode=${widget.isEditMode ? "edit" : "add"} childId=${childId.isNotEmpty ? childId : "new"} targetUserId=$userId registerDevice=$_registerDevice hasExistingDevice=${(_existingDeviceId ?? "").isNotEmpty}',
      );
    }

    setState(() {
      _submitting = true;
    });

    final success = widget.isEditMode
        ? await childProvider.updateChild(
            childId: childId,
            userId: userId,
            name: _nameController.text.trim(),
            age: int.parse(_ageController.text),
            photo: _photoUrl,
            registerDevice: _registerDevice,
            deviceId: _existingDeviceId,
            imei: _registerDevice ? _imeiController.text.trim() : null,
            simNumber:
                _registerDevice ? _simNumberController.text.trim() : null,
            firmware: _registerDevice ? _deviceFirmware : null,
          )
        : await childProvider.addChild(
            userId: userId,
            name: _nameController.text.trim(),
            age: int.parse(_ageController.text),
            photo: _photoUrl,
            imei: _registerDevice ? _imeiController.text.trim() : null,
            simNumber:
                _registerDevice ? _simNumberController.text.trim() : null,
            firmware: _registerDevice ? _deviceFirmware : null,
          );

    if (!mounted) return;
    setState(() {
      _submitting = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? l10n.childUpdatedSuccess
                : l10n.childAddedSuccess,
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      Navigator.pop(context, true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          childProvider.error != null
              ? localizeRawMessage(l10n, childProvider.error!)
              : l10n.error,
        ),
        backgroundColor: AppColors.errorColor,
      ),
    );
  }

  Widget _buildPhotoPreview(ImageProvider? persistedPhotoProvider) {
    Widget? child;
    if (_uploadingImage) {
      child = const Center(child: CircularProgressIndicator(strokeWidth: 3));
    } else if (_selectedImage != null) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: kIsWeb
            ? FutureBuilder<Uint8List>(
                future: _selectedImage!.readAsBytes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(snapshot.data!, fit: BoxFit.cover);
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              )
            : Image.file(File(_selectedImage!.path), fit: BoxFit.cover),
      );
    } else if (persistedPhotoProvider == null) {
      child = const Icon(
        Icons.child_care,
        size: 50,
        color: AppColors.primaryColor,
      );
    }

    return CircleAvatar(
      radius: 50,
      backgroundColor: AppColors.primaryColor.withValues(alpha: 0.1),
      backgroundImage: _selectedImage == null && !_uploadingImage
          ? persistedPhotoProvider
          : null,
      child: child,
    );
  }

  Widget _buildInitialLoadState() {
    final l10n = context.l10n;
    if (_loadingInitialChild) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initialLoadError == null) {
      return const SizedBox.shrink();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_initialLoadError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialChildForEdit,
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final persistedPhotoProvider = buildPhotoProvider(_photoUrl);

    return Scaffold(
      drawer: authProvider.isAdmin ? const AdminDrawer() : const AppDrawer(),
      appBar: AppBar(
        title: Text(widget.isEditMode ? l10n.editChild : l10n.addChild),
        backgroundColor: AppColors.primaryColor,
      ),
      body: _loadingInitialChild || _initialLoadError != null
          ? _buildInitialLoadState()
          : Consumer<ChildProvider>(
              builder: (context, childProvider, child) {
                final isBusy = childProvider.isLoading || _submitting;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: _uploadingImage ? null : _pickImage,
                            child: Stack(
                              children: [
                                _buildPhotoPreview(persistedPhotoProvider),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            _selectedImage != null ||
                                    (_photoUrl?.isNotEmpty ?? false)
                                ? l10n.tapToChangePhoto
                                : l10n.tapToAddPhoto,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (authProvider.isAdmin) ...[
                          TextFormField(
                            controller: _userIdController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l10n.userId,
                              helperText: l10n.useParentPhoneEmailOrTapSearch,
                              prefixIcon: const Icon(Icons.person_outline),
                              suffixIcon: _loadingUsers
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.search),
                                      tooltip: l10n.selectParentUser,
                                      onPressed: _showUserPicker,
                                    ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.pleaseEnterParentUserId;
                              }
                              if (_didLoadUsers &&
                                  !_userLoadFailed &&
                                  _resolveLocalUser(value) == null) {
                                return l10n.noMatchingParentUserFound;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: l10n.childName,
                            prefixIcon: const Icon(Icons.child_care),
                          ),
                          validator: (value) {
                              return validateFullNameInput(
                                value,
                                requiredMessage: l10n.pleaseEnterChildName,
                                invalidMessage: l10n.pleaseEnterChildName,
                              );
                            },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ageController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.age,
                            prefixIcon: const Icon(Icons.cake),
                          ),
                          validator: (value) {
                            return validateAgeInput(
                              value,
                              requiredMessage: l10n.pleaseEnterChildAge,
                              invalidMessage: l10n.pleaseEnterValidAge,
                            );
                          },
                        ),
                        const SizedBox(height: 32),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.phone_android,
                                            color: AppColors.primaryColor,
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: Text(
                                              l10n.registerDevice,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _registerDevice,
                                      onChanged: (value) {
                                        setState(() {
                                          _registerDevice = value;
                                        });
                                      },
                                      activeThumbColor: AppColors.primaryColor,
                                    ),
                                  ],
                                ),
                                if (_registerDevice) ...[
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _imeiController,
                                    decoration: InputDecoration(
                                      labelText: l10n.imei,
                                      prefixIcon: const Icon(Icons.qr_code),
                                    ),
                                    validator: (value) {
                                      if (!_registerDevice) {
                                        return null;
                                      }
                                      return validateImeiInput(
                                        value,
                                        requiredMessage: l10n.enterDeviceId,
                                        invalidMessage: l10n.enterDeviceId,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _simNumberController,
                                    decoration: InputDecoration(
                                      labelText: l10n.simNumberOptional,
                                      prefixIcon: const Icon(Icons.sim_card),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.deviceWillBeRegistered,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed:
                              isBusy || _uploadingImage ? null : _saveChild,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: isBusy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.isEditMode
                                      ? l10n.editChild
                                      : l10n.addChild,
                                  style: const TextStyle(fontSize: 16),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
