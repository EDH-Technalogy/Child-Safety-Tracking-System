import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Future<XFile?> pickImageFromCamera(
  BuildContext context,
  ImagePicker imagePicker,
) {
  return imagePicker.pickImage(
    source: ImageSource.camera,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 85,
  );
}
