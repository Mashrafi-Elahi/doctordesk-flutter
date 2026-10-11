// app_role_and_nav.dart
//
// Single source of truth for app roles, additive multi-role capabilities,
// bottom navigation labels/icons, and auth entry points.

import 'package:flutter/material.dart';
import '../models/user_role.dart';
import 'google_sign_in_button.dart';

export '../models/user_role.dart';

/// Roles are additive flags on ONE user, not an exclusive account type.
/// Every signed-in (or guest) user is implicitly a patient — no flag needed.
class UserRoles {
  final bool isDoctor;
  final bool isOperator;
  final bool isAdmin;
  final bool isModerator;
  final int chamberCount; // 0 means "hide Manage/Desk tab entirely"

  const UserRoles({
    this.isDoctor = false,
    this.isOperator = false,
    this.isAdmin = false,
    this.isModerator = false,
    this.chamberCount = 0,
  });

  factory UserRoles.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'] as Map<String, dynamic>? ?? {};
    return UserRoles(
      isDoctor: roles['isDoctor'] == true,
      isOperator: roles['isOperator'] == true,
      isAdmin: roles['isAdmin'] == true,
      isModerator: roles['isModerator'] == true,
      chamberCount: (json['chamberCount'] as int?) ?? 0,
    );
  }

  /// Feed & Q&A Permission Rules:
  /// - Doctor can post video, answer FAQ, and post in feed
  /// - Patient and operator can comment and ask questions, but cannot answer or post video
  /// - Admin and Moderator can do all
  /// - Admin can remove moderator, moderator cannot
  bool get canPostVideo => isDoctor || isAdmin || isModerator;
  bool get canPostFeed => isDoctor || isAdmin || isModerator;
  bool get canAnswerFaq => isDoctor || isAdmin || isModerator;
  bool get canManageModerators => isAdmin;

  List<AppRole> get availableRoles => [
        AppRole.patient,
        if (isDoctor) AppRole.doctor,
        if (isOperator) AppRole.operator,
        if (isAdmin) AppRole.admin,
      ];

  bool get hasMultipleRoles => availableRoles.length > 1;
}

/// Single source of truth for the 3rd bottom-nav tab. Every screen must read
/// from here instead of hardcoding a label — this prevents drifting across screens.
class AppBottomNavConfig {
  static String thirdTabLabel(AppRole role) => switch (role) {
        AppRole.patient => 'Appointments',
        AppRole.doctor => 'Manage',
        AppRole.operator => 'Desk',
        AppRole.admin => 'Admin',
      };

  static IconData thirdTabIcon(AppRole role) => switch (role) {
        AppRole.patient => Icons.calendar_today_outlined,
        AppRole.doctor => Icons.dashboard_customize_outlined,
        AppRole.operator => Icons.grid_view_outlined,
        AppRole.admin => Icons.admin_panel_settings_outlined,
      };

  static IconData thirdTabSelectedIcon(AppRole role) => switch (role) {
        AppRole.patient => Icons.calendar_today,
        AppRole.doctor => Icons.dashboard_customize,
        AppRole.operator => Icons.grid_view,
        AppRole.admin => Icons.admin_panel_settings,
      };

  /// Doctor/operator only see their management tab if they actually have a
  /// chamber to manage. Patient's Appointments tab always shows. Admin console always shows.
  static bool showThirdTab(AppRole role, UserRoles roles) {
    if (role == AppRole.admin) return true;
    if (role == AppRole.doctor || role == AppRole.operator) {
      return roles.chamberCount > 0;
    }
    return true;
  }
}

/// Shown only in Profile when a user actually has more than one role.
/// Single-role users never see this — no clutter for the common case.
class RoleSwitcher extends StatelessWidget {
  final UserRoles roles;
  final AppRole current;
  final ValueChanged<AppRole> onSwitch;

  const RoleSwitcher({
    super.key,
    required this.roles,
    required this.current,
    required this.onSwitch,
  });

  String _label(AppRole r) => switch (r) {
        AppRole.patient => 'Patient view',
        AppRole.doctor => 'Doctor view',
        AppRole.operator => 'Operator view',
        AppRole.admin => 'Admin Console',
      };

  @override
  Widget build(BuildContext context) {
    if (!roles.hasMultipleRoles) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACTIVE PORTAL VIEW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: roles.availableRoles.map((r) {
              return ChoiceChip(
                label: Text(_label(r)),
                selected: current == r,
                onSelected: (_) => onSwitch(r),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Auth entry buttons for signed-out placeholder views.
/// Replaces the old lone mock modal trigger with clean Log In / Sign Up / Guest options.
class AuthEntryButtons extends StatelessWidget {
  final VoidCallback onLogIn;
  final VoidCallback onSignUp;
  final VoidCallback onContinueAsGuest;
  final VoidCallback? onGoogleSignIn;

  const AuthEntryButtons({
    super.key,
    required this.onLogIn,
    required this.onSignUp,
    required this.onContinueAsGuest,
    this.onGoogleSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: onLogIn,
          child: const Text('Log In'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onSignUp,
          child: const Text('Sign Up'),
        ),
        if (onGoogleSignIn != null) ...[
          const SizedBox(height: 8),
          GoogleSignInButton(
            text: 'Continue with Google',
            onPressed: onGoogleSignIn,
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: onContinueAsGuest,
          child: const Text('Continue as Guest'),
        ),
      ],
    );
  }
}
