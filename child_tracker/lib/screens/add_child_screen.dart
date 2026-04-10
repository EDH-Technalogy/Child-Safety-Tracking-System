import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/child_provider.dart';
import '../services/image_service.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';
import '../widgets/app_drawer.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _imeiController = TextEditingController();
  final _simNumberController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage;
  String? _photoUrl;
  bool _registerDevice = false;
  bool _uploadingImage = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _imeiController.dispose();
    _simNumberController.dispose();
    super.dispose();
  }

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
        // Upload image
        setState(() {
          _uploadingImage = true;
        });

        final String? downloadUrl = await ImageService.uploadChildImage(
          image: image,
          userId: authProvider.user!.id,
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
                content: Text(l10n.uploadFailedPhotoOptional),
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

  Future<void> _addChild() async {
    if (_uploadingImage || !_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final childProvider = Provider.of<ChildProvider>(context, listen: false);

    final success = await childProvider.addChild(
      userId: authProvider.user!.id,
      name: _nameController.text.trim(),
      age: int.parse(_ageController.text),
      photo: _photoUrl,
      imei: _registerDevice ? _imeiController.text.trim() : null,
      simNumber: _registerDevice ? _simNumberController.text.trim() : null,
      firmware: _registerDevice ? "1.0.0" : null,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.childAddedSuccess),
          backgroundColor: AppColors.successColor,
        ),
      );
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            childProvider.error != null
                ? localizeRawMessage(
                    AppLocalizations.of(context)!,
                    childProvider.error!,
                  )
                : AppLocalizations.of(context)!.error,
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(l10n.addChild),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
            tooltip: l10n.menu,
          ),
        ),
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
                            child: _selectedImage != null || _uploadingImage
                                ? Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(50),
                                        child: _uploadingImage
                                            ? Container(
                                                color: Colors.grey,
                                                child: const FittedBox(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              )
                                            : kIsWeb
                                                ? FutureBuilder<Uint8List>(
                                                    future: _selectedImage!
                                                        .readAsBytes(),
                                                    builder:
                                                        (context, snapshot) {
                                                      if (snapshot.hasData) {
                                                        return Image.memory(
                                                          snapshot.data!,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (context, error,
                                                                  stackTrace) {
                                                            return const Icon(
                                                              Icons.child_care,
                                                              size: 50,
                                                              color: AppColors
                                                                  .primaryColor,
                                                            );
                                                          },
                                                        );
                                                      } else if (snapshot
                                                          .hasError) {
                                                        return const Icon(
                                                          Icons.child_care,
                                                          size: 50,
                                                          color: AppColors
                                                              .primaryColor,
                                                        );
                                                      }
                                                      return const CircularProgressIndicator();
                                                    },
                                                  )
                                                : Image.file(
                                                    File(_selectedImage!.path),
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
                                                      return const Icon(
                                                        Icons.child_care,
                                                        size: 50,
                                                        color: AppColors
                                                            .primaryColor,
                                                      );
                                                    },
                                                  ),
                                      ),
                                      if (_uploadingImage)
                                        const Positioned.fill(
                                          child: Center(
                                            child: SizedBox(
                                              width: 30,
                                              height: 30,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 3),
                                            ),
                                          ),
                                        ),
                                    ],
                                  )
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
                                prefixIcon: const Icon(Icons.qr_code),
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

                  // Add button
                  ElevatedButton(
                    onPressed: childProvider.isLoading ? null : _addChild,
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
                            l10n.addChild,
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
