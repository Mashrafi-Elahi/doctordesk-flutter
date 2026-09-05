import 'package:flutter/material.dart';
import '../models/user_role.dart';

class ProfileScreen extends StatelessWidget {
  final UserRole role;

  const ProfileScreen({super.key, this.role = UserRole.patient});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String title;
    switch (role) {
      case UserRole.doctor:
        title = 'Doctor Profile & Chambers';
        break;
      case UserRole.operator:
        title = 'Chamber Desk Profile';
        break;
      case UserRole.patient:
        title = 'Patient Profile';
        break;
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    role == UserRole.doctor
                        ? Icons.local_hospital_outlined
                        : role == UserRole.operator
                            ? Icons.business_outlined
                            : Icons.person,
                    size: 40,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  role == UserRole.doctor
                      ? 'Doctor Account'
                      : role == UserRole.operator
                          ? 'Desk Operator'
                          : 'Guest User (Patient)',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  role == UserRole.patient
                      ? 'Sign in to sync your medical records & history'
                      : 'Sign in to manage your practice and chamber',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (role == UserRole.patient) ...[
            // Medical records & reports upload card
            Card(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_shared_outlined, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Medical History & Reports',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Keep your lab reports, prescriptions, and test history up to date so you can easily send them to your doctor via chat during active appointments.',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Report upload will activate once user login is connected.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Upload Medical Report'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ProfileTile(
              icon: Icons.edit_outlined,
              label: 'Edit Profile Details',
              colorScheme: colorScheme,
            ),
            _ProfileTile(
              icon: Icons.favorite_outline,
              label: 'Saved Doctors',
              colorScheme: colorScheme,
            ),
            _ProfileTile(
              icon: Icons.rate_review_outlined,
              label: 'My Reviews',
              colorScheme: colorScheme,
            ),
            _ProfileTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              colorScheme: colorScheme,
            ),
          ] else if (role == UserRole.doctor) ...[
            // Doctor Chamber Profile Box
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.apartment, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Chamber Profile & Schedule',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage your chamber locations, visiting hours, and consultation fees.',
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ProfileTile(
              icon: Icons.verified_user_outlined,
              label: 'BMDC Verification Status',
              colorScheme: colorScheme,
            ),
            _ProfileTile(
              icon: Icons.settings_outlined,
              label: 'Practice Settings',
              colorScheme: colorScheme,
            ),
          ] else if (role == UserRole.operator) ...[
            // Operator Chamber Desk Box
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.meeting_room_outlined, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Chamber Desk Management',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage patient check-ins, serial tickets, and doctor chamber queues.',
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ProfileTile(
              icon: Icons.settings_outlined,
              label: 'Desk Settings',
              colorScheme: colorScheme,
            ),
          ],

          const SizedBox(height: 12),
          _ProfileTile(
            icon: Icons.logout,
            label: 'Log Out',
            colorScheme: colorScheme,
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final bool isDestructive;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.colorScheme,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontSize: 15)),
        trailing: isDestructive
            ? null
            : Icon(Icons.chevron_right, color: Colors.grey[400]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {},
      ),
    );
  }
}
