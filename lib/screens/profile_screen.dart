import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_constants.dart';
import '../theme/app_theme.dart';
import '../widgets/app_role_and_nav.dart';
import '../widgets/auth_modal.dart';
import '../widgets/first_time_checkin_dialog.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/app_language.dart';
import '../services/tts_service.dart';
import 'settings_screen.dart';
import 'admin_console_screen.dart';
import '../widgets/health_documents_widget.dart';

class ProfileScreen extends StatefulWidget {
  final UserRole role;
  final ValueChanged<UserRole>? onRoleChanged;
  final ValueChanged<int>? onTabSwitch;

  const ProfileScreen({
    super.key,
    this.role = UserRole.patient,
    this.onRoleChanged,
    this.onTabSwitch,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool get _isSignedIn => AuthService.isSignedIn;
  UserRoles _userRoles = AuthService.userRoles;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserRoles();
  }

  Future<void> _loadUserRoles() async {
    final roles = await AuthService.fetchUserRoles();
    final uid = AuthService.currentUser?.uid;
    if (uid != null) {
      _userProfile = await DataService.fetchUserProfile(uid);
    }
    if (mounted) {
      setState(() {
        _userRoles = roles;
      });
    }
  }

  Future<void> _showDoctorApplicationDialog() async {
    final phoneController = TextEditingController(
        text: _userProfile?['phone'] ??
            AuthService.currentUser?.phoneNumber ??
            '');
    final bmdcController = TextEditingController(
        text: _userProfile?['bmdcRegNumber'] ??
            _userProfile?['doctorApplication']?['bmdcNumber'] ??
            '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Doctor Application', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Doctor role is allocated via database. Enter your phone number and BMDC registration number.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Doctor Phone Number (Required)',
                  hintText: 'e.g. 017XXXXXXXX',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bmdcController,
                decoration: const InputDecoration(
                  labelText: 'BMDC Registration Number (Optional)',
                  hintText: 'e.g. A-12345',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (phoneController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Submit Application'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final uid = AuthService.currentUser?.uid;
      if (uid != null) {
        await DataService.applyForDoctorRole(
          uid: uid,
          phone: phoneController.text.trim(),
          bmdcNumber: bmdcController.text.trim(),
          name: AuthService.currentUser?.displayName,
        );
        await _loadUserRoles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Doctor application submitted! Admin will review and verify your BMDC.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _showEditProfileDialog() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;

    final firstNameCtrl =
        TextEditingController(text: _userProfile?['firstName'] ?? '');
    final lastNameCtrl =
        TextEditingController(text: _userProfile?['lastName'] ?? '');
    final usernameCtrl = TextEditingController(
      text: _userProfile?['username'] ??
          AuthService.currentUser?.displayName ??
          '',
    );
    final phoneCtrl = TextEditingController(
      text:
          _userProfile?['phone'] ?? AuthService.currentUser?.phoneNumber ?? '',
    );
    final designationCtrl =
        TextEditingController(text: _userProfile?['designation'] ?? '');
    final degreesCtrl =
        TextEditingController(text: _userProfile?['degrees'] ?? '');
    final bmdcCtrl =
        TextEditingController(text: _userProfile?['bmdcRegNumber'] ?? '');

    final isDoctorRole = _userRoles.isDoctor || widget.role == UserRole.doctor;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'First Name',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lastNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Last Name',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Username / Display Name',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: designationCtrl,
                decoration: const InputDecoration(
                    labelText: 'Designation (e.g. Consultant / Patient)',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
              if (isDoctorRole) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: degreesCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Degrees (e.g. MBBS, FCPS)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bmdcCtrl,
                  decoration: const InputDecoration(
                      labelText: 'BMDC Registration ID',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Details'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      try {
        final fName = firstNameCtrl.text.trim();
        final lName = lastNameCtrl.text.trim();
        final uName = usernameCtrl.text.trim();
        final fullName = uName.isNotEmpty ? uName : '$fName $lName'.trim();

        final updates = <String, dynamic>{
          'firstName': fName,
          'lastName': lName,
          'username': uName,
          'name': fullName,
          'phone': phoneCtrl.text.trim(),
          'designation': designationCtrl.text.trim(),
        };

        if (isDoctorRole) {
          updates['degrees'] = degreesCtrl.text.trim();
          updates['bmdcRegNumber'] = bmdcCtrl.text.trim();
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(updates, SetOptions(merge: true));

        if (fullName.isNotEmpty) {
          await AuthService.currentUser?.updateDisplayName(fullName);
        }

        await _loadUserRoles();
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Profile details updated successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error updating profile: $e')));
        }
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New Password (min 6 chars)',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (passCtrl.text.trim().length < 6) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Password must be at least 6 characters.')));
                return;
              }
              if (passCtrl.text.trim() != confirmCtrl.text.trim()) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match.')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Update Password'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await AuthService.currentUser?.updatePassword(passCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Could not change password: ${e.toString().replaceAll("Exception:", "").trim()}')),
          );
        }
      }
    }
  }

