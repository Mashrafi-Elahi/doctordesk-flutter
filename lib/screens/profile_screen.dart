import 'package:flutter/material.dart';
import '../widgets/app_role_and_nav.dart';
import '../services/auth_service.dart';
import 'settings_screen.dart';
import 'admin_console_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserRoles();
  }

  Future<void> _loadUserRoles() async {
    final roles = await AuthService.fetchUserRoles();
    if (mounted) {
      setState(() {
        _userRoles = roles;
      });
    }
  }

  String _getRoleDisplayName() {
    final user = AuthService.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName!;
    }
    return switch (widget.role) {
      UserRole.doctor => 'Dr. Rafiqul Islam',
      UserRole.operator => 'Popular Diagnostic Desk Operator',
      UserRole.admin => 'System Administrator',
      UserRole.patient => _isSignedIn ? 'Karim Rahman' : 'Guest Patient',
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
      UserRole.patient => 'Medical records, mood journal, and appointments synced',
    };
  }

  void _showAuthModal(BuildContext context, {bool isSignUp = false}) {
    final emailController = TextEditingController();
    final passController = TextEditingController();
    final nameController = TextEditingController();
    bool loading = false;
    String? authError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isSignUp ? 'Create Account' : 'Welcome Back',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (authError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        authError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (isSignUp) ...[
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: loading
                        ? null
                        : () async {
                            final email = emailController.text.trim();
                            final pass = passController.text.trim();
                            if (email.isEmpty || pass.isEmpty) {
                              setModalState(() => authError = 'Please fill in all fields.');
                              return;
                            }
                            setModalState(() {
                              loading = true;
                              authError = null;
                            });

                            try {
                              if (isSignUp) {
                                await AuthService.signUpWithEmailPassword(
                                  email,
                                  pass,
                                  name: nameController.text.trim(),
                                );
                              } else {
                                await AuthService.signInWithEmailPassword(email, pass);
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadUserRoles();
                              if (mounted) setState(() {});
                            } catch (e) {
                              setModalState(() {
                                loading = false;
                                authError = e.toString().replaceAll('Exception:', '').trim();
                              });
                            }
                          },
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(isSignUp ? 'Sign Up' : 'Log In'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final title = switch (widget.role) {
      UserRole.doctor => 'Doctor Profile & Chambers',
      UserRole.operator => 'Chamber Desk Profile',
      UserRole.admin => 'Administrator Profile',
      UserRole.patient => 'Patient Profile',
    };

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
                    widget.role == UserRole.doctor
                        ? Icons.local_hospital_outlined
                        : widget.role == UserRole.operator
                            ? Icons.business_outlined
                            : Icons.person,
                    size: 40,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _getRoleDisplayName(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    _getRoleSubtitle(),
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),

                // Multi-role Switcher — Only shows if the user actually has more than one capability
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

                // If signed out: Auth Entry Buttons (Log In, Sign Up, Guest, and Dev Quick Login)
                if (!_isSignedIn) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: AuthEntryButtons(
                      onLogIn: () => _showAuthModal(context, isSignUp: false),
                      onSignUp: () => _showAuthModal(context, isSignUp: true),
                      onContinueAsGuest: () async {
                        await AuthService.setGuestMode(true);
                        widget.onRoleChanged?.call(UserRole.patient);
                        widget.onTabSwitch?.call(0);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Continuing as Guest Patient. You can search doctors and check symptoms freely.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      onDemoQuickLogin: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await AuthService.quickLoginDemo();
                        await _loadUserRoles();
                        widget.onRoleChanged?.call(UserRole.doctor);
                        if (!mounted) return;
                        setState(() {});
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Logged in to seeded demo account (Doctor + Operator views active)'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),

          if (widget.role == UserRole.patient) ...[
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
                          SnackBar(
                            content: Text(_isSignedIn
                                ? 'Report upload ready — select file from device storage.'
                                : 'Sign in to sync uploaded medical reports.'),
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
              isSignedIn: _isSignedIn,
              onCustomTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(role: widget.role),
                  ),
                );
              },
            ),
            _ProfileTile(
              icon: Icons.favorite_outline,
              label: 'Saved Doctors',
              colorScheme: colorScheme,
              isSignedIn: _isSignedIn,
            ),
            _ProfileTile(
              icon: Icons.rate_review_outlined,
              label: 'My Reviews',
              colorScheme: colorScheme,
              isSignedIn: _isSignedIn,
            ),
            _ProfileTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              colorScheme: colorScheme,
              isSignedIn: _isSignedIn,
              onCustomTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(role: widget.role),
                  ),
                );
              },
            ),
          ] else if (widget.role == UserRole.doctor) ...[
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
                      'Manage your chamber locations, visiting hours, and consultation fees from the Manage tab.',
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ProfileTile(
              icon: Icons.verified_user_outlined,
              label: 'BMDC Verification Status: Verified',
              colorScheme: colorScheme,
              isSignedIn: true,
              onCustomTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(role: UserRole.doctor, initialSection: 'bmdc'),
                  ),
                );
              },
            ),
            _ProfileTile(
              icon: Icons.settings_outlined,
              label: 'Practice Settings',
              colorScheme: colorScheme,
              isSignedIn: true,
              onCustomTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(role: UserRole.doctor),
                  ),
                );
              },
            ),
          ] else if (widget.role == UserRole.operator) ...[
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
                      'Manage patient check-ins, serial tickets, and doctor chamber queues from the Desk tab.',
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
              isSignedIn: true,
              onCustomTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(role: UserRole.operator),
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 12),
          _ProfileTile(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Admin Console & Backend Control',
            colorScheme: colorScheme,
            isSignedIn: true,
            onCustomTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminConsoleScreen(onRoleChanged: widget.onRoleChanged),
                ),
              );
            },
          ),

          if (_isSignedIn) ...[
            const SizedBox(height: 12),
            _ProfileTile(
              icon: Icons.logout,
              label: 'Log Out',
              colorScheme: colorScheme,
              isDestructive: true,
              isSignedIn: _isSignedIn,
              onCustomTap: () async {
                await AuthService.signOut();
                widget.onRoleChanged?.call(UserRole.patient);
                if (context.mounted) {
                  setState(() {
                    _userRoles = const UserRoles();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged out. You are now browsing as guest.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
          ],
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
  final bool isSignedIn;
  final VoidCallback? onCustomTap;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.colorScheme,
    this.isDestructive = false,
    this.isSignedIn = false,
    this.onCustomTap,
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
        onTap: onCustomTap ??
            () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isDestructive
                        ? (isSignedIn ? 'Logging out...' : 'You are currently browsing as a guest.')
                        : (isSignedIn ? '$label settings open.' : 'Sign in to access $label.'),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
      ),
    );
  }
}
