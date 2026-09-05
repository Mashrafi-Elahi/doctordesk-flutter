import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../widgets/profile_avatar_button.dart';

/// Doctor middle-tab placeholder: Post composer
class CreatePostScreen extends StatelessWidget {
  const CreatePostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Composer'),
        actions: const [
          ProfileAvatarButton(role: UserRole.doctor),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_box_outlined, size: 56, color: Colors.grey[350]),
              const SizedBox(height: 16),
              const Text(
                'Coming soon — post composer',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Verified doctors will be able to author medical articles, post health tips, and answer community questions here.',
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
