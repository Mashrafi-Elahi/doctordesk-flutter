import 'package:flutter/material.dart';
import '../models/doctor.dart';
import '../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDoctor();
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
                Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Unable to load doctor details',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center),
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
            .where((w) => w.isNotEmpty && !RegExp(r'^(Dr\.?|Prof\.?|Assoc\.?|Asst\.?)$', caseSensitive: false).hasMatch(w))
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join()
        : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Profile'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
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
                ],
              ),
            ),

            // Stats row
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
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
            ),

            const SizedBox(height: 8),

            // About
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

            // Education
            _SectionCard(
              title: 'Education',
              child: doctor.education.isNotEmpty
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: doctor.education
                          .map((deg) => Chip(
                                label: Text(deg, style: const TextStyle(fontSize: 13)),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    )
                  : Text('Not specified',
                      style: TextStyle(color: Colors.grey[500])),
            ),

            // Specialities
            if (doctor.specialities.isNotEmpty)
              _SectionCard(
                title: 'Specialities',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: doctor.specialities
                      .map((s) => Chip(
                            label: Text(s, style: const TextStyle(fontSize: 13)),
                            backgroundColor: colorScheme.primaryContainer
                                .withOpacity(0.5),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),

            // Concentrations
            if (doctor.concentrations.isNotEmpty)
              _SectionCard(
                title: 'Areas of Focus',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: doctor.concentrations
                      .map((c) => Chip(
                            label: Text(c, style: const TextStyle(fontSize: 13)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),

            // Chambers
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (chamber.hospitalName != null &&
                                        chamber.hospitalName!.isNotEmpty)
                                      Text(
                                        chamber.hospitalName!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
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
                        Icon(Icons.info_outline, size: 18, color: Colors.grey[400]),
                        const SizedBox(width: 8),
                        Text('No chamber information available',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
            ),

            // Reviews
            _SectionCard(
              title: 'Reviews',
              child: doctor.ratingCount > 0
                  ? const Text('Reviews will appear here.')
                  : Column(
                      children: [
                        Icon(Icons.rate_review_outlined,
                            size: 40, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text(
                          'No reviews yet',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Be the first to share your experience',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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
}

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
