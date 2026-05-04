import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_localizations.dart';
import '../../services/admin_api_service.dart';
import '../../services/image_service.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/photo_provider.dart';
import '../../widgets/admin_drawer.dart';

enum _UserPhotoAction { camera, gallery, remove }

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final AdminApiService _adminApi = AdminApiService();
  final ImagePicker _imagePicker = ImagePicker();
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterUsers);
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatError(Object error) {
    return localizeErrorMessage(AppLocalizations.of(context)!, error);
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

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = List<dynamic>.from(_users);
      });
    } else {
      setState(() {
        _filteredUsers = _users.where((user) {
          final name = (user['name'] ?? '').toString().toLowerCase();
          final email = (user['email'] ?? '').toString().toLowerCase();
          return name.contains(query) || email.contains(query);
        }).toList();
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await _adminApi.getAllUsers();
      setState(() {
        _users = users;
        _filteredUsers = List<dynamic>.from(users);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = _formatError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _blockUser(String userId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _adminApi.blockUser(userId);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.userBlocked)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_formatError(e))),
        );
      }
    }
  }

  Future<void> _unblockUser(String userId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _adminApi.unblockUser(userId);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.userUnblocked)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_formatError(e))),
        );
      }
    }
  }

  Future<void> _deleteUser(String userId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteUser),
        content: Text(l10n.areYouSureDeleteUser),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _adminApi.deleteUser(userId);
        await _loadUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.userDeleted)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_formatError(e))),
          );
        }
      }
    }
  }

  Future<String?> _pickUserPhoto({
    required String userId,
    required bool allowRemove,
  }) async {
    final action = await showModalBottomSheet<_UserPhotoAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(context.l10n.takePhoto),
              onTap: () => Navigator.pop(context, _UserPhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(context.l10n.chooseFromGallery),
              onTap: () => Navigator.pop(context, _UserPhotoAction.gallery),
            ),
            if (allowRemove)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  context.l10n.removePhoto,
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(context, _UserPhotoAction.remove),
              ),
          ],
        ),
      ),
    );

    if (action == null) {
      return null;
    }

    if (action == _UserPhotoAction.remove) {
      return '';
    }

    final source = action == _UserPhotoAction.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    final image = await _imagePicker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (image == null) {
      return null;
    }

    if (kDebugMode) {
      debugPrint(
        '[AdminUsersScreen] image source=$source recordType=user targetId=$userId',
      );
    }

    final downloadUrl = await ImageService.uploadUserImage(
      image: image,
      userId: userId,
    );

    if (downloadUrl != null) {
      return downloadUrl;
    }

    final imageBytes = await image.readAsBytes();
    final inlinePhotoUrl = _buildInlinePhotoDataUrl(image, imageBytes);

    if (kDebugMode) {
      debugPrint(
        '[AdminUsersScreen] firebase upload unavailable, using inline user photo fallback',
      );
    }

    return inlinePhotoUrl;
  }

  void _showAddUserDialog() {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'user';
    String photoUrl = '';
    bool uploadingPhoto = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.addNewUser),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    setDialogState(() {
                      uploadingPhoto = true;
                    });

                    final uploadTarget = emailController.text.trim().isNotEmpty
                        ? emailController.text.trim()
                        : 'pending_user_${DateTime.now().millisecondsSinceEpoch}';

                    final nextPhotoUrl = await _pickUserPhoto(
                      userId: uploadTarget,
                      allowRemove: photoUrl.isNotEmpty,
                    );

                    if (!mounted) return;

                    setDialogState(() {
                      uploadingPhoto = false;
                      if (nextPhotoUrl != null) {
                        photoUrl = nextPhotoUrl;
                      }
                    });
                  },
                  child: Stack(
                    children: [
                      Builder(
                        builder: (context) {
                          final photoProvider = buildPhotoProvider(photoUrl);
                          return CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.blue.withValues(alpha: 0.1),
                            backgroundImage: photoProvider,
                            child: photoProvider == null
                                ? const Icon(Icons.person, color: Colors.blue)
                                : null,
                          );
                        },
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: uploadingPhoto
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  size: 14,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: l10n.name),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(labelText: l10n.phone),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(labelText: l10n.email),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(labelText: l10n.password),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: InputDecoration(labelText: l10n.role),
                  items: [
                    DropdownMenuItem(
                      value: 'user',
                      child: Text(localizeRoleLabel(l10n, 'user')),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text(localizeRoleLabel(l10n, 'admin')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedRole = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _adminApi.createUser(
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                    password: passwordController.text,
                    role: selectedRole,
                    photo: photoUrl,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await _loadUsers();
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(l10n.userCreated)),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(_formatError(e))),
                    );
                  }
                }
              },
              child: Text(l10n.create),
            ),
          ],
        ),
      ),
    );
  }

  void _openUserProfileDialog(
    Map<String, dynamic> user, {
    required bool isAddProfile,
  }) {
    final action = isAddProfile ? 'add_profile' : 'edit_profile';
    if (kDebugMode) {
      debugPrint(
        '[AdminUsersScreen] menu action=$action targetUserId=${user['id']}',
      );
    }

    _showEditUserDialog(
      user,
      dialogTitle:
          isAddProfile ? context.l10n.addProfile : context.l10n.editProfile,
      submitLabel:
          isAddProfile ? context.l10n.saveProfile : context.l10n.update,
    );
  }

  void _showEditUserDialog(
    Map<String, dynamic> user, {
    String? dialogTitle,
    String? submitLabel,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final nameController =
        TextEditingController(text: (user['name'] ?? '').toString());
    final phoneController =
        TextEditingController(text: (user['phone'] ?? '').toString());
    final emailController =
        TextEditingController(text: (user['email'] ?? '').toString());
    String selectedRole =
        (user['role']?.toString().toLowerCase() == 'admin') ? 'admin' : 'user';
    String photoUrl = (user['photo'] ?? '').toString();
    bool uploadingPhoto = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(dialogTitle ?? l10n.editUser),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    setDialogState(() {
                      uploadingPhoto = true;
                    });

                    final nextPhotoUrl = await _pickUserPhoto(
                      userId: user['id'].toString(),
                      allowRemove: photoUrl.isNotEmpty,
                    );

                    if (!mounted) return;

                    setDialogState(() {
                      uploadingPhoto = false;
                      if (nextPhotoUrl != null) {
                        photoUrl = nextPhotoUrl;
                      }
                    });
                  },
                  child: Stack(
                    children: [
                      Builder(
                        builder: (context) {
                          final photoProvider = buildPhotoProvider(photoUrl);
                          return CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.blue.withValues(alpha: 0.1),
                            backgroundImage: photoProvider,
                            child: photoProvider == null
                                ? const Icon(Icons.person, color: Colors.blue)
                                : null,
                          );
                        },
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: uploadingPhoto
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  size: 14,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: l10n.name),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(labelText: l10n.phone),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(labelText: l10n.email),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: InputDecoration(labelText: l10n.role),
                  items: [
                    DropdownMenuItem(
                      value: 'user',
                      child: Text(localizeRoleLabel(l10n, 'user')),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text(localizeRoleLabel(l10n, 'admin')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedRole = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  if (kDebugMode) {
                    debugPrint(
                      '[AdminUsersScreen] submitting user update userId=${user['id']} selectedRole=$selectedRole',
                    );
                  }
                  await _adminApi.updateUser(
                    userId: user['id'],
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                    role: selectedRole,
                    photo: photoUrl,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await _loadUsers();
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(l10n.userUpdated)),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(_formatError(e))),
                    );
                  }
                }
              },
              child: Text(submitLabel ?? l10n.update),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(l10n.userManagement),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddUserDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchByNameOrEmail,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('${l10n.error}: $_error'))
                    : _filteredUsers.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_off,
                                    size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text(l10n.noUsersFound),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadUsers,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                final status = user['status'] ?? 'active';
                                final photoProvider = buildPhotoProvider(
                                  (user['photo'] ?? '').toString(),
                                );
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: status == 'blocked'
                                          ? Colors.red.withValues(alpha: 0.1)
                                          : Colors.blue.withValues(alpha: 0.1),
                                      backgroundImage: photoProvider,
                                      child: photoProvider == null
                                          ? Icon(
                                              Icons.person,
                                              color: status == 'blocked'
                                                  ? Colors.red
                                                  : Colors.blue,
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      user['name'] ?? l10n.unknown,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (user['email'] != null) ...[
                                          Text(user['email']),
                                          const SizedBox(height: 4),
                                        ],
                                        Text(
                                          '${l10n.status}: ${localizeStatusLabel(l10n, status)}',
                                          style: TextStyle(
                                            color: status == 'blocked'
                                                ? Colors.red
                                                : Colors.green,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (kDebugMode) {
                                          debugPrint(
                                            '[AdminUsersScreen] menu action=$value targetUserId=${user['id']}',
                                          );
                                        }
                                        switch (value) {
                                          case 'edit':
                                            _showEditUserDialog(user);
                                            break;
                                          case 'add_profile':
                                            _openUserProfileDialog(
                                              user,
                                              isAddProfile: true,
                                            );
                                            break;
                                          case 'edit_profile':
                                            _openUserProfileDialog(
                                              user,
                                              isAddProfile: false,
                                            );
                                            break;
                                          case 'block':
                                            _blockUser(user['id']);
                                            break;
                                          case 'unblock':
                                            _unblockUser(user['id']);
                                            break;
                                          case 'delete':
                                            _deleteUser(user['id']);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.edit),
                                              const SizedBox(width: 8),
                                              Text(l10n.edit),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'add_profile',
                                          child: Row(
                                            children: [
                                              const Icon(
                                                  Icons.person_add_alt_1),
                                              const SizedBox(width: 8),
                                              Text(l10n.addProfile),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit_profile',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.manage_accounts),
                                              const SizedBox(width: 8),
                                              Text(l10n.editProfile),
                                            ],
                                          ),
                                        ),
                                        if (status == 'active')
                                          PopupMenuItem(
                                            value: 'block',
                                            child: Row(
                                              children: [
                                                const Icon(Icons.block,
                                                    color: Colors.orange),
                                                const SizedBox(width: 8),
                                                Text(l10n.block),
                                              ],
                                            ),
                                          ),
                                        if (status == 'blocked')
                                          PopupMenuItem(
                                            value: 'unblock',
                                            child: Row(
                                              children: [
                                                const Icon(Icons.check_circle,
                                                    color: Colors.green),
                                                const SizedBox(width: 8),
                                                Text(l10n.unblock),
                                              ],
                                            ),
                                          ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.delete,
                                                  color: Colors.red),
                                              const SizedBox(width: 8),
                                              Text(l10n.delete),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
