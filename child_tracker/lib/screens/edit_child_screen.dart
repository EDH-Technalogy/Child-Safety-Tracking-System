import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/image_service.dart';
import '../../utils/constants.dart';
import '../../utils/localization_helpers.dart';
import '../../utils/photo_provider.dart';

class EditChildScreen extends StatefulWidget {
  final String childId;

  const EditChildScreen({super.key, required this.childId});

  @override
  State<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends State<EditChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage;
  String? _photoUrl;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadChild();
  }

  Future<void> _loadChild() async {
    final childProvider = Provider.of<ChildProvider>(context, listen: false);
    await childProvider.getChildById(
        widget.childId); // Assume add this method or use selectChild
    if (childProvider.selectedChild != null) {
      final child = childProvider.selectedChild!;
      _nameController.text = child.name;
      _ageController.text = child.age.toString();
      _photoUrl = child.photo;
    }
  }

  Future<void> _pickImage() async {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                title: Text(l10n.delete,
                    style: const TextStyle(color: Colors.red)),
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
    final l10n = context.l10n;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
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

        final String? downloadUrl = await ImageService.uploadChildImage(
          image: image,
          userId: authProvider.user!.id,
          childId: widget.childId,
        );

        if (mounted) {
          setState(() {
            _selectedImage = image;
            _photoUrl = downloadUrl;
            _uploadingImage = false;
          });

          if (downloadUrl == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.uploadFailedCurrentPhotoKept),
                backgroundColor: AppColors.warningColor,
              ),
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

  Future<void> _updateChild() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final childProvider = Provider.of<ChildProvider>(context, listen: false);

    final success = await childProvider.updateChild(
      childId: widget.childId,
      name: _nameController.text.trim(),
      age: int.parse(_ageController.text),
      photo: _photoUrl,
      userId: authProvider.user!.id,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.childUpdatedSuccess),
          backgroundColor: AppColors.successColor,
        ),
      );
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            childProvider.error != null
                ? localizeRawMessage(l10n, childProvider.error!)
                : l10n.updateFailed,
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final persistedPhotoProvider = buildPhotoProvider(_photoUrl);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editChild),
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
                            radius: 60,
                            backgroundColor:
                                AppColors.primaryColor.withValues(alpha: 0.1),
                            backgroundImage: _selectedImage == null
                                ? persistedPhotoProvider
                                : null,
                            child: _selectedImage != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(60),
                                    child: _uploadingImage
                                        ? const CircularProgressIndicator()
                                        : kIsWeb
                                            ? FutureBuilder<Uint8List>(
                                                future: _selectedImage!
                                                    .readAsBytes(),
                                                builder: (context, snapshot) {
                                                  if (snapshot.hasData) {
                                                    return Image.memory(
                                                      snapshot.data!,
                                                      fit: BoxFit.cover,
                                                    );
                                                  }
                                                  return const CircularProgressIndicator();
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
                                        size: 60,
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
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _selectedImage != null
                          ? l10n.tapToChangePhoto
                          : l10n.tapToAddPhoto,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Name field
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.childName,
                      prefixIcon: const Icon(Icons.child_care),
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
                      labelText: l10n.childAge,
                      prefixIcon: const Icon(Icons.cake),
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

                  // Update button
                  ElevatedButton(
                    onPressed: childProvider.isLoading ? null : _updateChild,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: childProvider.isLoading
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
                            l10n.editChild,
                            style: TextStyle(fontSize: 16),
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
