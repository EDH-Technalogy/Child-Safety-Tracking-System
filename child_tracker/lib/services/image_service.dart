import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ImageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads child image to Firebase Storage and returns download URL
  /// Path: children/{userId}/{timestamp}.jpg
  static Future<String?> uploadChildImage({
    required XFile image,
    required String userId,
    String childId = '', // Optional for updates
  }) async {
    try {
      if (kDebugMode) {
        print(
          'Starting child image upload for userId=$userId childId=${childId.isNotEmpty ? childId : "new"}',
        );
      }

      final fileName = childId.isNotEmpty
          ? '${DateTime.now().millisecondsSinceEpoch}_$childId.jpg'
          : '${DateTime.now().millisecondsSinceEpoch}.jpg';

      final ref = _storage.ref().child('children/$userId/$fileName');

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        uploadTask = ref.putData(bytes);
      } else {
        final file = File(image.path);
        uploadTask = ref.putFile(file);
      }

      // Wait for upload complete
      final snapshot = await uploadTask.whenComplete(() {});

      // Get download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (kDebugMode) {
        print('Image uploaded: $downloadUrl');
      }

      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        print('Image upload error: $e');
      }
      return null; // Photo optional
    }
  }

  /// Uploads user/admin image to Firebase Storage and returns download URL
  /// Path: users/{userId}/{timestamp}.jpg
  static Future<String?> uploadUserImage({
    required XFile image,
    required String userId,
  }) async {
    try {
      if (kDebugMode) {
        print('Starting user image upload for userId=$userId');
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      final ref = _storage.ref().child('users/$userId/$fileName');

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        uploadTask = ref.putData(bytes);
      } else {
        final file = File(image.path);
        uploadTask = ref.putFile(file);
      }

      final snapshot = await uploadTask.whenComplete(() {});

      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (kDebugMode) {
        print('User image uploaded: $downloadUrl');
      }

      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        print('User image upload error: $e');
      }
      return null; // Photo optional
    }
  }
}
