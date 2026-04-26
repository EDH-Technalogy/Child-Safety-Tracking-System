import 'package:flutter/material.dart';

import '../shared_child_form_screen.dart';

class AdminAddChildScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SharedChildFormScreen(
      isEditMode: isEditMode,
      initialChild: initialChild,
      initialDevice: initialDevice,
    );
  }
}
