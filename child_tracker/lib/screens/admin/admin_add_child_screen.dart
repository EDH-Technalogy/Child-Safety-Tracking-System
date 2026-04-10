import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/child_provider.dart';
import '../../models/child_model.dart';
import '../../services/admin_api_service.dart';
import '../../services/image_service.dart';
import '../../utils/constants.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/photo_provider.dart';
import '../../widgets/admin_drawer.dart';

class AdminAddChildScreen extends StatefulWidget {
  final bool isEditMode;
  final Map<String, dynamic>? initialChild;
  final Map<String, dynamic>? initialDevice;

  const AdminAddChildScreen({
    super.key,
    this.isEditMode = false,
    this.initialChild,
    this.initialDevice,
  });

  @override
  State<AdminAddChildScreen> createState() => _AdminAddChildScreenState();
}

class _AdminAddChildScreenState extends State<AdminAddChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final AdminApiService _adminApi = AdminApiService();
  final _userIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _imeiController = TextEditingController();
  final _simNumberController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage;
  String? _photoUrl;
  String? _existingDeviceId;
  String _deviceFirmware = '1.0.0';
  bool _registerDevice = false;
  bool _uploadingImage = false;
  bool _submittingEdit = false;
  bool _loadingUsers = false;
  bool _didLoadUsers = false;
  bool _userLoadFailed = false;
  List<Map<String, dynamic>> _availableUsers = const [];

  @override
  void initState() {
    super.initState();
    _applyInitialValues();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAdmin) {
        _loadAvailableUsers();
      }
    });
  }

  void _applyInitialValues() {
    if (!widget.isEditMode) return;

    final child = widget.initialChild ?? const <String, dynamic>{};
    final device = widget.initialDevice;

    _userIdController.text = (child['user_id'] ?? '').toString();
    _nameController.text = (child['name'] ?? '').toString();
    _ageController.text = (child['age'] ?? '').toString();
    _photoUrl = ChildModel.resolvePhotoFromJson(child);

    if (device != null) {
      _existingDeviceId = device['id']?.toString();
      _registerDevice = true;
      _imeiController.text = (device['imei'] ?? '').toString();
      _simNumberController.text = (device['sim_number'] ?? '').toString();
      _deviceFirmware = (device['firmware_version'] ?? '1.0.0').toString();
    }
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
    if (identifier.isEmpty) {
      return null;
    }

    final normalizedIdentifier = identifier.toLowerCase();
    final matches = _availableUsers.where((user) {
      final id = (user['id'] ?? '').toString().trim();
      final phone = (user['phone'] ?? '').toString().trim();
      final email = (user['email'] ?? '').toString().trim().toLowerCase();
      return id == identifier ||
          phone == identifier ||
          email == normalizedIdentifier;
    }).toList();

    if (matches.length == 1) {
      return matches.first;
    }

    return null;
  }

  String _userDisplayValue(Map<String, dynamic> user) {
    final phone = (user['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) {
      return phone;
    }

    final email = (user['email'] ?? '').toString().trim();
    if (email.isNotEmpty) {
      return email;
    }

    return (user['id'] ?? '').toString();
  }

  String _userPickerTitle(Map<String, dynamic> user) {
    final name = (user['name'] ?? '').toString().trim();
    if (name.isNotEmpty) {
      return name;
    }
    return _userDisplayValue(user);
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

  Future<void> _getImage(ImageSource source) async {
    final l10n = context.l10n;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final matchedUser = authProvider.isAdmin
          ? _resolveLocalUser(_userIdController.text)
          : null;
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

        final uploadOwnerId = authProvider.isAdmin
            ? ((matchedUser?['id'] ??
                    widget.initialChild?['user_id'] ??
                    authProvider.user!.id)
                .toString())
            : authProvider.user!.id;
        final childId = widget.initialChild?['id']?.toString() ?? '';

        if (kDebugMode) {
          debugPrint(
            '[AdminAddChildScreen] image source=$source recordType=child ownerId=$uploadOwnerId childId=${childId.isNotEmpty ? childId : "new"}',
          );
        }

        final String? downloadUrl = await ImageService.uploadChildImage(
          image: image,
          userId: uploadOwnerId,
          childId: childId,
        );
        final nextPhotoUrl = downloadUrl ??
            _buildInlinePhotoDataUrl(image, await image.readAsBytes());

        if (mounted) {
          setState(() {
            _selectedImage = image;
            _photoUrl = nextPhotoUrl;
            _uploadingImage = false;
          });

          if (downloadUrl == null) {
            debugPrint(
              '[AdminAddChildScreen] firebase upload unavailable, using inline child photo fallback',
            );
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
            content: Text(localizeErrorMessage(l10n, e)),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _addChild() async {
    if (_uploadingImage || !_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    final enteredUserValue = authProvider.isAdmin
        ? _userIdController.text.trim()
        : authProvider.user!.id;
    final matchedUser =
        authProvider.isAdmin ? _resolveLocalUser(enteredUserValue) : null;
    final resolvedUserId =
        matchedUser != null ? (matchedUser['id'] ?? '').toString() : null;
    final userId = authProvider.isAdmin
        ? (resolvedUserId?.isNotEmpty ?? false)
            ? resolvedUserId!
            : enteredUserValue
        : authProvider.user!.id;

    if (authProvider.isAdmin && enteredUserValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.userIdRequiredForAdminChildCreation),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (authProvider.isAdmin && _loadingUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.waitForParentUsersToLoad),
          backgroundColor: AppColors.warningColor,
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
          content: Text(context.l10n.noMatchingParentUserFound),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[AdminAddChildScreen] submit isEditMode=${widget.isEditMode} enteredUser=$enteredUserValue resolvedUserId=$userId name=${_nameController.text.trim()} registerDevice=$_registerDevice',
      );
    }

    bool success;

    if (widget.isEditMode) {
      setState(() {
        _submittingEdit = true;
      });

      try {
        final childId = widget.initialChild?['id']?.toString() ?? '';
        if (childId.isEmpty) {
          throw Exception(context.l10n.childIdRequiredForUpdates);
        }

        await _adminApi.updateChild(
          childId: childId,
          userId: userId,
          name: _nameController.text.trim(),
          age: int.parse(_ageController.text),
          photo: _photoUrl ?? '',
        );

        if (_registerDevice) {
          if (_existingDeviceId != null && _existingDeviceId!.isNotEmpty) {
            await _adminApi.updateDevice(
              deviceId: _existingDeviceId!,
              childId: childId,
              imei: _imeiController.text.trim(),
              simNumber: _simNumberController.text.trim(),
              firmware: _deviceFirmware,
            );
          } else {
            await _adminApi.createDevice(
              childId: childId,
              imei: _imeiController.text.trim(),
              simNumber: _simNumberController.text.trim(),
              firmware: _deviceFirmware,
            );
          }
        } else if (_existingDeviceId != null && _existingDeviceId!.isNotEmpty) {
          await _adminApi.deleteDevice(_existingDeviceId!);
        }

        final refreshedChildDetails =
            await _adminApi.getChildWithDevice(childId);
        childProvider.syncChildFromJson(
          Map<String, dynamic>.from(
            (refreshedChildDetails['child'] as Map?) ?? const {},
          ),
          deviceJson: refreshedChildDetails['device'] is Map
              ? Map<String, dynamic>.from(
                  refreshedChildDetails['device'] as Map,
                )
              : null,
        );

        success = true;
      } catch (e) {
        success = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizeErrorMessage(context.l10n, e)),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _submittingEdit = false;
          });
        }
      }
    } else {
      success = await childProvider.addChild(
        userId: userId,
        name: _nameController.text.trim(),
        age: int.parse(_ageController.text),
        photo: _photoUrl,
        imei: _registerDevice ? _imeiController.text.trim() : null,
        simNumber: _registerDevice ? _simNumberController.text.trim() : null,
        firmware: _registerDevice ? "1.0.0" : null,
      );
    }

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? context.l10n.childUpdatedSuccess
                : context.l10n.childAddedSuccess,
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
      Navigator.pop(context);
    } else if (mounted && !widget.isEditMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            childProvider.error != null
                ? localizeRawMessage(context.l10n, childProvider.error!)
                : context.l10n.error,
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final persistedPhotoProvider = buildPhotoProvider(_photoUrl);

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(widget.isEditMode ? l10n.editChild : l10n.addChild),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Consumer<ChildProvider>(
        builder: (context, childProvider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Photo picker
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor:
                                AppColors.primaryColor.withValues(alpha: 0.1),
                            backgroundImage: _selectedImage == null
                                ? persistedPhotoProvider
                                : null,
                            child: _selectedImage != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(50),
                                    child: kIsWeb
                                        ? FutureBuilder<Uint8List>(
                                            future:
                                                _selectedImage!.readAsBytes(),
                                            builder: (context, snapshot) {
                                              if (snapshot.hasData) {
                                                return Image.memory(
                                                  snapshot.data!,
                                                  fit: BoxFit.cover,
                                                );
                                              }
                                              return const Icon(
                                                Icons.child_care,
                                                size: 50,
                                                color: AppColors.primaryColor,
                                              );
                                            },
                                          )
                                        : Image.file(
                                            File(_selectedImage!.path),
                                            fit: BoxFit.cover,
                                          ),
                                  )
                                : persistedPhotoProvider != null
                                    ? null
                                    : const Icon(
                                        Icons.child_care,
                                        size: 50,
                                        color: AppColors.primaryColor,
                                      ),
                          ),
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
                      _selectedImage != null || (_photoUrl?.isNotEmpty ?? false)
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
                        if (authProvider.isAdmin &&
                            (value == null || value.trim().isEmpty)) {
                          return l10n.pleaseEnterParentUserId;
                        }
                        if (authProvider.isAdmin &&
                            _didLoadUsers &&
                            !_userLoadFailed &&
                            value != null &&
                            value.trim().isNotEmpty &&
                            _resolveLocalUser(value) == null) {
                          return l10n.noMatchingParentUserFound;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Name field
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.childName,
                      prefixIcon: Icon(Icons.child_care),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.pleaseEnterChildName;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Age field
                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.age,
                      prefixIcon: Icon(Icons.cake),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.pleaseEnterChildAge;
                      }
                      final age = int.tryParse(value);
                      if (age == null || age < 0 || age > 18) {
                        return l10n.pleaseEnterValidAge;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Device Registration Toggle
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.phone_android,
                                      color: AppColors.primaryColor),
                                  const SizedBox(width: 12),
                                  Text(
                                    l10n.registerDevice,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _registerDevice,
                                onChanged: (value) {
                                  setState(() {
                                    _registerDevice = value;
                                  });
                                },
                                activeColor: AppColors.primaryColor,
                              ),
                            ],
                          ),
                          if (_registerDevice) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _imeiController,
                              decoration: InputDecoration(
                                labelText: l10n.imei,
                                prefixIcon: Icon(Icons.qr_code),
                              ),
                              validator: (value) {
                                if (_registerDevice &&
                                    (value == null || value.isEmpty)) {
                                  return l10n.enterDeviceId;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _simNumberController,
                              decoration: InputDecoration(
                                labelText: l10n.simNumberOptional,
                                prefixIcon: Icon(Icons.sim_card),
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

                  // Add button
                  ElevatedButton(
                    onPressed: (childProvider.isLoading || _submittingEdit)
                        ? null
                        : _addChild,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: (childProvider.isLoading || _submittingEdit)
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            widget.isEditMode ? l10n.editChild : l10n.addChild,
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
