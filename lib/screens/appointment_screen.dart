import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/profile_avatar_button.dart';
import 'doctors_screen.dart';

/// Appointments & Health Calendar Screen
class AppointmentScreen extends StatefulWidget {
  final int initialTabIndex;

  const AppointmentScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      initialIndex: widget.initialTabIndex,
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Appointments & Calendar'),
          actions: const [
            ProfileAvatarButton(),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past Visits'),
              Tab(text: 'Health Calendar'),
            ],
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: theme.colorScheme.primary,
          ),
        ),
        body: const TabBarView(
          children: [
            _EmptyState(
              icon: Icons.calendar_today_outlined,
              title: 'No upcoming appointments',
              subtitle:
                  'Book a doctor from the Home or Doctors directory to see it here.',
            ),
            _EmptyState(
              icon: Icons.history_outlined,
              title: 'No past appointments yet',
              subtitle: 'Your visit history will show up here after consultations.',
            ),
            _HealthCalendarTab(),
          ],
        ),
      ),
    );
  }
}

class _HealthCalendarTab extends StatefulWidget {
  const _HealthCalendarTab();

  @override
  State<_HealthCalendarTab> createState() => _HealthCalendarTabState();
}

class _HealthCalendarTabState extends State<_HealthCalendarTab> {
  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final Map<String, String> _dayToFeeling = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  String _dateKey(DateTime dt) =>
      "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    final entries = await ApiService.fetchJournalEntries();
    if (mounted) {
      final map = <String, String>{};
      for (final item in entries) {
        final raw = item['createdAt'] ?? item['date'];
        if (raw != null) {
          final dt = DateTime.tryParse(raw.toString());
          if (dt != null) {
            final key = _dateKey(dt.toLocal());
            if (!map.containsKey(key)) {
              map[key] = (item['feeling'] ?? '').toString().toLowerCase();
            }
          }
        }
      }
      setState(() {
        _dayToFeeling.clear();
        _dayToFeeling.addAll(map);
        _isLoading = false;
      });
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + offset, 1);
    });
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final leadingEmptyDays = (firstDayOfMonth.weekday - 1);
    final totalCells = leadingEmptyDays + daysInMonth;

    int goodDaysCount = 0;
    int okayDaysCount = 0;
    int lowDaysCount = 0;
    int unwellDaysCount = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final k = _dateKey(DateTime(_currentMonth.year, _currentMonth.month, d));
      final f = _dayToFeeling[k];
      if (f == 'good' || f == 'great') {
        goodDaysCount++;
      } else if (f == 'okay') {
        okayDaysCount++;
      } else if (f == 'low') {
        lowDaysCount++;
      } else if (f == 'unwell') {
        unwellDaysCount++;
      }
    }

    final selectedKey = _dateKey(_selectedDay);
    final selectedFeeling = _dayToFeeling[selectedKey];

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Daily Health Gratitude Reminder Banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFF16A34A),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Be Grateful for Your Health Today',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF166534),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Every healthy day is a blessing. Log your mood daily on Home to build your wellness streak and track your monthly health.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF15803D),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Month Header with Prev / Next controls
            Card(
              elevation: 0.8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => _changeMonth(-1),
                        ),
                        Text(
                          '${_getMonthName(_currentMonth.month)} ${_currentMonth.year}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => _changeMonth(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Weekday headers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        _WeekdayLabel('Mon'),
                        _WeekdayLabel('Tue'),
                        _WeekdayLabel('Wed'),
                        _WeekdayLabel('Thu'),
                        _WeekdayLabel('Fri'),
                        _WeekdayLabel('Sat'),
                        _WeekdayLabel('Sun'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Calendar grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: totalCells,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: 1.0,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemBuilder: (context, index) {
                        if (index < leadingEmptyDays) {
                          return const SizedBox.shrink();
                        }
                        final dayNumber = index - leadingEmptyDays + 1;
                        final cellDate = DateTime(_currentMonth.year, _currentMonth.month, dayNumber);
                        final key = _dateKey(cellDate);
                        final feeling = _dayToFeeling[key];

                        final isToday = cellDate.year == now.year &&
                            cellDate.month == now.month &&
                            cellDate.day == now.day;
                        final isSelected = cellDate.year == _selectedDay.year &&
                            cellDate.month == _selectedDay.month &&
                            cellDate.day == _selectedDay.day;

                        Color bgColor = Colors.transparent;
                        Color textColor = Colors.black87;
                        Color? borderColor;
                        Widget? marker;

                        if (feeling == 'good' || feeling == 'great') {
                          // GREEN MARK on good days
                          bgColor = const Color(0xFFE8F5E9);
                          textColor = const Color(0xFF2E7D32);
                          borderColor = const Color(0xFF4CAF50);
                          marker = Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                          );
                        } else if (feeling == 'okay') {
                          // YELLOW / OKAY MARK
                          bgColor = const Color(0xFFFFFDE7);
                          textColor = const Color(0xFFF57F17);
                          borderColor = const Color(0xFFFBC02D);
                          marker = Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF57F17),
                              shape: BoxShape.circle,
                            ),
                          );
                        } else if (feeling == 'low') {
                          // PURPLE / LOW MOOD MARK
                          bgColor = const Color(0xFFEDE7F6);
                          textColor = const Color(0xFF5E35B1);
                          borderColor = const Color(0xFF7E57C2);
                          marker = Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF5E35B1),
                              shape: BoxShape.circle,
                            ),
                          );
                        } else if (feeling == 'unwell') {
                          // RED / UNWELL MARK
                          bgColor = const Color(0xFFFFEBEE);
                          textColor = const Color(0xFFC62828);
                          borderColor = const Color(0xFFE53935);
                          marker = Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFFC62828),
                              shape: BoxShape.circle,
                            ),
                          );
                        }

                        if (isSelected) {
                          borderColor = colorScheme.primary;
                        } else if (isToday && borderColor == null) {
                          borderColor = colorScheme.primary.withValues(alpha: 0.6);
                        }

                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              _selectedDay = cellDate;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(10),
                              border: borderColor != null
                                  ? Border.all(
                                      color: borderColor,
                                      width: isSelected ? 2.0 : 1.2,
                                    )
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$dayNumber',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isToday || isSelected || feeling != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: textColor,
                                  ),
                                ),
                                if (marker != null) ...[
                                  const SizedBox(height: 2),
                                  marker,
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Legend
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _legendItem(const Color(0xFF4CAF50), 'Good'),
                        _legendItem(const Color(0xFFFBC02D), 'Okay'),
                        _legendItem(const Color(0xFF7E57C2), 'Low'),
                        _legendItem(const Color(0xFFE53935), 'Unwell'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Selected Day Card
            Card(
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
                        Text(
                          '${_getMonthName(_selectedDay.month)} ${_selectedDay.day}, ${_selectedDay.year}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (_selectedDay.year == now.year &&
                            _selectedDay.month == now.month &&
                            _selectedDay.day == now.day)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Today',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedFeeling == 'good' || selectedFeeling == 'great') ...[
                      Row(
                        children: const [
                          Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 28),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Good Health Day 🟢',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'You logged feeling healthy and great on this day. Take a moment to be grateful for your health!',
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else if (selectedFeeling == 'okay') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDE7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.sentiment_neutral, color: Color(0xFFF57F17), size: 26),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Okay / Balanced Day 🟡',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFFF57F17),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'You logged feeling steady and balanced today.',
                                    style: TextStyle(fontSize: 12, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (selectedFeeling == 'low') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE7F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.psychology_outlined, color: Color(0xFF5E35B1), size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'Low Mood / Overwhelmed 🟣',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF5E35B1),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Mental health matters just as much as physical health. Speaking with a psychiatrist or specialist can help.',
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
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
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (selectedFeeling == 'unwell') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.healing, color: Color(0xFFC62828), size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'Felt Unwell / Needed Care 🔴',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFFC62828),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'You recorded feeling unwell. Would you like to consult a General Physician (GD) or Medicine doctor?',
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const DoctorsScreen(initialQuery: 'Medicine'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.medical_services_outlined, size: 18),
                                label: const Text('See General Doctor (GD)'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFC62828),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'No health status recorded for this day.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Monthly Health Overview Card
            Card(
              elevation: 0.8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_getMonthName(_currentMonth.month)} Health Summary',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryStatCard(
                            count: goodDaysCount,
                            label: 'Good Days 🟢',
                            bgColor: const Color(0xFFE8F5E9),
                            textColor: const Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _summaryStatCard(
                            count: okayDaysCount,
                            label: 'Okay Days 🟡',
                            bgColor: const Color(0xFFFFFDE7),
                            textColor: const Color(0xFFF57F17),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryStatCard(
                            count: lowDaysCount,
                            label: 'Low Mood 🟣',
                            bgColor: const Color(0xFFEDE7F6),
                            textColor: const Color(0xFF5E35B1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _summaryStatCard(
                            count: unwellDaysCount,
                            label: 'Care Needed 🔴',
                            bgColor: const Color(0xFFFFEBEE),
                            textColor: const Color(0xFFC62828),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStatCard({
    required int count,
    required String label,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;
  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey[350]),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
