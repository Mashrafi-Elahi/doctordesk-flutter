import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'google_sign_in_button.dart';

/// Shows the DoctorDesk authentication bottom sheet supporting:
/// 1. Patient vs Doctor role selection
/// 2. Email & Password mode
/// 3. Phone Number with SMS OTP verification
/// 4. Google Sign-in
void showDoctorDeskAuthModal(
  BuildContext context, {
  bool isSignUp = false,
  Future<void> Function()? onAuthenticated,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _AuthModalContent(
      initialIsSignUp: isSignUp,
      onAuthenticated: onAuthenticated,
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
  bool _isDoctorRole = false;
  int _authMethodIndex = 0; // 0 = Email, 1 = Phone Number

  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _otpSent = false;
  String? _verificationId;
  String? _authError;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _formatPhone(String raw) {
    String clean = raw.replaceAll(RegExp(r'[\s\-]'), '').trim();
    if (clean.startsWith('01')) {
      return '+88$clean';
    }
    if (!clean.startsWith('+') && clean.isNotEmpty) {
      return '+$clean';
    }
    return clean;
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final pass = _passController.text.trim();
    final phone = _formatPhone(_phoneController.text.trim());

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _authError = 'Please fill in both email and password.');
      return;
    }

    if (_isDoctorRole && phone.isEmpty) {
      setState(() => _authError = 'Doctor registration requires a valid phone number.');
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
          pass,
          name: _nameController.text.trim(),
          phone: phone,
          role: _isDoctorRole ? 'doctor' : 'patient',
          isDoctor: _isDoctorRole,
        );
      } else {
        await AuthService.signInWithEmailPassword(
          email,
          pass,
          isDoctor: _isDoctorRole,
        );
      }

      if (mounted) Navigator.pop(context);
      await widget.onAuthenticated?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _authError = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _formatPhone(_phoneController.text.trim());
    if (phone.length < 10) {
      setState(() => _authError = 'Please enter a valid phone number (e.g. 01712345678).');
      return;
    }

    setState(() {
      _loading = true;
      _authError = null;
      _infoMessage = null;
    });

    try {
      await AuthService.verifyPhoneNumber(
        phoneNumber: phone,
        onCodeSent: (verificationId) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _otpSent = true;
              _loading = false;
              _infoMessage = 'Verification code sent to $phone';
            });
          }
        },
        onVerificationCompleted: (credential) async {
          // Auto-resolution on Android if available
          if (credential.smsCode != null && _verificationId != null) {
            _otpController.text = credential.smsCode!;
            await _verifyPhoneOtp();
          }
        },
        onVerificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              _loading = false;
              _authError = e.message ?? 'Phone verification failed (${e.code}).';
            });
          }
        },
        onCodeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _authError = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final code = _otpController.text.trim();
    if (code.length < 6 || _verificationId == null) {
      setState(() => _authError = 'Please enter the 6-digit verification code.');
      return;
    }

    setState(() {
      _loading = true;
      _authError = null;
    });

    try {
      final phone = _formatPhone(_phoneController.text.trim());
      await AuthService.signInWithPhoneOtp(
        verificationId: _verificationId!,
        smsCode: code,
        name: _nameController.text.trim(),
        phone: phone,
        role: _isDoctorRole ? 'doctor' : 'patient',
        isDoctor: _isDoctorRole,
      );

      if (mounted) Navigator.pop(context);
      await widget.onAuthenticated?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _authError = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _handleGoogleAuth() async {
    setState(() {
      _googleLoading = true;
      _authError = null;
    });

    try {
      final cred = await AuthService.signInWithGoogle(isDoctor: _isDoctorRole);
      if (cred != null) {
        if (mounted) Navigator.pop(context);
        await widget.onAuthenticated?.call();
      } else {
        if (mounted) setState(() => _googleLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _googleLoading = false;
          _authError = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isSignUp
                      ? (_isDoctorRole ? 'Create Doctor Account' : 'Create Patient Account')
                      : (_isDoctorRole ? 'Doctor Log In' : 'Welcome Back'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Role Selector Chips (Patient vs Doctor)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _isDoctorRole = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_isDoctorRole ? colorScheme.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: !_isDoctorRole
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                              : null,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 16,
                                color: !_isDoctorRole ? colorScheme.primary : Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Patient Role',
                                style: TextStyle(
                                  fontWeight: !_isDoctorRole ? FontWeight.bold : FontWeight.normal,
                                  color: !_isDoctorRole ? colorScheme.primary : Colors.grey[700],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _isDoctorRole = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _isDoctorRole ? colorScheme.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _isDoctorRole
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                              : null,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.local_hospital_outlined,
                                size: 16,
                                color: _isDoctorRole ? colorScheme.primary : Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Doctor Role',
                                style: TextStyle(
                                  fontWeight: _isDoctorRole ? FontWeight.bold : FontWeight.normal,
                                  color: _isDoctorRole ? colorScheme.primary : Colors.grey[700],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Method Toggle: Email vs Phone Number
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.email_outlined, size: 16),
                  label: Text('Email'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.phone_android, size: 16),
                  label: Text('Phone OTP'),
                ),
              ],
              selected: {_authMethodIndex},
              onSelectionChanged: (val) {
                setState(() {
                  _authMethodIndex = val.first;
                  _authError = null;
                  _infoMessage = null;
                });
              },
            ),
            const SizedBox(height: 12),

            // Error display
            if (_authError != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _authError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Info display
            if (_infoMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _infoMessage!,
                        style: const TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Full Name (if sign up)
            if (_isSignUp) ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: _isDoctorRole ? 'Doctor Name (e.g. Dr. Jane Doe)' : 'Full Name',
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // MODE 0: EMAIL & PASSWORD
            if (_authMethodIndex == 0) ...[
              // Doctor phone number in email mode
              if (_isDoctorRole) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Doctor Phone Number (Required)',
                    hintText: '017XXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (_loading || _googleLoading) ? null : _handleEmailAuth,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isSignUp ? 'Sign Up' : 'Log In'),
              ),
            ],

            // MODE 1: PHONE NUMBER & OTP
            if (_authMethodIndex == 1) ...[
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                enabled: !_otpSent || !_loading,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '017XXXXXXXX or +88017...',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              if (_otpSent) ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '6-digit SMS OTP Code',
                    prefixIcon: Icon(Icons.password_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: (_loading || _googleLoading) ? null : _verifyPhoneOtp,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Verify OTP & Enter'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _sendPhoneOtp,
                  child: const Text('Resend SMS Code'),
                ),
              ] else ...[
                const SizedBox(height: 6),
                FilledButton.icon(
                  icon: const Icon(Icons.sms_outlined),
                  onPressed: (_loading || _googleLoading) ? null : _sendPhoneOtp,
                  label: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send SMS Verification Code'),
                ),
              ],
            ],

            // Divider: OR
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

            // Google Sign-In
            GoogleSignInButton(
              text: _isSignUp
                  ? (_isDoctorRole ? 'Sign up Doctor with Google' : 'Sign up with Google')
                  : (_isDoctorRole ? 'Sign in Doctor with Google' : 'Sign in with Google'),
              isLoading: _googleLoading,
              onPressed: (_loading || _googleLoading) ? null : _handleGoogleAuth,
            ),
            const SizedBox(height: 8),

            // Toggle between Sign Up and Log In
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
