import 'package:flutter/material.dart';
import '../widgets/app_role_and_nav.dart';
import '../widgets/google_sign_in_button.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'feed_screen.dart';
import 'appointment_screen.dart';
import 'doctor_manager_screen.dart';
import 'operator_desk_screen.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';
import 'admin_console_screen.dart';
import '../widgets/app_drawer.dart';

class MainShell extends StatefulWidget {
  final UserRole initialRole;

  const MainShell({
    super.key,
    this.initialRole = UserRole.patient,
  });

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  late UserRole _currentRole;
  UserRoles _userRoles = const UserRoles();

  @override
  void initState() {
    super.initState();
    _currentRole = widget.initialRole;
    _refreshRoles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AuthService.isSignedIn && !AuthService.isGuest) {
        _showInitialAuthPrompt();
      }
    });
  }

  Future<void> _refreshRoles() async {
    final roles = await AuthService.fetchUserRoles();
    if (mounted) {
      setState(() {
        _userRoles = roles;
      });
    }
  }

  void setRole(UserRole role) {
    setState(() {
      _currentRole = role;
      _userRoles = AuthService.userRoles;
      // If the middle tab becomes hidden and was selected, switch to Home
      if (!AppBottomNavConfig.showThirdTab(_currentRole, _userRoles) && _currentIndex == 2) {
        _currentIndex = 0;
      }
    });
    AuthService.saveRole(role);
  }

  void switchToTab(int index, {String? searchQuery}) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _showInitialAuthPrompt() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 64,
                  width: 64,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Welcome to DoctorDesk',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to access your role-specific desk, chambers, and health records, or continue as a guest.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              AuthEntryButtons(
                onLogIn: () {
                  Navigator.pop(ctx);
                  _showAuthModal(isSignUp: false);
                },
                onSignUp: () {
                  Navigator.pop(ctx);
                  _showAuthModal(isSignUp: true);
                },
                onGoogleSignIn: () async {
                  try {
                    final cred = await AuthService.signInWithGoogle();
                    if (cred != null) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _refreshRoles();
                      if (mounted) setState(() {});
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Google Sign-in failed: ${e.toString().replaceAll("Exception:", "").trim()}'),
                        ),
                      );
                    }
                  }
                },
                onContinueAsGuest: () async {
                  await AuthService.setGuestMode(true);
                  if (ctx.mounted) Navigator.pop(ctx);
                  setRole(UserRole.patient);
                  switchToTab(0);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Continuing as Guest Patient. You can browse specialists and check symptoms freely.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onDemoQuickLogin: () async {
                  await AuthService.quickLoginDemo();
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _refreshRoles();
                  setRole(UserRole.doctor);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Logged in to seeded demo account (Doctor view active)'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAuthModal({bool isSignUp = false}) {
    final emailController = TextEditingController();
    final passController = TextEditingController();
    final nameController = TextEditingController();
    bool isCurrentSignUp = isSignUp;
    bool loading = false;
    bool googleLoading = false;
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
                        isCurrentSignUp ? 'Create Account' : 'Welcome Back',
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
                  if (isCurrentSignUp) ...[
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
                    onPressed: (loading || googleLoading)
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
                              if (isCurrentSignUp) {
                                await AuthService.signUpWithEmailPassword(
                                  email,
                                  pass,
                                  name: nameController.text.trim(),
                                );
                              } else {
                                await AuthService.signInWithEmailPassword(email, pass);
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _refreshRoles();
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
                        : Text(isCurrentSignUp ? 'Sign Up' : 'Log In'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GoogleSignInButton(
                    text: isCurrentSignUp ? 'Sign up with Google' : 'Sign in with Google',
                    isLoading: googleLoading,
                    onPressed: (loading || googleLoading)
                        ? null
                        : () async {
                            setModalState(() {
                              googleLoading = true;
                              authError = null;
                            });
                            try {
                              final cred = await AuthService.signInWithGoogle();
                              if (cred != null) {
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _refreshRoles();
                                if (mounted) setState(() {});
                              } else {
                                setModalState(() => googleLoading = false);
                              }
                            } catch (e) {
                              setModalState(() {
                                googleLoading = false;
                                authError = e.toString().replaceAll('Exception:', '').trim();
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setModalState(() {
                        isCurrentSignUp = !isCurrentSignUp;
                        authError = null;
                      });
                    },
                    child: Text(
                      isCurrentSignUp
                          ? 'Already have an account? Log In'
                          : "Don't have an account? Sign Up",
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _getMiddleScreen() => switch (_currentRole) {
        AppRole.patient => const AppointmentScreen(),
        AppRole.doctor => const DoctorManagerScreen(),
        AppRole.operator => const OperatorDeskScreen(),
        AppRole.admin => AdminConsoleScreen(onRoleChanged: setRole),
      };

  @override
  Widget build(BuildContext context) {
    final showThirdTab = AppBottomNavConfig.showThirdTab(_currentRole, _userRoles);

    // Build the dynamic pages and navigation destinations list
    final List<Widget> pages = [
      HomeScreen(onTabSwitch: switchToTab),
      const FeedScreen(),
      if (showThirdTab) _getMiddleScreen(),
      const InboxScreen(),
      ProfileScreen(
        role: _currentRole,
        onRoleChanged: setRole,
        onTabSwitch: switchToTab,
      ),
    ];

    // Ensure selected index is clamped within bounds
    final selectedIndex = _currentIndex.clamp(0, pages.length - 1);

    final List<NavigationDestination> destinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.dynamic_feed_outlined),
        selectedIcon: Icon(Icons.dynamic_feed),
        label: 'Feed',
      ),
      if (showThirdTab)
        NavigationDestination(
          icon: Icon(AppBottomNavConfig.thirdTabIcon(_currentRole)),
          selectedIcon: Icon(AppBottomNavConfig.thirdTabSelectedIcon(_currentRole)),
          label: AppBottomNavConfig.thirdTabLabel(_currentRole),
        ),
      const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        selectedIcon: Icon(Icons.chat_bubble),
        label: 'Inbox',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    ];

    return Scaffold(
      drawer: AppDrawer(
        currentRole: _currentRole,
        onRoleChanged: setRole,
      ),
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: destinations,
      ),
    );
  }
}
