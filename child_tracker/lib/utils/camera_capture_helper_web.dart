// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';

Uint8List _bytesFromDataUrl(String dataUrl) {
  final parts = dataUrl.split(',');
  if (parts.length != 2) {
    return Uint8List(0);
  }

  return base64Decode(parts[1]);
}

Future<XFile?> pickImageFromCamera(
  BuildContext context,
  ImagePicker imagePicker,
) async {
  final mediaDevices = html.window.navigator.mediaDevices;
  if (mediaDevices == null) {
    return imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
  }

  html.MediaStream? stream;
  html.VideoElement? videoElement;

  try {
    final l10n = AppLocalizations.of(context)!;
    stream = await mediaDevices.getUserMedia({
      'video': {
        'facingMode': 'user',
      },
      'audio': false,
    });

    videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..setAttribute('playsinline', 'true');

    videoElement.srcObject = stream;
    await videoElement.play();

    if (!context.mounted) {
      return null;
    }

    final viewType = 'admin-camera-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int _) => videoElement!,
    );

    final capturedBytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.takePhoto),
        content: SizedBox(
          width: 320,
          height: 420,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: HtmlElementView(viewType: viewType),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final width =
                  videoElement!.videoWidth > 0 ? videoElement.videoWidth : 720;
              final height = videoElement.videoHeight > 0
                  ? videoElement.videoHeight
                  : 1280;

              final canvas = html.CanvasElement(
                width: width,
                height: height,
              );

              canvas.context2D.drawImageScaled(
                videoElement,
                0,
                0,
                width.toDouble(),
                height.toDouble(),
              );

              final dataUrl = canvas.toDataUrl('image/jpeg', 0.9);
              Navigator.pop(dialogContext, _bytesFromDataUrl(dataUrl));
            },
            child: Text(l10n.capture),
          ),
        ],
      ),
    );

    if (capturedBytes == null || capturedBytes.isEmpty) {
      return null;
    }

    return XFile.fromData(
      capturedBytes,
      mimeType: 'image/jpeg',
      name: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
  } catch (_) {
    return imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
  } finally {
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
    }
    if (videoElement != null) {
      videoElement.srcObject = null;
    }
  }
}
