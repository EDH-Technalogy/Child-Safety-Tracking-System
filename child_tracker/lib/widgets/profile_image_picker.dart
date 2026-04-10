import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../services/image_service.dart';

class ProfileImagePicker extends StatefulWidget {
  final String userId;
  final Function(String?) onPhotoChanged;

  const ProfileImagePicker({
    super.key,
    required this.userId,
    required this.onPhotoChanged,
  });

  @override
  State<ProfileImagePicker> createState() => _ProfileImagePickerState();
}

class _ProfileImagePickerState extends State<ProfileImagePicker> {
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
          ],
        ),
      ),
    );
  }

  Future<void> _getImage(ImageSource source) async {
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
          userId: widget.userId,
        );

        if (mounted) {
          setState(() {
            _selectedImage = image;
            _photoUrl = downloadUrl;
            _uploadingImage = false;
          });
          widget.onPhotoChanged(downloadUrl);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pickImage,
      child: CircleAvatar(
        radius: 60,
        backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
        backgroundColor: Colors.grey[300],
        child: _selectedImage != null || _uploadingImage
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              )
            : const Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
      ),
    );
  }
}
