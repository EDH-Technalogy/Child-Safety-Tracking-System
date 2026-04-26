import 'package:flutter/material.dart';

import 'shared_child_form_screen.dart';

class EditChildScreen extends StatelessWidget {
  final String childId;

  const EditChildScreen({super.key, required this.childId});

  @override
  Widget build(BuildContext context) {
    return SharedChildFormScreen(
      isEditMode: true,
      childId: childId,
    );
  }
}
