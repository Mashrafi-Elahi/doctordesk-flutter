import 'package:flutter/material.dart';
import '../widgets/profile_avatar_button.dart';

/// Inbox screen — honest empty state placeholder for doctor and clinic desk messaging.
/// No chat backend or doctor accounts exist yet.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inbox',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          ProfileAvatarButton(),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey[350]),
              const SizedBox(height: 16),
              const Text(
                'No conversations yet',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Direct messaging with your doctor and clinic desk operator will appear here during active appointments.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Messaging unlocks once you have an active appointment'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        tooltip: 'New Message',
        child: const Icon(Icons.add),
      ),
    );
  }
}
