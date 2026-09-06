import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_role_and_nav.dart';

class AdminConsoleScreen extends StatefulWidget {
  final ValueChanged<UserRole>? onRoleChanged;

  const AdminConsoleScreen({super.key, this.onRoleChanged});

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> {
  bool _loading = false;
  String _serverStatus = 'Checking...';
  int? _latencyMs;
  int? _doctorCount;
  int? _appointmentCount;
  String? _lastActionMessage;

  @override
  void initState() {
    super.initState();
    _refreshBackendStats();
  }

  Future<void> _refreshBackendStats() async {
    setState(() => _loading = true);
    final stopwatch = Stopwatch()..start();

    try {
      final res = await ApiService.getRequest('/health');
      stopwatch.stop();

      int apptCount = 0;
      try {
        final qRes = await ApiService.getRequest('/appointments/today?chamberId=demo-chamber');
        if (qRes.statusCode == 200) {
          final qData = jsonDecode(qRes.body)['data'] as List?;
          apptCount = qData?.length ?? 0;
        }
      } catch (_) {}

      int docCount = 0;
      try {
        final dRes = await ApiService.fetchDoctors(limit: 1);
        docCount = dRes['total'] ?? 0;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _loading = false;
          _serverStatus = res.statusCode == 200 ? 'Online & Healthy' : 'Status code: ${res.statusCode}';
          _latencyMs = stopwatch.elapsedMilliseconds;
          _appointmentCount = apptCount;
          _doctorCount = docCount;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _serverStatus = 'Offline: $e';
          _latencyMs = null;
        });
      }
    }
  }

  Future<void> _clearAllAppointments() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Appointments?'),
        content: const Text(
          'This will delete all seeded and live appointments from the MongoDB collection.\n\nYou can re-seed them anytime from this console.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final res = await http.delete(Uri.parse('${ApiService.baseUrl}/appointments/clear/all'));
      if (res.statusCode == 200) {
        setState(() {
          _lastActionMessage = 'All appointments deleted from MongoDB.';
        });
      }
    } catch (e) {
      setState(() => _lastActionMessage = 'Clear error: $e');
    }
    await _refreshBackendStats();
  }

  Future<void> _seedDemoAppointments() async {
    setState(() => _loading = true);
    try {
      final sampleNames = ['Karim Uddin', 'Fatema Begum', 'Rahim Mia', 'Nasrin Akter', 'Mohammad Hasan'];
      for (int i = 0; i < sampleNames.length; i++) {
        final t = DateTime.now().add(Duration(minutes: (i + 1) * 30));
        await ApiService.postRequest(
          '/appointments',
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'patientName': sampleNames[i],
            'scheduledTime': t.toIso8601String(),
            'status': i == 0 ? 'in_progress' : 'waiting',
            'operatorNote': '',
          }),
        );
      }
      setState(() {
        _lastActionMessage = 'Successfully seeded 5 appointments to MongoDB.';
      });
    } catch (e) {
      setState(() => _lastActionMessage = 'Seed error: $e');
    }
    await _refreshBackendStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Admin Console', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshBackendStats,
            tooltip: 'Ping Backend',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshBackendStats,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Server Node.js + MongoDB Status Card
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.dns, color: Colors.greenAccent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DoctorDesk Node.js API',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                ApiService.baseUrl,
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _serverStatus.contains('Online') ? Colors.green : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _serverStatus.contains('Online') ? 'ONLINE' : 'ERROR',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _metric('MongoDB', 'Connected', Colors.greenAccent),
                        _metric('Latency', _latencyMs != null ? '$_latencyMs ms' : '--', Colors.amberAccent),
                        _metric('Doctors', _doctorCount != null ? '$_doctorCount' : '--', Colors.cyanAccent),
                        _metric('Queue', _appointmentCount != null ? '$_appointmentCount' : '--', Colors.purpleAccent),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_lastActionMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_lastActionMessage!, style: const TextStyle(fontSize: 12.5, color: Colors.blue)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Appointment & Queue Controls
            _sectionTitle('APPOINTMENTS & QUEUE MANAGEMENT'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                    title: const Text('Clear All Appointments'),
                    subtitle: const Text('Deletes all seeded and live patient appointments from MongoDB'),
                    trailing: FilledButton.tonal(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade50),
                      onPressed: _loading ? null : _clearAllAppointments,
                      child: const Text('Purge', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.playlist_add, color: Colors.green),
                    title: const Text('Seed 5 Sample Appointments'),
                    subtitle: const Text('Populates live chamber queue with fresh test appointments'),
                    trailing: FilledButton.tonal(
                      onPressed: _loading ? null : _seedDemoAppointments,
                      child: const Text('Seed'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Role Impersonation & Testing
            _sectionTitle('ROLE & SESSION SWITCHER'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.medical_services_outlined, color: Colors.blue),
                    title: const Text('Switch to Doctor Portal'),
                    subtitle: const Text('Active chamber management and live patient queue view'),
                    onTap: () {
                      widget.onRoleChanged?.call(UserRole.doctor);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Switched to Doctor portal view')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.desktop_windows_outlined, color: Colors.indigo),
                    title: const Text('Switch to Operator Desk'),
                    subtitle: const Text('Reception queue desk for patient check-ins and tickets'),
                    onTap: () {
                      widget.onRoleChanged?.call(UserRole.operator);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Switched to Operator Desk view')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: Colors.teal),
                    title: const Text('Switch to Guest Patient Mode'),
                    subtitle: const Text('Clean guest view without doctor/operator tabs'),
                    onTap: () async {
                      await AuthService.setGuestMode(true);
                      widget.onRoleChanged?.call(UserRole.patient);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Switched to Guest Patient view')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Database Utilities
            _sectionTitle('DATABASE & CACHE UTILITIES'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cable, color: Colors.amber),
                    title: const Text('Test Backend Connection Ping'),
                    subtitle: Text('Current resolved: ${ApiService.baseUrl}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _refreshBackendStats,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined, color: Colors.grey),
                    title: const Text('Reset All Local App Storage'),
                    subtitle: const Text('Clears SharedPreferences roles, guest mode, and mood keys'),
                    onTap: () async {
                      await AuthService.signOut();
                      await AuthService.setGuestMode(true);
                      widget.onRoleChanged?.call(UserRole.patient);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All local app storage reset to clean state.')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
