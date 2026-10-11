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
  static Future<UserCredential?> signInWithEmailPassword(
    String email,
    String password, {
    bool isDoctor = false,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      if (isDoctor) {
        await ApiService.syncUser(
          uid: credential.user!.uid,
          email: email.trim(),
          role: 'doctor',
          isDoctor: true,
        );
      }
      await fetchUserRoles();
      if (isDoctor) {
        await saveRole(UserRole.doctor);
      }
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
    String? phone,
    String? role,
    bool isDoctor = false,
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
        phone: phone ?? '',
        role: role ?? (isDoctor ? 'doctor' : 'patient'),
        isDoctor: isDoctor,
      );
      await fetchUserRoles();
      if (isDoctor) {
        await saveRole(UserRole.doctor);
      }
      await setGuestMode(false);
      return credential;
    } catch (e) {
      debugPrint('Sign up error: $e');
      rethrow;
    }
  }

  /// Sign in or Sign up with Google OAuth
  static Future<UserCredential?> signInWithGoogle({bool isDoctor = false}) async {
    try {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');

      UserCredential credential;
      if (kIsWeb) {
        credential = await _auth.signInWithPopup(googleProvider);
      } else {
        credential = await _auth.signInWithProvider(googleProvider);
      }

      final user = credential.user;
      if (user != null) {
        await ApiService.syncUser(
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? '',
          role: isDoctor ? 'doctor' : 'patient',
          isDoctor: isDoctor,
        );
      }
      await fetchUserRoles();
      if (isDoctor) {
        await saveRole(UserRole.doctor);
      }
      await setGuestMode(false);
      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' || e.code == 'canceled') {
        debugPrint('Google sign in cancelled by user');
        return null;
      }
      debugPrint('Google sign in FirebaseAuthException: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Google Sign-in error: $e');
      rethrow;
    }
  }

  /// Trigger phone verification via SMS OTP
  static Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException error) onVerificationFailed,
    required void Function(PhoneAuthCredential credential) onVerificationCompleted,
    void Function(String verificationId)? onCodeAutoRetrievalTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.trim(),
      verificationCompleted: onVerificationCompleted,
      verificationFailed: onVerificationFailed,
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        onCodeAutoRetrievalTimeout?.call(verificationId);
      },
      timeout: const Duration(seconds: 60),
    );
  }

  /// Complete phone verification and sign in / sign up with OTP
  static Future<UserCredential?> signInWithPhoneOtp({
    required String verificationId,
    required String smsCode,
    String? name,
    String? phone,
    String? role,
    bool isDoctor = false,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      final userCred = await _auth.signInWithCredential(credential);

      if (name != null && name.isNotEmpty) {
        await userCred.user?.updateDisplayName(name);
      }

      await ApiService.syncUser(
        uid: userCred.user!.uid,
        email: userCred.user!.email ?? '',
        name: name ?? (userCred.user!.displayName ?? ''),
        phone: phone ?? (userCred.user!.phoneNumber ?? ''),
        role: role ?? (isDoctor ? 'doctor' : 'patient'),
        isDoctor: isDoctor,
      );

      await fetchUserRoles();
      if (isDoctor) {
        await saveRole(UserRole.doctor);
      }
      await setGuestMode(false);
      return userCred;
    } catch (e) {
      debugPrint('Phone OTP sign-in error: $e');
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
