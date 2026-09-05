import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../screens/profile_screen.dart';

class ProfileAvatarButton extends StatelessWidget {
  final UserRole role;

  const ProfileAvatarButton({
    super.key,
    this.role = UserRole.patient,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: IconButton(
        tooltip: 'Profile',
        icon: CircleAvatar(
          radius: 16,
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(
            role == UserRole.doctor
                ? Icons.local_hospital_outlined
                : role == UserRole.operator
                    ? Icons.business_outlined
                    : Icons.person_outline,
            size: 18,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(role: role),
            ),
          );
        },
      ),
    );
  }
}
