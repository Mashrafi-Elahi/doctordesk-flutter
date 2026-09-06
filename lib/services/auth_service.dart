import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_role_and_nav.dart';
import 'api_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static bool get isSignedIn => currentUser != null;

  static UserRoles _currentUserRoles = const UserRoles();
  static UserRoles get userRoles => _currentUserRoles;

  static bool _isGuestMode = false;
  static bool get isGuest => _isGuestMode && !isSignedIn;

  static Future<void> loadGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isGuestMode = prefs.getBool('is_guest_mode') ?? false;
  }

  static Future<void> setGuestMode(bool value) async {
    _isGuestMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest_mode', value);
    if (value) {
      _currentUserRoles = const UserRoles(
        isDoctor: false,
        isOperator: false,
        isAdmin: false,
        chamberCount: 0,
      );
      await saveRole(UserRole.patient);
    }
  }

  static void enableAdminRole() {
    _currentUserRoles = UserRoles(
      isDoctor: _currentUserRoles.isDoctor,
      isOperator: _currentUserRoles.isOperator,
      isAdmin: true,
      chamberCount: _currentUserRoles.chamberCount,
    );
  }

  static Future<UserRole> getSavedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool('is_guest_mode') ?? false;
    if (isGuest) return UserRole.patient;
    final roleStr = prefs.getString('user_role');
    if (roleStr == 'admin') return UserRole.admin;
    if (roleStr == 'doctor') return UserRole.doctor;
    if (roleStr == 'operator') return UserRole.operator;
    return UserRole.patient;
  }

  static Future<void> saveRole(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role.name);
  }

  /// Refreshes and returns the additive roles from backend MongoDB
  static Future<UserRoles> fetchUserRoles() async {
    try {
      final uid = currentUser?.uid ?? 'demo-user-uid';
      final profile = await ApiService.fetchUserProfile(uid);
      if (profile != null) {
        _currentUserRoles = UserRoles.fromJson(profile);
        return _currentUserRoles;
      }
    } catch (e) {
      debugPrint('Error fetching user roles: $e');
    }

    // If logged in with demo email or anonymous with demo name, default to multi-role demo capability
    if (currentUser?.email == 'demo@mail.com' || (currentUser?.displayName?.contains('Demo') ?? false)) {
      _currentUserRoles = const UserRoles(
        isDoctor: true,
        isOperator: true,
        isAdmin: true,
        chamberCount: 1,
      );
      return _currentUserRoles;
    }

    _currentUserRoles = const UserRoles(
      isDoctor: false,
      isOperator: false,
      chamberCount: 0,
    );
    return _currentUserRoles;
  }

  /// Sign in with email and password
  static Future<UserCredential?> signInWithEmailPassword(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      await fetchUserRoles();
      await setGuestMode(false);
      return credential;
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  /// Sign up with email and password
  static Future<UserCredential?> signUpWithEmailPassword(
    String email,
    String password, {
    String? name,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      if (name != null && name.isNotEmpty) {
        await credential.user?.updateDisplayName(name);
      }
      await ApiService.syncUser(
        uid: credential.user!.uid,
        email: email.trim(),
        name: name ?? '',
      );
      await fetchUserRoles();
      await setGuestMode(false);
      return credential;
    } catch (e) {
      debugPrint('Sign up error: $e');
      rethrow;
    }
  }

  /// Real demo account login (demo@mail.com / demo1234)
  /// Seeds real session linked to seeded Doctor + Chamber + Appointments in MongoDB.
  static Future<bool> quickLoginDemo() async {
    const demoEmail = 'demo@mail.com';
    const demoPassword = 'demo';

    try {
      UserCredential? cred;
      try {
        cred = await _auth.signInWithEmailAndPassword(
          email: demoEmail,
          password: demoPassword,
        );
      } catch (authError) {
        // If not in Firebase Auth, create it
        try {
          cred = await _auth.createUserWithEmailAndPassword(
            email: demoEmail,
            password: demoPassword,
          );
        } catch (_) {
          // Fallback to anonymous demo session if network restricts Firebase
          cred = await _auth.signInAnonymously();
        }
      }

      await cred.user?.updateDisplayName('Dr. Rafiqul Islam (Demo)');

      // Sync with backend user profile
      if (cred.user != null) {
        await ApiService.syncUser(
          uid: cred.user!.uid,
          email: demoEmail,
          name: 'Dr. Rafiqul Islam (Demo)',
        );
      }

      await fetchUserRoles();
      await saveRole(UserRole.doctor);
      await setGuestMode(false);
      return true;
    } catch (e) {
      debugPrint('quickLoginDemo error: $e');
      // Even if offline, enable multi-role demo state locally
      _currentUserRoles = const UserRoles(
        isDoctor: true,
        isOperator: true,
        isAdmin: true,
        chamberCount: 1,
      );
      await saveRole(UserRole.doctor);
      await setGuestMode(false);
      return true;
    }
  }

  /// Log out from Firebase and reset roles
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    _currentUserRoles = const UserRoles();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
    await setGuestMode(true);
  }
}
