import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  final UserRole role;
  final String? initialSection;

  const SettingsScreen({
    super.key,
    this.role = UserRole.patient,
    this.initialSection,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _dailyMoodReminder = true;
  bool _queueSoundAlerts = true;
  bool _autoConfirmAppointments = false;
  String _language = 'English';
  String _consultationSlot = '20 mins';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('setting_notifications') ?? true;
        _dailyMoodReminder = prefs.getBool('setting_mood_reminder') ?? true;
        _queueSoundAlerts = prefs.getBool('setting_queue_sounds') ?? true;
        _autoConfirmAppointments = prefs.getBool('setting_auto_confirm') ?? false;
        _language = prefs.getString('setting_language') ?? 'English';
        _consultationSlot = prefs.getString('setting_slot') ?? '20 mins';
      });
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSignedIn = AuthService.isSignedIn;

    final title = switch (widget.role) {
      UserRole.doctor => 'Practice Settings',
      UserRole.operator => 'Chamber Desk Settings',
      UserRole.admin => 'Admin Settings',
      UserRole.patient => 'Settings',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Status Card
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(
                      isSignedIn ? Icons.person : Icons.person_outline,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSignedIn
                              ? (AuthService.currentUser?.displayName ?? 'Active Account')
                              : 'Guest Patient Mode',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSignedIn
                              ? (AuthService.currentUser?.email ?? 'Logged In')
                              : 'Limited offline session • Sign in to sync data',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (!isSignedIn)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text('Sign In'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Role-specific sections
          if (widget.role == UserRole.doctor) ...[
            _buildSectionHeader('DOCTOR & PRACTICE VERIFICATION'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified, color: Colors.blue),
                    title: const Text('BMDC Verification Status'),
                    subtitle: const Text('BMDC Reg: A-84920 • Verified Specialist'),
                    trailing: const Chip(
                      label: Text('ACTIVE', style: TextStyle(fontSize: 10, color: Colors.white)),
                      backgroundColor: Colors.green,
                      visualDensity: VisualDensity.compact,
                    ),
                    onTap: () {
                      _showBmdcDetailsDialog(context);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Default Consultation Slot'),
                    subtitle: Text(_consultationSlot),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickSlotDialog(context),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.rule_folder_outlined),
                    title: const Text('Auto-confirm Patient Bookings'),
                    subtitle: const Text('Accept bookings directly into schedule queue'),
                    value: _autoConfirmAppointments,
                    onChanged: (val) {
                      setState(() => _autoConfirmAppointments = val);
                      _saveBool('setting_auto_confirm', val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (widget.role == UserRole.operator) ...[
            _buildSectionHeader('OPERATOR DESK PREFERENCES'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.volume_up_outlined),
                    title: const Text('Queue Call & Bell Sound'),
                    subtitle: const Text('Audio chime when calling next patient token'),
                    value: _queueSoundAlerts,
                    onChanged: (val) {
                      setState(() => _queueSoundAlerts = val);
                      _saveBool('setting_queue_sounds', val);
                    },
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.meeting_room_outlined),
                    title: Text('Desk Station'),
                    subtitle: Text('Popular Diagnostic Desk 01 (Central)'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // General Notifications
          _buildSectionHeader('NOTIFICATIONS & ALERTS'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Receive appointment and serial queue updates'),
                  value: _notificationsEnabled,
                  onChanged: (val) {
                    setState(() => _notificationsEnabled = val);
                    _saveBool('setting_notifications', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.spa_outlined),
                  title: const Text('Daily Health & Mood Check-in'),
                  subtitle: const Text('Gentle daily reminder to record your wellness streak'),
                  value: _dailyMoodReminder,
                  onChanged: (val) {
                    setState(() => _dailyMoodReminder = val);
                    _saveBool('setting_mood_reminder', val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Preferences & Localization
          _buildSectionHeader('PREFERENCES'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_outlined),
                  title: const Text('Language'),
                  subtitle: Text(_language == 'English' ? 'English (US)' : 'বাংলা (Bengali)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickLanguageDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Clear Local Health Cache'),
                  subtitle: const Text('Reset offline search and mood cache'),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('hasSeenOnboarding');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Local cache cleared successfully.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // About & Legal
          _buildSectionHeader('ABOUT DOCTORDESK'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('App Version'),
                  subtitle: Text('DoctorDesk v1.0.4 • Bangladesh Healthcare Network'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Privacy & Medical Disclaimer'),
                  subtitle: const Text('Health recommendations are rule-assisted guides'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Medical Disclaimer'),
                        content: const Text(
                          'DoctorDesk provides verified doctor directory discovery, chamber queue management, and rule-based specialty recommendations.\n\nInformation provided in the app is not a substitute for formal clinical diagnosis. Always consult certified medical practitioners for emergencies.',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Understood'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  void _showBmdcDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified, color: Colors.blue),
            SizedBox(width: 8),
            Text('BMDC Verification'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Doctor Name: Dr. Rafiqul Islam', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('BMDC Registration: A-84920'),
            SizedBox(height: 4),
            Text('Qualification: MBBS, FCPS (Medicine)'),
            SizedBox(height: 4),
            Text('Verification Level: Level 3 Verified Specialist'),
            SizedBox(height: 8),
            Text(
              'Your profile displays the verified doctor badge on directory searches and appointment schedules.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _pickSlotDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Consultation Duration'),
        children: ['15 mins', '20 mins', '30 mins', '45 mins'].map((slot) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _consultationSlot = slot);
              _saveString('setting_slot', slot);
              Navigator.pop(ctx);
            },
            child: Text(slot),
          );
        }).toList(),
      ),
    );
  }

  void _pickLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Language'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _language = 'English');
              _saveString('setting_language', 'English');
              Navigator.pop(ctx);
            },
            child: const Text('English (US)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() => _language = 'Bengali');
              _saveString('setting_language', 'Bengali');
              Navigator.pop(ctx);
            },
            child: const Text('বাংলা (Bengali)'),
          ),
        ],
      ),
    );
  }
}
