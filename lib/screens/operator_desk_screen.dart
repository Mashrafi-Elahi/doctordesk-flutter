import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../widgets/profile_avatar_button.dart';

/// Operator middle-tab placeholder: Chamber Desk Queue Management
class OperatorDeskScreen extends StatelessWidget {
  const OperatorDeskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desk Queue'),
        actions: const [
          ProfileAvatarButton(role: UserRole.operator),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.dashboard_outlined, size: 56, color: Colors.grey[350]),
              const SizedBox(height: 16),
              const Text(
                'Coming soon — queue management',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Clinic desk operators will be able to manage patient check-in queues, issue tokens, and monitor chamber status here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
