import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../widgets/profile_avatar_button.dart';

/// Doctor Appointment Manager & Post Composer Screen
class DoctorManagerScreen extends StatelessWidget {
  const DoctorManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Doctor Desk'),
          actions: const [
            ProfileAvatarButton(role: UserRole.doctor),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Appointments'),
              Tab(text: 'Post Composer'),
            ],
            labelColor: colorScheme.primary,
            indicatorColor: colorScheme.primary,
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Appointments Queue
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 56, color: Colors.grey[350]),
                    const SizedBox(height: 16),
                    const Text(
                      'No patient appointments yet',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Appointments booked by patients for your chambers will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            // Tab 2: Post Composer
            Center(
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
                      'Verified doctors will be able to share health advisories, clinical articles, and answers to community questions here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
