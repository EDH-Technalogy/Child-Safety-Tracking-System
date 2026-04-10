import 'dart:convert';

import 'package:flutter/material.dart';

ImageProvider<Object>? buildPhotoProvider(String? photoUrl) {
  final normalized = (photoUrl ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }

  if (normalized.startsWith('data:image/')) {
    final commaIndex = normalized.indexOf(',');
    if (commaIndex <= 0 || commaIndex >= normalized.length - 1) {
      return null;
    }

    try {
      return MemoryImage(
        base64Decode(normalized.substring(commaIndex + 1)),
      );
    } catch (_) {
      return null;
    }
  }

  return NetworkImage(normalized);
}
