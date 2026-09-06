import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/doctor.dart';
import '../services/api_service.dart';
import '../widgets/profile_avatar_button.dart';
import 'appointment_screen.dart';
import 'doctor_detail_screen.dart';
import 'doctors_screen.dart';
import 'nearby_doctors_screen.dart';
import '../services/specialty_matcher.dart';
import '../widgets/specialty_feedback_widget.dart';
import '../widgets/chamber_accessibility.dart';
import 'health_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(int, {String? searchQuery})? onTabSwitch;

  const HomeScreen({super.key, this.onTabSwitch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _specialities = [];
  List<Doctor> _topDoctors = [];
  int? _totalDoctorsCount;
  String? _todayFeeling;
  bool _isMoodExpanded = false;
  bool _isMoodSubmittedToday = false;
  bool _isLoading = true;
  bool _isOffline = false;
  String? _error;

  // Search suggestions
  bool _showSuggestions = false;
  bool _isSearchingSuggestions = false;
  List<Doctor> _doctorSuggestions = [];
  List<String> _specialitySuggestions = [];

  // Symptom checker
  final TextEditingController _symptomController = TextEditingController();
  Timer? _symptomDebounce;
  String? _matchedSpecialty;
  bool _hasSymptomQuery = false;

  String get _todayDateKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatCount(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        buffer.write(',');
      }
    }
    return buffer.toString().split('').reversed.join('');
  }

  String _moodEmoji(String? mood) {
    switch (mood) {
      case 'great':
        return '🌟';
      case 'good':
        return '😊';
      case 'okay':
        return '😐';
      case 'low':
        return '😔';
      case 'unwell':
        return '🤒';
      default:
        return '🙂';
    }
  }

  String _moodLabel(String? mood) {
    switch (mood) {
      case 'great':
        return 'Great';
      case 'good':
        return 'Good';
      case 'okay':
        return 'Okay';
      case 'low':
        return 'Low';
      case 'unwell':
        return 'Unwell';
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchInputChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchInputChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _symptomDebounce?.cancel();
    _symptomController.dispose();
    super.dispose();
  }

  void _onSymptomChanged(String value) {
    _symptomDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _hasSymptomQuery = false;
        _matchedSpecialty = null;
      });
      return;
    }
    _symptomDebounce = Timer(const Duration(milliseconds: 300), () {
      final match = SpecialtyMatcher.match(query);
      setState(() {
        _hasSymptomQuery = true;
        _matchedSpecialty = match?.topSpecialty;
      });
    });
  }

  void _onSearchInputChanged() {
    final query = _searchController.text.trim();
    _searchDebounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _showSuggestions = false;
        _isSearchingSuggestions = false;
        _doctorSuggestions = [];
        _specialitySuggestions = [];
      });
      return;
    }

    setState(() {
      _showSuggestions = true;
      _isSearchingSuggestions = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final specMatches = _specialities
            .map((s) => (s['speciality'] ?? '').toString())
            .where((name) => name.toLowerCase().contains(query.toLowerCase()))
            .take(3)
            .toList();

        final searchResult = await ApiService.fetchDoctors(
          search: query,
          limit: 5,
        );

        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _specialitySuggestions = specMatches;
            _doctorSuggestions = List<Doctor>.from(searchResult['doctors'] ?? []);
            _isSearchingSuggestions = false;
          });
        }
      } catch (_) {
        if (mounted) {
          final localDoctorMatches = _topDoctors
              .where((d) =>
                  d.name.toLowerCase().contains(query.toLowerCase()) ||
                  d.specialities.any((s) => s.toLowerCase().contains(query.toLowerCase())))
              .take(5)
              .toList();
          setState(() {
            _specialitySuggestions = _specialities
                .map((s) => (s['speciality'] ?? '').toString())
                .where((name) => name.toLowerCase().contains(query.toLowerCase()))
                .take(3)
                .toList();
            _doctorSuggestions = localDoctorMatches;
            _isSearchingSuggestions = false;
          });
        }
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final localTodayMood = prefs.getString('mood_$_todayDateKey');
      if (localTodayMood != null) {
        _isMoodSubmittedToday = true;
        _todayFeeling = localTodayMood;
      }

      final specialitiesData = await ApiService.fetchSpecialities();
      final doctorsData = await ApiService.fetchDoctors(limit: 5);
      final todayStatus = await ApiService.fetchTodayFeeling();

      final List<Doctor> doctors = List<Doctor>.from(doctorsData['doctors'] ?? []);
      final bool offlineFlag = doctorsData['isOffline'] == true;

      // Cache real data locally so cutting the backend keeps the app presentable
      if (doctors.isNotEmpty) {
        await prefs.setString(
            'cached_top_doctors', jsonEncode(doctors.map((d) => d.toJson()).toList()));
      }
      if (specialitiesData.isNotEmpty) {
        await prefs.setString('cached_specialities', jsonEncode(specialitiesData));
      }
      if (doctorsData['total'] != null) {
        await prefs.setInt('cached_total_doctors', doctorsData['total'] as int);
      }

      setState(() {
        _specialities = specialitiesData;
        _topDoctors = doctors;
        _totalDoctorsCount = doctorsData['total'] as int?;
        _isOffline = offlineFlag;
        if (todayStatus != null && todayStatus['feeling'] != null) {
          _todayFeeling = todayStatus['feeling'];
          _isMoodSubmittedToday = true;
          prefs.setString('mood_$_todayDateKey', _todayFeeling!);
        }
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      // Fallback: try loading cached doctor info so app is still presentable
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedDocsRaw = prefs.getString('cached_top_doctors');
        final cachedSpecsRaw = prefs.getString('cached_specialities');
        final cachedTotal = prefs.getInt('cached_total_doctors');

        if (cachedDocsRaw != null && cachedDocsRaw.isNotEmpty) {
          final List decoded = jsonDecode(cachedDocsRaw);
          final loadedDocs = decoded.map((j) => Doctor.fromJson(j)).toList();
          List<Map<String, dynamic>> loadedSpecs = [];
          if (cachedSpecsRaw != null) {
            final List decSpecs = jsonDecode(cachedSpecsRaw);
            loadedSpecs = decSpecs.cast<Map<String, dynamic>>();
          }

          setState(() {
            _topDoctors = loadedDocs;
            _specialities = loadedSpecs;
            _totalDoctorsCount = cachedTotal ?? loadedDocs.length;
            _isOffline = true;
            _isLoading = false;
            _error = null;
          });
          return;
        }
      } catch (_) {}

      setState(() {
        _error = 'No Internet Connection\nPlease check your network connection and try again.';
        _isLoading = false;
      });
    }
  }

  void _submitSearch(String query) {
    setState(() {
      _showSuggestions = false;
    });
    _searchFocusNode.unfocus();
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 30,
              width: 30,
            ),
            const SizedBox(width: 8),
            const Text('DoctorDesk', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
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
              Text('Hello there,', style: Theme.of(context).textTheme.titleLarge),
              Text(
                'Find your specialist',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 20),

              // Search field with live dropdown suggestions and rule-based assistant button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Search doctors, specialties...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchInputChanged();
                                },
                              )
                            : IconButton(
                                icon: const Icon(Icons.arrow_forward),
                                onPressed: () => _submitSearch(_searchController.text),
                              ),
                      ),
                      onSubmitted: _submitSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                    child: Tooltip(
                      message: 'Rule-based Health Assistant',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HealthChatScreen()),
                          ).then((_) => _loadData());
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          child: const Icon(
                            Icons.smart_toy_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Dropdown matching doctor names / specialties
              _buildSearchSuggestionsDropdown(colorScheme),

              // Multilingual Rule-based Symptom Checker
              _buildSymptomChecker(colorScheme),

              const SizedBox(height: 20),

              // Sole non-redundant Quick Action: Near Me (Full Width)
              Card(
                elevation: 0.8,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFE57373).withValues(alpha: 0.15),
                          child: const Icon(Icons.location_on_outlined, color: Color(0xFFE57373)),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Doctors Near Me',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Find chambers and verified specialists close to your location',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 40, color: Theme.of(context).colorScheme.error),
                            const SizedBox(height: 10),
                            Text(
                              'No Internet Connection',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Please check your network connection and try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                if (_isOffline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 20, color: Colors.amber.shade900),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Offline mode • Displaying saved doctor directory',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                const SizedBox(height: 28),

                // Top Doctors Heading with dynamic verified count stat from GET /doctors
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Top Doctors',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_totalDoctorsCount != null && _totalDoctorsCount! > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${_formatCount(_totalDoctorsCount!)}${_totalDoctorsCount! >= 100 ? '+' : ''} verified specialists',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
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

              const SizedBox(height: 24),

              // Daily feeling / mood widget (collapsed by default, expands on tap, saved to SharedPreferences)
              _buildFeelingSection(context, colorScheme),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSuggestionsDropdown(ColorScheme colorScheme) {
    if (!_showSuggestions || _searchController.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSearchingSuggestions)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_specialitySuggestions.isEmpty && _doctorSuggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.search_off, size: 18, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text(
                      'No matching doctors or specialties',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              )
            else ...[
              for (final spec in _specialitySuggestions)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.medical_services_outlined, color: colorScheme.primary, size: 20),
                  title: Text(
                    spec,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Specialty',
                      style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _showSuggestions = false;
                      _searchController.clear();
                    });
                    _searchFocusNode.unfocus();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DoctorsScreen(initialQuery: spec),
                      ),
                    );
                  },
                ),
              for (final doc in _doctorSuggestions)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      doc.name.isNotEmpty ? doc.name[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                    ),
                  ),
                  title: Text(
                    doc.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    doc.specialities.join(', '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  onTap: () {
                    setState(() {
                      _showSuggestions = false;
                      _searchController.clear();
                    });
                    _searchFocusNode.unfocus();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DoctorDetailScreen(doctorId: doc.id),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSymptomChecker(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _symptomController,
            onChanged: _onSymptomChanged,
            decoration: InputDecoration(
              hintText: "Describe your symptoms or health concern / আপনার সমস্যাগুলো লিখুন",
              hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.healing_outlined, size: 20),
              suffixIcon: _symptomController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _symptomController.clear();
                        _onSymptomChanged('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          if (_hasSymptomQuery) ...[
            const SizedBox(height: 8),
            if (_matchedSpecialty != null)
              Card(
                elevation: 0,
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DoctorsScreen(
                              initialQuery: _matchedSpecialty,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text: 'Sounds like you need a ',
                                  style: const TextStyle(fontSize: 13),
                                  children: [
                                    TextSpan(
                                      text: _matchedSpecialty,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const TextSpan(
                                      text: '. Show doctors →',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: colorScheme.primary, size: 18),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 10),
                      child: SpecialtyFeedbackRow(
                        inputText: _symptomController.text,
                        matchedSpecialty: _matchedSpecialty!,
                        source: 'rule_based',
                        onSubmitFeedback: ({
                          required String inputText,
                          required String matchedSpecialty,
                          required String source,
                          required bool liked,
                        }) => ApiService.submitSpecialtyFeedback(
                          inputText: inputText,
                          matchedSpecialty: matchedSpecialty,
                          source: source,
                          liked: liked,
                          language: SpecialtyMatcher.detectLanguage(inputText),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No specialist suggestion for that input — try a different description or search directly.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeelingSection(BuildContext context, ColorScheme colorScheme) {
    if (_isMoodSubmittedToday) {
      // Once a mood is submitted, keep widget collapsed/hidden for the rest of that calendar day
      return Card(
        elevation: 0.6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(_moodEmoji(_todayFeeling), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    "Today's mood logged: ${_moodLabel(_todayFeeling)}",
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HealthCalendarScreen()),
                  );
                },
                child: const Text('Calendar >', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isMoodExpanded) {
      // Single line by default
      return Card(
        elevation: 0.8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              _isMoodExpanded = true;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.sentiment_satisfied_alt_outlined, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'How are you feeling today? 🙂',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Icon(Icons.expand_more, color: Colors.grey[600], size: 20),
              ],
            ),
          ),
        ),
      );
    }

    // Expanded view with emoji picker
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
                Row(
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HealthCalendarScreen()),
                        );
                      },
                      child: const Text('Calendar >', style: TextStyle(fontSize: 12)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.expand_less, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          _isMoodExpanded = false;
                        });
                      },
                    ),
                  ],
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
      _isMoodSubmittedToday = true;
      _isMoodExpanded = false;
    });

    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('mood_$_todayDateKey', key);
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
                child: Text('Today marked green on your Health Calendar! 🟢'),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Calendar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthCalendarScreen()),
              );
            },
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthCalendarScreen()),
              );
            },
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
                          if (doctor.chamber?.accessibility != null) ...[
                            const SizedBox(width: 6),
                            AccessibilityIcon(accessibility: doctor.chamber!.accessibility!),
                          ],
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
                              ? (doctor.bayesianRating?.toStringAsFixed(1) ?? 'N/A')
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
