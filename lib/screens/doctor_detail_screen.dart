import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/doctor.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/chamber_accessibility.dart';
import '../widgets/trust_score.dart';
import 'package:flutter_tts/flutter_tts.dart';

class DoctorDetailScreen extends StatefulWidget {
  final String doctorId;

  const DoctorDetailScreen({super.key, required this.doctorId});

  @override
  State<DoctorDetailScreen> createState() => _DoctorDetailScreenState();
}

class _DoctorDetailScreenState extends State<DoctorDetailScreen> {
  Doctor? _doctor;
  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _reviews = [];
  bool _isReviewsLoading = true;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlayingTts = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadDoctor();
    _loadReviews();
  }

  void _initTts() {
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlayingTts = false);
    });
    _flutterTts.setErrorHandler((_) {
      if (mounted) setState(() => _isPlayingTts = false);
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _toggleTts(Doctor doctor) async {
    if (_isPlayingTts) {
      await _flutterTts.stop();
      if (mounted) setState(() => _isPlayingTts = false);
      return;
    }

    final speech = StringBuffer();
    speech.write('${doctor.name}. ');
    if (doctor.designation != null && doctor.designation!.isNotEmpty) {
      speech.write('${doctor.designation}. ');
    }
    if (doctor.isBmdcVerified) {
      speech.write('BMDC Verified Specialist. ');
    }
    if (doctor.specialities.isNotEmpty) {
      speech.write('Specialities: ${doctor.specialities.join(", ")}. ');
    }
    if (doctor.experienceYears > 0) {
      speech.write('${doctor.experienceYears.toInt()} years of experience. ');
    }
    if (doctor.ratingCount > 0) {
      speech.write('Rating: ${doctor.ratingAverage?.toStringAsFixed(1) ?? "-"} stars out of ${doctor.ratingCount} reviews. ');
    } else {
      speech.write('Not rated yet. ');
    }
    if (doctor.chambers.isNotEmpty) {
      speech.write('Chambers: ');
      for (final c in doctor.chambers) {
        if (c.hospitalName != null) speech.write('${c.hospitalName}. ');
        if (c.area != null) speech.write('${c.area}. ');
        if (c.accessibility != null && c.accessibility!.tier != AccessibilityTier.none) {
          speech.write('Wheelchair accessible chamber. ');
        }
      }
    }
    if (_reviews.isNotEmpty) {
      speech.write('Recent reviews: ');
      for (final r in _reviews.take(2)) {
        if (r['comment'] != null && (r['comment'] as String).isNotEmpty) {
          speech.write('${r["comment"]}. ');
        }
      }
    }

    setState(() => _isPlayingTts = true);
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.48);
    await _flutterTts.speak(speech.toString());
  }

  Future<void> _loadDoctor() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final doctor = await ApiService.fetchDoctorById(widget.doctorId);
      setState(() {
        _doctor = doctor;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadReviews() async {
    setState(() => _isReviewsLoading = true);
    try {
      final reviews = await ApiService.fetchReviews(widget.doctorId);
      setState(() {
        _reviews = reviews;
        _isReviewsLoading = false;
      });
    } catch (_) {
      setState(() => _isReviewsLoading = false);
    }
  }

  String _buildAboutText(Doctor doctor) {
    final buffer = StringBuffer();
    final primarySpec = doctor.specialities.isNotEmpty
        ? doctor.specialities.first
        : 'medical professional';
    buffer.write('${doctor.name} is a $primarySpec');
    if (doctor.experienceYears > 0) {
      buffer.write(' with ${doctor.experienceYears.toInt()} years of experience');
    }
    buffer.write('.');
    if (doctor.education.isNotEmpty) {
      buffer.write(' They hold qualifications in ${doctor.education.join(", ")}.');
    }
    if (doctor.concentrations.isNotEmpty) {
      buffer.write(
          ' Their areas of focus include ${doctor.concentrations.join(", ")}.');
    }
    return buffer.toString();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Claim bottom sheet
  // ──────────────────────────────────────────────────────────────────────────

  void _openClaimSheet(Doctor doctor) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ClaimSheet(
        doctorId: widget.doctorId,
        doctorName: doctor.name,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Claim submitted — BMDC verification will be reviewed manually within 2–3 business days.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
          _loadDoctor();
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Review bottom sheet
  // ──────────────────────────────────────────────────────────────────────────

  void _openReviewSheet() async {
    final patientUid = AuthService.currentUser?.uid;
    if (patientUid != null) {
      final canRev = await ApiService.checkCanReview(widget.doctorId, patientUid);
      if (!canRev && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are not eligible to review this profile (doctor self-review or staff conflict).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReviewSheet(
        doctorId: widget.doctorId,
        onSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review submitted — thank you!')),
          );
          _loadReviews();
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'No Internet Connection',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please check your network connection and try again.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _loadDoctor,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final doctor = _doctor!;
    final initials = doctor.name.isNotEmpty
        ? doctor.name
            .split(' ')
            .where((w) =>
                w.isNotEmpty &&
                !RegExp(r'^(Dr\.?|Prof\.?|Assoc\.?|Asst\.?)$',
                        caseSensitive: false)
                    .hasMatch(w))
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join()
        : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Profile'),
        actions: [
          IconButton(
            icon: Icon(_isPlayingTts ? Icons.stop_circle : Icons.volume_up),
            tooltip: _isPlayingTts ? 'Stop reading' : 'Read profile aloud (TTS)',
            color: _isPlayingTts ? colorScheme.error : null,
            onPressed: () => _toggleTts(doctor),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Colors.white,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          doctor.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // BMDC badge — ONLY shown when verified
                      if (doctor.isBmdcVerified) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'BMDC Verified',
                          child: Icon(Icons.verified,
                              color: colorScheme.primary, size: 22),
                        ),
                      ],
                    ],
                  ),
                  if (doctor.designation != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      doctor.designation!,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (doctor.specialities.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      doctor.specialities.join(', '),
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Semantics(
                    button: true,
                    label: _isPlayingTts
                        ? 'Stop reading doctor profile'
                        : 'Read doctor profile aloud with speech synthesizer',
                    child: FilledButton.tonalIcon(
                      icon: Icon(_isPlayingTts ? Icons.stop : Icons.volume_up, size: 18),
                      label: Text(_isPlayingTts ? 'Stop Voice' : 'Read Aloud (Voice)'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: _isPlayingTts ? colorScheme.error : colorScheme.primary,
                        backgroundColor: _isPlayingTts
                            ? colorScheme.errorContainer
                            : colorScheme.primaryContainer.withValues(alpha: 0.5),
                      ),
                      onPressed: () => _toggleTts(doctor),
                    ),
                  ),
                ],
              ),
            ),

            // ── Stats row & Trust Score ───────────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatItem(
                          icon: Icons.work_outline,
                          label: 'Experience',
                          value: doctor.experienceYears > 0
                              ? '${doctor.experienceYears.toInt()} years'
                              : 'Not specified',
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey[200],
                      ),
                      Expanded(
                        child: _StatItem(
                          icon: Icons.star_outline,
                          label: 'Rating',
                          // Honest rating state
                          value: doctor.ratingCount > 0
                              ? '★ ${doctor.ratingAverage?.toStringAsFixed(1) ?? "-"} (${doctor.ratingCount})'
                              : 'Not rated yet',
                          valueColor: doctor.ratingCount > 0
                              ? Colors.amber[700]
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  ScoreBadge(
                    score: TrustScore(
                      ratingAverage: doctor.ratingAverage,
                      ratingCount: doctor.ratingCount,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── About ─────────────────────────────────────────────────────
            _SectionCard(
              title: 'About',
              child: Text(
                _buildAboutText(doctor),
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: Colors.grey[700],
                ),
              ),
            ),

            // ── Education ─────────────────────────────────────────────────
            _SectionCard(
              title: 'Education',
              child: doctor.education.isNotEmpty
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: doctor.education
                          .map((deg) => Chip(
                                label: Text(deg,
                                    style: const TextStyle(fontSize: 13)),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    )
                  : Text('Not specified',
                      style: TextStyle(color: Colors.grey[500])),
            ),

            // ── Specialities ──────────────────────────────────────────────
            if (doctor.specialities.isNotEmpty)
              _SectionCard(
                title: 'Specialities',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: doctor.specialities
                      .map((s) => Chip(
                            label: Text(s,
                                style: const TextStyle(fontSize: 13)),
                            backgroundColor: colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),

            // ── Areas of Focus ────────────────────────────────────────────
            if (doctor.concentrations.isNotEmpty)
              _SectionCard(
                title: 'Areas of Focus',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: doctor.concentrations
                      .map((c) => Chip(
                            label: Text(c,
                                style: const TextStyle(fontSize: 13)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),

            // ── Chambers ──────────────────────────────────────────────────
            _SectionCard(
              title: 'Chambers',
              child: doctor.chambers.isNotEmpty
                  ? Column(
                      children: doctor.chambers.map((chamber) {
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on_outlined,
                                  color: colorScheme.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (chamber.hospitalName != null &&
                                        chamber.hospitalName!.isNotEmpty)
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              chamber.hospitalName!,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          if (chamber.accessibility != null) ...[
                                            const SizedBox(width: 8),
                                            AccessibilityIcon(
                                              accessibility: chamber.accessibility!,
                                            ),
                                          ],
                                        ],
                                      ),
                                    if (chamber.area != null &&
                                        chamber.area!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        chamber.area!,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    if (chamber.location != null &&
                                        chamber.location!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        chamber.location!,
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  : Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.grey[400]),
                        const SizedBox(width: 8),
                        Text('No chamber information available',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
            ),

            // ── Reviews ───────────────────────────────────────────────────
            _SectionCard(
              title: 'Reviews',
              child: _buildReviewsContent(),
            ),

            // ── Claim this profile ────────────────────────────────────────
            if (!doctor.isClaimed)
              _SectionCard(
                title: 'Claim this profile',
                child: _buildClaimContent(doctor),
              ),

            const SizedBox(height: 100), // Space for bottom button
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: null, // Disabled for Monday
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Book Appointment — Coming Soon'),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Reviews content widget
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildReviewsContent() {
    final isSignedIn = AuthService.isSignedIn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isReviewsLoading)
          const Center(child: CircularProgressIndicator())
        else if (_reviews.isEmpty)
          Column(
            children: [
              Icon(Icons.rate_review_outlined,
                  size: 40, color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text(
                'No reviews yet',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Be the first to share your experience',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          )
        else
          Column(
            children: _reviews
                .map((review) => _ReviewCard(review: review))
                .toList(),
          ),
        if (isSignedIn) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _openReviewSheet,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Write a review'),
          ),
        ],
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Claim content widget
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildClaimContent(Doctor doctor) {
    final isSignedIn = AuthService.isSignedIn;

    if (!isSignedIn) {
      return Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 8),
          Text('Sign in to claim this profile.',
              style: TextStyle(color: Colors.grey[600])),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Are you ${doctor.name}? Claim this profile to manage your information, '
          'respond to reviews, and display your BMDC verification badge.',
          style: TextStyle(color: Colors.grey[700], height: 1.5),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => _openClaimSheet(doctor),
          child: const Text('Claim this profile'),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Review card
// ════════════════════════════════════════════════════════════════════════════

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;

  const _ReviewCard({required this.review});

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final int rating = (review['rating'] as num?)?.toInt() ?? 0;
    final String comment = (review['comment'] as String?) ?? '';
    final bool isProofVerified = review['isProofVerified'] == true;
    final String dateStr = _formatDate(review['createdAt'] as String?);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Star row
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 18,
                    color: Colors.amber[700],
                  );
                }),
              ),
              const SizedBox(width: 8),
              // Verified chip
              if (isProofVerified)
                const Chip(
                  padding: EdgeInsets.zero,
                  labelPadding: EdgeInsets.symmetric(horizontal: 6),
                  avatar: Icon(Icons.check_circle,
                      size: 14, color: Color(0xFF2E7D32)),
                  label: Text(
                    'Verified visit',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  backgroundColor: Color(0xFFE8F5E9),
                  side: BorderSide(color: Color(0xFFA5D6A7)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              const Spacer(),
              if (dateStr.isNotEmpty)
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Claim bottom sheet (multi-step)
// ════════════════════════════════════════════════════════════════════════════

class _ClaimSheet extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  final VoidCallback onSuccess;

  const _ClaimSheet({
    required this.doctorId,
    required this.doctorName,
    required this.onSuccess,
  });

  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  final _bmdcController = TextEditingController();
  File? _certFile;
  double? _uploadProgress;
  String? _certDownloadUrl;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _bmdcController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadCert() async {
    final uid = AuthService.currentUser!.uid;
    final picker = ImagePicker();
    final XFile? picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() {
      _certFile = File(picked.path);
      _uploadProgress = 0;
      _certDownloadUrl = null;
    });

    final ref =
        FirebaseStorage.instance.ref('claims/$uid/certificate.jpg');
    final task = ref.putFile(_certFile!);

    task.snapshotEvents.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
      });
    });

    final snap = await task;
    final url = await snap.ref.getDownloadURL();
    if (!mounted) return;
    setState(() {
      _certDownloadUrl = url;
      _uploadProgress = null;
    });
  }

  Future<void> _submit() async {
    final bmdcNum = _bmdcController.text.trim();
    if (bmdcNum.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await ApiService.claimDoctor(
        widget.doctorId,
        bmdcRegNumber: bmdcNum,
        claimedByUid: AuthService.currentUser!.uid,
        certificateImageUrl: _certDownloadUrl,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit claim: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final bmdcFilled = _bmdcController.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Claim this profile',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Step 1: BMDC number
          Text('Step 1: BMDC Registration',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 8),
          TextField(
            controller: _bmdcController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'BMDC Registration Number',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const SizedBox(height: 20),

          // Step 2: Certificate upload
          Text('Step 2: Upload document (recommended)',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.outlined(
                icon: const Icon(Icons.upload_file),
                onPressed:
                    _uploadProgress != null ? null : _pickAndUploadCert,
                tooltip: 'Upload certificate or ID photo',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _uploadProgress != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: _uploadProgress),
                          const SizedBox(height: 4),
                          Text(
                            '${((_uploadProgress ?? 0) * 100).toStringAsFixed(0)}% uploaded',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      )
                    : _certDownloadUrl != null
                        ? Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(_certFile!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 20),
                              const SizedBox(width: 4),
                              Text('Uploaded',
                                  style: TextStyle(
                                      color: Colors.green[700],
                                      fontSize: 13)),
                            ],
                          )
                        : Text(
                            'Upload certificate or ID photo (recommended)',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13),
                          ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: _isSubmitting
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(
                    onPressed: bmdcFilled ? _submit : null,
                    child: const Text('Submit Claim'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Review bottom sheet
// ════════════════════════════════════════════════════════════════════════════

class _ReviewSheet extends StatefulWidget {
  final String doctorId;
  final VoidCallback onSuccess;

  const _ReviewSheet({required this.doctorId, required this.onSuccess});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _selectedRating = 0;
  final _commentController = TextEditingController();
  File? _proofFile;
  double? _uploadProgress;
  String? _proofDownloadUrl;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadProof() async {
    final uid = AuthService.currentUser!.uid;
    final picker = ImagePicker();
    final XFile? picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() {
      _proofFile = File(picked.path);
      _uploadProgress = 0;
      _proofDownloadUrl = null;
    });

    final ref = FirebaseStorage.instance
        .ref('reviews/$uid/${widget.doctorId}.jpg');
    final task = ref.putFile(_proofFile!);

    task.snapshotEvents.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
      });
    });

    final snap = await task;
    final url = await snap.ref.getDownloadURL();
    if (!mounted) return;
    setState(() {
      _proofDownloadUrl = url;
      _uploadProgress = null;
    });
  }

  Future<void> _submit() async {
    if (_selectedRating == 0) return;
    setState(() => _isSubmitting = true);
    try {
      await ApiService.submitReview(
        widget.doctorId,
        patientUid: AuthService.currentUser!.uid,
        rating: _selectedRating,
        comment: _commentController.text.trim(),
        proofImageUrl: _proofDownloadUrl,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit review: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Share your experience',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Star selector
            Text('Your rating',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                final starValue = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRating = starValue),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      starValue <= _selectedRating
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber[700],
                      size: 36,
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 16),

            // Comment
            Text('Comment (optional)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Describe your experience…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            const SizedBox(height: 16),

            // Proof upload
            Text('Proof of visit (optional)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              'Upload a prescription photo as proof of visit (optional). '
              'This photo is used only for verification — it will not be shown to other users.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  icon: const Icon(Icons.upload_file),
                  onPressed:
                      _uploadProgress != null ? null : _pickAndUploadProof,
                  tooltip: 'Upload prescription photo',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _uploadProgress != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(value: _uploadProgress),
                            const SizedBox(height: 4),
                            Text(
                              '${((_uploadProgress ?? 0) * 100).toStringAsFixed(0)}% uploaded',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        )
                      : _proofDownloadUrl != null
                          ? Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(_proofFile!,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.check_circle,
                                    color: Colors.green, size: 20),
                                const SizedBox(width: 4),
                                Text('Uploaded',
                                    style: TextStyle(
                                        color: Colors.green[700],
                                        fontSize: 13)),
                              ],
                            )
                          : Text(
                              'No photo selected',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13),
                            ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              child: _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton(
                      onPressed: _selectedRating > 0 ? _submit : null,
                      child: const Text('Submit Review'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Shared helper widgets
// ════════════════════════════════════════════════════════════════════════════

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[500]),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: valueColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
