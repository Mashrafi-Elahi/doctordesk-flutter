import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'google_sign_in_button.dart';

/// Shows one account entry point. A signed-in user can apply for the doctor
/// role later; authentication itself never grants a privileged role.
void showDoctorDeskAuthModal(
  BuildContext context, {
  bool isSignUp = false,
  Future<void> Function()? onAuthenticated,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: _AuthModalContent(
        initialIsSignUp: isSignUp,
        onAuthenticated: onAuthenticated,
      ),
    ),
  );
}

class _AuthModalContent extends StatefulWidget {
  final bool initialIsSignUp;
  final Future<void> Function()? onAuthenticated;

  const _AuthModalContent({
    required this.initialIsSignUp,
    this.onAuthenticated,
  });

  @override
  State<_AuthModalContent> createState() => _AuthModalContentState();
}

class _AuthModalContentState extends State<_AuthModalContent> {
  late bool _isSignUp = widget.initialIsSignUp;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  final _nameController = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  String? _authError;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String _readableAuthError(Object error) {
    if (error is PlatformException &&
        (error.code == 'sign_in_failed' ||
            error.message?.contains('10') == true)) {
      return 'Google Sign-In is not configured for this Android build. Add this app\'s SHA-1 and SHA-256 in Firebase Console, download google-services.json again, then rebuild.';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-cert-hash':
          return 'Google Sign-In is not configured for this Android build. Add the app SHA-1/SHA-256 certificate in Firebase Console, then rebuild the APK.';
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Email or password is incorrect.';
        case 'email-already-in-use':
          return 'That email already has an account. Use Log In instead.';
        case 'weak-password':
          return 'Use a stronger password (at least 6 characters).';
        case 'network-request-failed':
          return 'Network error. Check the device connection and try again.';
        default:
          return error.message ?? 'Authentication failed (${error.code}).';
      }
    }
    return error.toString().replaceFirst('Exception:', '').trim();
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _authError = 'Please fill in both email and password.');
      return;
    }
    if (_isSignUp && password.length < 6) {
      setState(() => _authError = 'Use a password with at least 6 characters.');
      return;
    }
    if (_isSignUp && password != _confirmPassController.text) {
      setState(() => _authError = 'Passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _authError = null;
      _infoMessage = null;
    });
    try {
      if (_isSignUp) {
        await AuthService.signUpWithEmailPassword(
          email,
          password,
          name: _nameController.text.trim(),
          role: 'user',
        );
      } else {
        await AuthService.signInWithEmailPassword(email, password);
      }
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onAuthenticated?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _authError = _readableAuthError(error);
        });
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _authError = null;
        _infoMessage =
            'Enter your email address, then use Forgot password again.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _authError = null;
      _infoMessage = null;
    });
    try {
      await AuthService.sendPasswordResetEmail(email);
    } catch (error) {
      // This response must not reveal whether the address has an account.
      debugPrint('Password reset request failed: $error');
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _infoMessage =
            'If an account exists for that email, a password-reset link has been sent.';
      });
    }
  }

  Future<void> _handleGoogleAuth() async {
    setState(() {
      _googleLoading = true;
      _authError = null;
    });
    try {
      final credential = await AuthService.signInWithGoogle();
      if (credential == null || !mounted) {
        if (mounted) setState(() => _googleLoading = false);
        return;
      }
      Navigator.pop(context);
      await widget.onAuthenticated?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _googleLoading = false;
          _authError = _readableAuthError(error);
        });
      }
    }
  }

  Widget _notice({required bool error, required String message}) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: error ? Colors.red.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: error ? Colors.red.shade200 : Colors.green.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? Colors.red : Colors.green,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: error ? Colors.red.shade800 : Colors.green.shade800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isSignUp ? 'Create your account' : 'Welcome back',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_authError != null) ...[
              _notice(error: true, message: _authError!),
              const SizedBox(height: 10),
            ],
            if (_infoMessage != null) ...[
              _notice(error: false, message: _infoMessage!),
              const SizedBox(height: 10),
            ],
            if (_isSignUp) ...[
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passController,
              obscureText: true,
              onSubmitted: (_) => _handleEmailAuth(),
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (_isSignUp) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _confirmPassController,
                obscureText: true,
                onSubmitted: (_) => _handleEmailAuth(),
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _sendPasswordReset,
                  child: const Text('Forgot password?'),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: (_loading || _googleLoading) ? null : _handleEmailAuth,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isSignUp ? 'Sign Up' : 'Log In'),
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
              text: _isSignUp ? 'Sign up with Google' : 'Sign in with Google',
              isLoading: _googleLoading,
              onPressed:
                  (_loading || _googleLoading) ? null : _handleGoogleAuth,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _isSignUp = !_isSignUp;
                  _authError = null;
                  _infoMessage = null;
                });
              },
              child: Text(
                _isSignUp
                    ? 'Already have an account? Log In'
                    : "Don't have an account? Sign Up",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