  String _getRoleDisplayName() {
    final user = AuthService.currentUser;
    final profileName = _userProfile?['name']?.toString().trim();
    if (profileName != null && profileName.isNotEmpty) return profileName;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName!;
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email!.split('@').first;
    }
    return switch (widget.role) {
      UserRole.doctor => 'Doctor',
      UserRole.operator => 'Chamber Operator',
      UserRole.admin => 'Administrator',
      UserRole.patient => 'Guest Patient',
    };
  }

  String _getRoleSubtitle() {
    if (!_isSignedIn) {
      return 'Sign in to access your role-specific desk, chambers, and records';
    }
    return switch (widget.role) {
      UserRole.doctor => 'BMDC Verified Specialist • Active Doctor Account',
      UserRole.operator => 'Live Chamber Queue Desk • Active Operator Account',
      UserRole.admin => 'Backend Controller • Database & Server Operations',
      UserRole.patient =>
        tr('Medical records, mood journal, and appointments synced'),
    };
  }

  void _showAuthModal(BuildContext context, {bool isSignUp = false}) {
    showDoctorDeskAuthModal(
      context,
      isSignUp: isSignUp,
      onAuthenticated: () async {
        await _loadUserRoles();
        if (mounted) setState(() {});
        if (context.mounted) {
          await showFirstTimeCheckinDialog(context);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.role) {
      UserRole.doctor => 'Doctor Profile & Chambers',
      UserRole.operator => 'Chamber Desk Profile',
      UserRole.admin => 'Administrator Profile',
      UserRole.patient => 'Patient Profile',
    };

    final emailOrPhone = AuthService.currentUser?.email?.isNotEmpty == true
        ? AuthService.currentUser!.email!
        : (AuthService.currentUser?.phoneNumber?.isNotEmpty == true
            ? AuthService.currentUser!.phoneNumber!
            : _getRoleSubtitle());

    final List<_SettingsItem> settingsItems = [
      if (_isSignedIn) ...[
        _SettingsItem(
          icon: Icons.person_outline,
          title: 'Profile Details',
          onTap: _showEditProfileDialog,
        ),
        _SettingsItem(
          icon: Icons.lock_reset_outlined,
          title: 'Change Password',
          onTap: _showChangePasswordDialog,
        ),
      ],
      if (widget.role == UserRole.patient)
        _SettingsItem(
          icon: Icons.settings_outlined,
          title: 'Settings',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const SettingsScreen(role: UserRole.patient)),
          ),
        )
      else if (widget.role == UserRole.doctor)
        _SettingsItem(
          icon: Icons.tune_outlined,
          title: 'Practice Settings',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const SettingsScreen(role: UserRole.doctor)),
          ),
        )
      else if (widget.role == UserRole.operator)
        _SettingsItem(
          icon: Icons.desk_outlined,
          title: 'Desk Settings',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const SettingsScreen(role: UserRole.operator)),
          ),
        ),
      _SettingsItem(
        icon: Icons.notifications_outlined,
        title: 'Notifications',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SettingsScreen(
                    role: widget.role,
                    initialSection: 'notifications',
                  )),
        ),
      ),
      _SettingsItem(
        icon: Icons.language_outlined,
        title: 'Language',
        onTap: () => _pickLanguageDialog(context),
      ),
      _SettingsItem(
        icon: Icons.help_outline,
        title: 'Help & FAQ',
        onTap: () => _showHelpDialog(context),
      ),
      _SettingsItem(
        icon: Icons.shield_outlined,
        title: 'Terms & Privacy',
        onTap: () => _showTermsDialog(context),
      ),
      if (_userRoles.isAdmin)
        _SettingsItem(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Admin Console & Database Control',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AdminConsoleScreen(onRoleChanged: widget.onRoleChanged),
            ),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const SizedBox(height: 8),
            // Top Hero
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primaryTint,
                    child: Icon(
                      widget.role == UserRole.doctor
                          ? Icons.local_hospital_outlined
                          : widget.role == UserRole.operator
                              ? Icons.business_outlined
                              : Icons.person,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getRoleDisplayName(),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      emailOrPhone,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (widget.role == UserRole.doctor) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusChip),
                        border: Border.all(color: AppColors.success, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 16, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            'BMDC & NID Verified Specialist',
                            style: GoogleFonts.poppins(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Multi-role Switcher
                  if (_isSignedIn && _userRoles.hasMultipleRoles) ...[
                    RoleSwitcher(
                      roles: _userRoles,
                      current: widget.role,
                      onSwitch: (newRole) {
                        widget.onRoleChanged?.call(newRole);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // If signed out: Auth Entry Buttons
                  if (!_isSignedIn) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: AuthEntryButtons(
                        onLogIn: () => _showAuthModal(context, isSignUp: false),
                        onSignUp: () => _showAuthModal(context, isSignUp: true),
                        onGoogleSignIn: () async {
                          try {
                            final cred = await AuthService.signInWithGoogle();
                            if (cred != null) {
                              await _loadUserRoles();
                              if (mounted) setState(() {});
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Google Sign-in failed: ${e.toString().replaceAll("Exception:", "").trim()}'),
                                ),
                              );
                            }
                          }
                        },
                        onContinueAsGuest: () async {
                          await AuthService.setGuestMode(true);
                          widget.onRoleChanged?.call(UserRole.patient);
                          widget.onTabSwitch?.call(0);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Continuing as Guest Patient. You can search doctors and check symptoms freely.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),

            // Role-specific section
            if (widget.role == UserRole.patient) ...[
              const HealthDocumentsWidget(),
              const SizedBox(height: 16),
              if (_isSignedIn && !_userRoles.isDoctor) ...[
                Card(
                  color: AppColors.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusCard),
                    side: const BorderSide(
                        color: AppColors.borderSubtle, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.screenPadding),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primaryTint,
                          child: Icon(Icons.medical_services_outlined,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Are you a Doctor?',
                                  style: AppTheme.cardTitle),
                              const SizedBox(height: 2),
                              Text(
                                  'Apply for BMDC verification & directory listing.',
                                  style: AppTheme.caption),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _showDoctorApplicationDialog,
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ] else if (widget.role == UserRole.doctor) ...[
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Practice Overview', style: AppTheme.sectionTitle),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Chambers', style: AppTheme.caption),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_userRoles.chamberCount > 0 ? _userRoles.chamberCount : (_userProfile?['chamberCount'] ?? 1)}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Today's Patients",
                                      style: AppTheme.caption),
                                  const SizedBox(height: 4),
                                  Text(
                                    '0',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton),
                            ),
                          ),
                          onPressed: () {
                            widget.onTabSwitch?.call(2);
                          },
                          child: const Text('Manage Practice'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else if (widget.role == UserRole.operator) ...[
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Desk Status', style: AppTheme.sectionTitle),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Assigned Chamber',
                                      style: AppTheme.caption),
                                  const SizedBox(height: 4),
                                  Text(
                                    _userProfile?['operatorChamberName'] ??
                                        'Central Clinic Desk',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Today's Queue",
                                      style: AppTheme.caption),
                                  const SizedBox(height: 4),
                                  Text(
                                    '3 Waiting',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusButton),
                            ),
                          ),
                          onPressed: () {
                            widget.onTabSwitch?.call(2);
                          },
                          child: const Text('Open Desk'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Settings List Card
            _buildSettingsGroup(settingsItems),

            // Log Out Button
            if (_isSignedIn) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusButton),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(
                    'Log Out',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                  onPressed: () async {
                    await AuthService.signOut();
                    widget.onRoleChanged?.call(UserRole.patient);
                    if (context.mounted) {
                      setState(() {
                        _userRoles = const UserRoles();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Logged out. You are now browsing as guest.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<_SettingsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        boxShadow: AppConstants.softShadow,
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isLast = index == items.length - 1;

          return Column(
            children: [
              ListTile(
                leading: Icon(item.icon, color: AppColors.primary, size: 22),
                title: Text(
                  item.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.textSecondary),
                onTap: item.onTap,
              ),
              if (!isLast)
                const Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: AppColors.primaryTint,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _pickLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Language'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              AppLanguage.setLanguage('English');
              TtsService.instance.setLocale('en');
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('English (US)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              AppLanguage.setLanguage('Bengali');
              TtsService.instance.setLocale('bn');
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('বাংলা (Bengali)'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Help & FAQ'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How do I find a doctor?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'Use the search bar on Home to search by name or enter symptoms to automatically find the right specialist.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text(
                'What is Read Aloud mode?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'When enabled in Accessibility settings, tapping an item reads it aloud, and double-tapping opens it.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms & Privacy'),
        content: const Text(
          'DoctorDesk provides verified doctor discovery, chamber queue management, and health records synchronization.\n\nMedical recommendations are algorithmic guides and do not replace professional medical diagnosis.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });
}
