import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/doctor.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/tts_service.dart';
import '../theme/app_constants.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_modal.dart';
import '../widgets/chamber_accessibility.dart';

String _reviewErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains('permission-denied')) {
    return 'Review was blocked by Firebase rules. Deploy the latest firestore.rules, then try again.';
  }
  if (raw.contains('network')) {
    return 'Network error while saving the review. Check your connection and try again.';
  }
  return 'Failed to save review. Please try again.';
}

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

  @override
  void initState() {
    super.initState();
    _loadDoctor();
    _loadReviews();
  }

  @override
  void dispose() {
    TtsService.instance.stop();
    super.dispose();
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
      buffer
          .write(' with ${doctor.experienceYears.toInt()} years of experience');
    }
    buffer.write('.');
    if (doctor.education.isNotEmpty) {
      buffer.write(
          ' They hold qualifications in ${doctor.education.join(", ")}.');
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
    final user = AuthService.currentUser;
    if (user == null || !AuthService.isSignedIn || AuthService.isGuest) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Guests can only check ratings. Please sign in as a Patient, Operator, or Doctor to rate.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        showDoctorDeskAuthModal(context, isSignUp: false);
      }
      return;
    }

    final doctorMap = _doctor != null
        ? {
            '_id': _doctor!.id,
            'id': _doctor!.id,
            'claimedByUid': _doctor!.claimedByUid,
          }
        : null;

    final canRate = await FirestoreService.checkCanReview(
      widget.doctorId,
      user.uid,
      doctorData: doctorMap,
    );

    if (!canRate && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot rate your own doctor profile.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
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
            const SnackBar(
                content: Text('Rating saved to reviews — thank you!')),
          );
          _loadReviews();
          _loadDoctor();
        },
      ),
    );
  }

  void _showBookingSheet(Doctor doctor) {
    if (!AuthService.isSignedIn || AuthService.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to book an appointment.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!doctor.isClaimed ||
        doctor.claimedByUid == null ||
        doctor.claimedByUid!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'This doctor profile is not claimed yet, so appointments are unavailable.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final chambers = doctor.chambers
        .map((c) => c.hospitalName ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    if (chambers.isEmpty) {
      chambers.add(doctor.chamber?.hospitalName ?? 'Main Consultation Chamber');
    }

    String selectedChamber = chambers.first;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);
    final patientNameCtrl = TextEditingController(
      text: AuthService.currentUser?.displayName?.isNotEmpty == true
          ? AuthService.currentUser!.displayName!
          : 'Patient',
    );
    bool isSubmitting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Book with ${doctor.name}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: patientNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Patient Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedChamber,
                      decoration: const InputDecoration(
                        labelText: 'Select Chamber',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: chambers
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedChamber = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                                '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 90)),
                              );
                              if (picked != null) {
                                setSheetState(() => selectedDate = picked);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(selectedTime.format(context)),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setSheetState(() => selectedTime = picked);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setSheetState(() => isSubmitting = true);
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final scheduled = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  selectedTime.hour,
                                  selectedTime.minute,
                                );
                                await FirestoreService.createAppointment(
                                  patientName:
                                      patientNameCtrl.text.trim().isNotEmpty
                                          ? patientNameCtrl.text.trim()
                                          : 'Patient',
                                  scheduledTime: scheduled,
                                  chamberId: selectedChamber,
                                  doctorId: doctor.id,
                                  status: 'waiting',
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Appointment booked! Check the Appointments tab.'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setSheetState(() => isSubmitting = false);
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                        content: Text('Booking error: $e')),
                                  );
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Confirm Appointment'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                Icon(Icons.wifi_off_rounded,
                    size: 48, color: theme.colorScheme.error),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Doctor Profile',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Hero Card (radius 24, gradient from primaryTint to primary) ────
            Container(
              margin: const EdgeInsets.all(AppConstants.screenPadding),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusHero),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppColors.primaryTint, AppColors.primaryLight],
                ),
                boxShadow: AppConstants.elevatedShadow,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doctor.name,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (doctor.specialities.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            doctor.specialities.join(', '),
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primaryDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 16, color: AppColors.star),
                            const SizedBox(width: 4),
                            Text(
                              doctor.ratingCount > 0
                                  ? '${doctor.ratingAverage?.toStringAsFixed(1) ?? "-"} (${doctor.ratingCount} Reviews)'
                                  : 'N/A',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Outlined "BOOK" button
                        OutlinedButton(
                          onPressed: () => _showBookingSheet(doctor),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary, width: 1.5),
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            'BOOK',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (doctor.chambers.isNotEmpty || doctor.chamber != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            doctor.chambers.isNotEmpty
                                ? doctor.chambers.map((c) => c.hospitalName).whereType<String>().join(', ')
                                : (doctor.chamber?.hospitalName ?? ''),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textPrimary.withValues(alpha: 0.8),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Right: circular/large avatar area
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.white,
                      backgroundImage: (doctor.certificateImageUrl != null &&
                              doctor.certificateImageUrl!.isNotEmpty)
                          ? NetworkImage(doctor.certificateImageUrl!)
                          : null,
                      child: (doctor.certificateImageUrl == null ||
                              doctor.certificateImageUrl!.isEmpty)
                          ? Text(
                              initials,
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // ── 2. Stat chips row (equal width, outlined, no invented numbers) ────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
              child: Row(
                children: [
                  if (doctor.experienceYears > 0)
                    _buildStatChip(
                      icon: Icons.work_outline,
                      value: '${doctor.experienceYears.toInt()} Years',
                      label: 'Experience',
                    ),
                  if (doctor.experienceYears > 0 && doctor.ratingCount > 0)
                    const SizedBox(width: 10),
                  if (doctor.ratingCount > 0)
                    _buildStatChip(
                      icon: Icons.rate_review_outlined,
                      value: '${doctor.ratingCount}',
                      label: 'Reviews',
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.sectionGap),

            // ── 3. About {name} ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
              child: _SectionCard(
                title: 'About ${doctor.name}',
                child: Text(
                  _buildAboutText(doctor),
                  style: AppTheme.body,
                ),
              ),
            ),

            // ── 4. Experience bullet list ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
              child: _SectionCard(
                title: 'Experience',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (doctor.experienceYears > 0)
                      _buildBulletItem('Over ${doctor.experienceYears.toInt()} years of professional clinical practice'),
                    if (doctor.education.isNotEmpty)
                      _buildBulletItem('Qualified: ${doctor.education.join(", ")}'),
                    if (doctor.concentrations.isNotEmpty)
                      _buildBulletItem('Clinical Focus: ${doctor.concentrations.join(", ")}'),
                    if (doctor.isBmdcVerified)
                      _buildBulletItem('BMDC & NID Verified Specialist'),
                    if (doctor.experienceYears <= 0 && doctor.education.isEmpty)
                      _buildBulletItem('Specialist medical practitioner with registered credentials'),
                  ],
                ),
              ),
            ),

            // ── 5. Specialities (filled primary chips, wrapping) ───────────
            if (doctor.specialities.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
                child: _SectionCard(
                  title: 'Specialities',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: doctor.specialities.map((s) {
                      return Chip(
                        label: Text(
                          s,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusChip),
                        ),
                        side: BorderSide.none,
                      );
                    }).toList(),
                  ),
                ),
              ),

            // ── 6. Chambers (with accessibility details) ───────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
              child: _SectionCard(
                title: 'Chambers',
                child: doctor.chambers.isNotEmpty
                    ? Column(
                        children: doctor.chambers.map((chamber) {
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on_outlined,
                                        color: AppColors.primary, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            chamber.hospitalName ?? 'Consultation Chamber',
                                            style: AppTheme.cardTitle,
                                          ),
                                          if (chamber.area != null && chamber.area!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              chamber.area!,
                                              style: AppTheme.body,
                                            ),
                                          ],
                                          if (chamber.location != null && chamber.location!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              chamber.location!,
                                              style: AppTheme.caption,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (chamber.isAccessible)
                                      const AccessibilityIcon(
                                        isAccessible: true,
                                        showLabel: true,
                                      ),
                                  ],
                                ),
                                // Accessibility detail features & disclaimer
                                if (chamber.isAccessible) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'This is declared by the doctor.',
                                        style: AppTheme.captionSmall,
                                      ),
                                    ],
                                  ),
                                  if (chamber.accessibilityFeatures.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: chamber.accessibilityFeatures.map((feat) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryTint,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            feat,
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      )
                    : Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.grey[400]),
                          const SizedBox(width: 8),
                          Text('No chamber information available', style: AppTheme.caption),
                        ],
                      ),
              ),
            ),

            // ── 7. Patient Reviews ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
              child: _SectionCard(
                title: 'Patient Reviews',
                child: _buildReviewsContent(),
              ),
            ),

            // ── 8. Claim this profile ──────────────────────────────────────
            if (!doctor.isClaimed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenPadding),
                child: _SectionCard(
                  title: 'Claim this profile',
                  child: _buildClaimContent(doctor),
                ),
              ),

            const SizedBox(height: 100), // Reserve bottom space for floating/fixed button
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.screenPadding),
          child: FilledButton(
            onPressed: () => _showBookingSheet(doctor),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusButton),
              ),
            ),
            child: Text(
              'Book Appointment',
              style: AppTheme.buttonText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip({required IconData icon, required String value, required String label}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          border: Border.all(color: AppColors.primary, width: 1.0),
          boxShadow: AppConstants.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
          Expanded(
            child: Text(text, style: AppTheme.body),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Reviews content widget
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildReviewsContent() {
    final isSignedIn = AuthService.isSignedIn && !AuthService.isGuest;
    final isDoctor = AuthService.userRoles.isDoctor;
    final isOperator = AuthService.userRoles.isOperator;

    String buttonLabel = 'Write a review';
    if (isDoctor) {
      buttonLabel = 'Rate as Doctor Specialist (Realtime Database)';
    } else if (isOperator) {
      buttonLabel = 'Rate as Chamber Operator (Realtime Database)';
    }

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
            children:
                _reviews.map((review) => _ReviewCard(review: review)).toList(),
          ),
        const SizedBox(height: 12),
        if (!isSignedIn) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined,
                    size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guest Mode: Viewing ratings only. Sign in to rate this doctor.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      showDoctorDeskAuthModal(context, isSignUp: false),
                  child: const Text('Sign In',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ] else ...[
          TextButton.icon(
            onPressed: _openReviewSheet,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(buttonLabel),
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
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
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
    final String raterName = (review['raterName'] as String?)?.isNotEmpty == true
        ? (review['raterName'] as String)
        : 'Patient';
    final String? raterRole = review['raterRole'] as String?;

    final initials = raterName.isNotEmpty ? raterName[0].toUpperCase() : 'P';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppConstants.cardGap),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  initials,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            raterName,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (raterRole == 'doctor') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Specialist',
                              style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (dateStr.isNotEmpty)
                      Text(
                        dateStr,
                        style: AppTheme.captionSmall,
                      ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: AppColors.star,
                  );
                }),
              ),
            ],
          ),
          if (isProofVerified) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 13, color: AppColors.success),
                const SizedBox(width: 4),
                Text('Verified visit', style: AppTheme.captionSmall.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: AppTheme.body,
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

    final ref = FirebaseStorage.instance.ref('claims/$uid/certificate.jpg');
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
                onPressed: _uploadProgress != null ? null : _pickAndUploadCert,
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
                                    width: 48, height: 48, fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 20),
                              const SizedBox(width: 4),
                              Text('Uploaded',
                                  style: TextStyle(
                                      color: Colors.green[700], fontSize: 13)),
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

    final ref =
        FirebaseStorage.instance.ref('reviews/$uid/${widget.doctorId}.jpg');
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
        SnackBar(content: Text(_reviewErrorMessage(e))),
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AuthService.userRoles.isDoctor
                          ? 'Rating as Doctor Specialist (Peer review)'
                          : (AuthService.userRoles.isOperator
                              ? 'Rating as Chamber Operator'
                              : 'Rating as Verified Patient'),
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
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
                                      width: 48, height: 48, fit: BoxFit.cover),
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
                      child: const Text('Submit Rating'),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppConstants.sectionGap),
      padding: const EdgeInsets.all(AppConstants.screenPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        boxShadow: AppConstants.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.sectionTitle,
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
