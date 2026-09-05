import 'package:flutter/material.dart';
import '../models/doctor.dart';
import '../services/api_service.dart';
import '../widgets/profile_avatar_button.dart';
import 'doctor_detail_screen.dart';
import 'doctors_screen.dart';
import 'nearby_doctors_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(int, {String? searchQuery})? onTabSwitch;

  const HomeScreen({super.key, this.onTabSwitch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _specialities = [];
  List<Doctor> _topDoctors = [];
  String? _todayFeeling;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final specialitiesData = await ApiService.fetchSpecialities();
      final doctorsData = await ApiService.fetchDoctors(limit: 5);
      final todayStatus = await ApiService.fetchTodayFeeling();

      setState(() {
        _specialities = specialitiesData;
        _topDoctors = List<Doctor>.from(doctorsData['doctors']);
        if (todayStatus != null) {
          _todayFeeling = todayStatus['feeling'];
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _submitSearch(String query) {
    if (query.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DoctorsScreen(initialQuery: query),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DoctorDesk', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
          const ProfileAvatarButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello,', style: Theme.of(context).textTheme.titleLarge),
              Text(
                'Find your specialist',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search doctors, specialties...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _submitSearch(_searchController.text),
                  ),
                ),
                onSubmitted: _submitSearch,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuickActionCard(
                    title: 'Find a Doctor',
                    icon: Icons.person_search_outlined,
                    color: colorScheme.primary,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DoctorsScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  _QuickActionCard(
                    title: 'Near Me',
                    icon: Icons.location_on_outlined,
                    color: const Color(0xFFE57373),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildFeelingSection(context, colorScheme),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Center(
                  child: Column(
                    children: [
                      Text('Error loading data', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      TextButton(onPressed: _loadData, child: const Text('Retry'))
                    ],
                  ),
                )
              else ...[
                Text(
                  'Specialities',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: _specialities.isEmpty
                      ? const Text('No specialities available')
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _specialities.length,
                          itemBuilder: (context, index) {
                            final spec = _specialities[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ActionChip(
                                label: Text(spec['speciality']),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DoctorsScreen(
                                        initialQuery: spec['speciality'],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Top Doctors',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DoctorsScreen(),
                          ),
                        );
                      },
                      child: const Text('See All'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_topDoctors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No doctors found.'),
                  )
                else
                  ..._topDoctors.map((doc) => _DoctorListCard(doctor: doc)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeelingSection(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0.8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'How are you feeling today?',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => widget.onTabSwitch?.call(2),
                  child: const Text('Calendar >', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.spa_outlined, color: Color(0xFF33691E), size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Be grateful for your health today • Keep your daily wellness streak',
                      style: TextStyle(fontSize: 11, color: Color(0xFF33691E), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _moodButton('great', '🌟', 'Great', colorScheme),
                _moodButton('good', '😊', 'Good', colorScheme),
                _moodButton('okay', '😐', 'Okay', colorScheme),
                _moodButton('low', '😔', 'Low', colorScheme),
                _moodButton('unwell', '🤒', 'Unwell', colorScheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodButton(String key, String emoji, String label, ColorScheme colorScheme) {
    final isSelected = _todayFeeling == key;
    Color? borderColor = Colors.transparent;
    Color? bgColor = Colors.transparent;
    Color? textColor = Colors.grey[700];

    if (isSelected) {
      if (key == 'good' || key == 'great') {
        borderColor = const Color(0xFF2E7D32);
        bgColor = const Color(0xFFE8F5E9);
        textColor = const Color(0xFF2E7D32);
      } else if (key == 'okay') {
        borderColor = const Color(0xFFF9A825);
        bgColor = const Color(0xFFFFFDE7);
        textColor = const Color(0xFFF57F17);
      } else if (key == 'low') {
        borderColor = const Color(0xFF7E57C2);
        bgColor = const Color(0xFFEDE7F6);
        textColor = const Color(0xFF5E35B1);
      } else if (key == 'unwell') {
        borderColor = const Color(0xFFC62828);
        bgColor = const Color(0xFFFFEBEE);
        textColor = const Color(0xFFC62828);
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onFeelingSelected(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onFeelingSelected(String key) {
    setState(() {
      _todayFeeling = key;
    });

    ApiService.logFeeling(feeling: key);

    if (key == 'good' || key == 'great') {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF81C784), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Today marked green on your Health Calendar! 🟢 Be grateful for your health!'),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Calendar',
            onPressed: () => widget.onTabSwitch?.call(2),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (key == 'okay') {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.circle, color: Color(0xFFFBC02D), size: 14),
              SizedBox(width: 8),
              Expanded(
                child: Text('Today marked yellow on your Health Calendar! 🟡 Steady and balanced.'),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Calendar',
            onPressed: () => widget.onTabSwitch?.call(2),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (key == 'low') {
      _showPsychiatristPrompt();
    } else if (key == 'unwell') {
      _showGeneralDoctorPrompt();
    }
  }

  void _showPsychiatristPrompt() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEDE7F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.psychology_outlined, color: Color(0xFF5E35B1), size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Feeling low or overwhelmed?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Mental health is just as important as physical health. Would you like to speak to a licensed Psychiatrist or specialist?',
                style: TextStyle(color: Colors.grey[700], fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Marked on your Health Calendar. Be kind to yourself today.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DoctorsScreen(initialQuery: 'Psychiatrist'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.psychology, size: 18),
                      label: const Text('See Psychiatrist'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5E35B1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showGeneralDoctorPrompt() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFEBEE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_hospital_outlined, color: Color(0xFFC62828), size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Feeling unwell today?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'We noticed you are feeling unwell. Would you like to consult a General Physician (GD) or Medicine doctor?',
                style: TextStyle(color: Colors.grey[700], fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Marked on your Health Calendar. Rest well and stay hydrated!'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DoctorsScreen(initialQuery: 'Medicine'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.medical_services_outlined, size: 18),
                      label: const Text('See General Doctor'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3B6FA0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.1),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoctorListCard extends StatelessWidget {
  final Doctor doctor;

  const _DoctorListCard({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DoctorDetailScreen(doctorId: doctor.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  doctor.name.isNotEmpty ? doctor.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 24,
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            doctor.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (doctor.isBmdcVerified)
                          const Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Icon(Icons.verified, color: Colors.blue, size: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      doctor.specialities.join(', '),
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${doctor.experienceYears.toStringAsFixed(0)} years experience',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    if (doctor.chamber?.hospitalName != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.local_hospital_outlined, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doctor.chamber!.hospitalName!,
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.star, size: 16, color: doctor.ratingCount > 0 ? Colors.amber : Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          doctor.ratingCount > 0
                              ? '${doctor.bayesianRating?.toStringAsFixed(1) ?? 'N/A'}'
                              : 'Not rated yet',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: doctor.ratingCount > 0 ? FontWeight.bold : FontWeight.normal,
                            color: doctor.ratingCount > 0 ? Colors.black87 : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
