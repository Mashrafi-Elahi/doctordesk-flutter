import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/data_service.dart';

/// Shared, database-backed doctor application form. Submission only creates a
/// pending application; it never grants a doctor role on the device.
Future<bool> showDoctorApplicationDialog(BuildContext context) async {
  final user = AuthService.currentUser;
  if (user == null) return false;
  final phoneController = TextEditingController(text: user.phoneNumber ?? '');
  final bmdcController = TextEditingController();
  final specialityController = TextEditingController();

  final submitted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Doctor application'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your application will be reviewed by an administrator. Approval is required before doctor tools are enabled.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: specialityController,
              decoration: const InputDecoration(
                labelText: 'Speciality',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bmdcController,
              decoration: const InputDecoration(
                labelText: 'BMDC registration number (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (phoneController.text.trim().isEmpty) return;
            await DataService.applyForDoctorRole(
              uid: user.uid,
              phone: phoneController.text.trim(),
              name: user.displayName,
              bmdcNumber: bmdcController.text.trim(),
              speciality: specialityController.text.trim(),
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          },
          child: const Text('Submit application'),
        ),
      ],
    ),
  );
  phoneController.dispose();
  bmdcController.dispose();
  specialityController.dispose();
  return submitted == true;
}
