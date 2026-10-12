// app_role_and_nav.dart
//
// Single source of truth for app roles, additive multi-role capabilities,
// bottom navigation labels/icons, and auth entry points.

import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../services/app_language.dart';
import '../theme/app_constants.dart';
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
  final String? doctorProfileId;
  final List<String> operatorAssignments;

  const UserRoles({
    this.isDoctor = false,
    this.isOperator = false,
    this.isAdmin = false,
    this.isModerator = false,
    this.chamberCount = 0,
    this.doctorProfileId,
    this.operatorAssignments = const [],
  });

  factory UserRoles.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'] as Map<String, dynamic>? ?? {};
    return UserRoles(
      isDoctor: roles['isDoctor'] == true,
      isOperator: roles['isOperator'] == true,
      isAdmin: roles['isAdmin'] == true,
      isModerator: roles['isModerator'] == true,
      chamberCount: (json['chamberCount'] as num?)?.toInt() ?? 0,
      doctorProfileId: json['doctorProfileId']?.toString(),
      operatorAssignments: (json['operatorAssignments'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
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
        AppRole.patient => tr('Appointments'),
        AppRole.doctor => tr('Manage'),
        AppRole.operator => tr('Desk'),
        AppRole.admin => tr('Admin'),
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

  /// Doctor/operator always see their respective tab when in that role so
  /// they can add/manage chambers and run desk queues. Patient's Appointments tab always shows. Admin console always shows.
  static bool showThirdTab(AppRole role, UserRoles roles) {
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
        AppRole.patient => tr('Patient'),
        AppRole.doctor => tr('Doctor'),
        AppRole.operator => tr('Operator'),
        AppRole.admin => tr('Admin'),
      };

  @override
  Widget build(BuildContext context) {
    if (!roles.hasMultipleRoles) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        boxShadow: AppConstants.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE PORTAL',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: roles.availableRoles.map((r) {
                final isSelected = current == r;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppConstants.radiusChip),
                    onTap: () => onSwitch(r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryTint : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppConstants.radiusChip),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.borderSubtle,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            const Icon(Icons.check, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _label(r),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
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
