import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/firestore_config.dart';
import '../services/firestore_service.dart';
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
  List<Map<String, dynamic>> _doctorApplications = [];
  List<Map<String, dynamic>> _moderators = [];
  final TextEditingController _manualUidController = TextEditingController();
  final TextEditingController _moderatorUidController = TextEditingController();
  bool _manualGrantVerified = false;

  @override
  void initState() {
    super.initState();
    _refreshBackendStats();
    _loadDoctorApplications();
    _loadModerators();
  }

  @override
  void dispose() {
    _manualUidController.dispose();
    _moderatorUidController.dispose();
    super.dispose();
  }

  Future<void> _loadDoctorApplications() async {
    try {
      final apps = await DataService.fetchDoctorApplications();
      if (mounted) {
        setState(() {
          _doctorApplications = apps;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadModerators() async {
    try {
      final mods = await DataService.fetchModerators();
      if (mounted) {
        setState(() {
          _moderators = mods;
        });
      }
    } catch (_) {}
  }

  Future<void> _approveDoctorApplication(String uid) async {
    setState(() => _loading = true);
    try {
      final doctorProfileId =
          await DataService.approveDoctorApplication(uid: uid);
      setState(() {
        _lastActionMessage =
            'Approved doctor application and linked directory profile $doctorProfileId.';
      });
      await _loadDoctorApplications();
      await _refreshBackendStats();
    } catch (e) {
      setState(() => _lastActionMessage = 'Error allocating doctor role: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rejectDoctorApplication(String uid) async {
    setState(() => _loading = true);
    try {
      await DataService.setDoctorRole(uid: uid, isDoctor: false);
      setState(() {
        _lastActionMessage =
            'Doctor application rejected/revoked for user $uid in database.';
      });
      await _loadDoctorApplications();
      await _refreshBackendStats();
    } catch (e) {
      setState(
          () => _lastActionMessage = 'Error rejecting doctor application: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reopenDoctorApplication(String uid) async {
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'doctorApplication': {
          'status': 'under_appeal',
          'appealedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
      setState(() {
        _lastActionMessage =
            'Application for $uid reopened under appeal for review.';
      });
      await _loadDoctorApplications();
      await _refreshBackendStats();
    } catch (e) {
      setState(() => _lastActionMessage = 'Error reopening application: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddDoctorDialog({Map<String, dynamic>? applicant}) async {
    final applicantDoc = applicant?['doctorApplication'] as Map? ?? {};
    final initialName = (applicantDoc['name'] ?? applicant?['name'] ?? '').toString();
    final initialSpec = (applicantDoc['speciality'] ?? '').toString();
    final initialPhone = (applicantDoc['phone'] ?? applicant?['phone'] ?? '').toString();
    final initialBmdc = (applicantDoc['bmdcNumber'] ?? applicant?['bmdcRegNumber'] ?? '').toString();

    String? selectedApplicantUid = applicant?['uid']?.toString();

    final nameCtrl = TextEditingController(
      text: initialName.isNotEmpty ? (initialName.startsWith('Dr.') ? initialName : 'Dr. $initialName') : '',
    );
    final specCtrl = TextEditingController(
      text: initialSpec.isNotEmpty ? initialSpec : 'General Medicine',
    );
    final chamberCtrl = TextEditingController(text: 'Bup Medical');
    final degreeCtrl = TextEditingController(text: 'MBBS');
    final phoneCtrl = TextEditingController(text: initialPhone);
    final bmdcCtrl = TextEditingController(text: initialBmdc);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            selectedApplicantUid != null
                ? 'Review & Create Doctor Profile'
                : 'Add Doctor to Directory',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (applicant == null && _doctorApplications.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: selectedApplicantUid,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Link to Pending Applicant',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (Unclaimed Directory Profile)'),
                      ),
                      ..._doctorApplications.map((app) {
                        final docApp = app['doctorApplication'] as Map? ?? {};
                        final aName = (docApp['name'] ?? app['name'] ?? 'Applicant').toString();
                        final aPhone = (docApp['phone'] ?? app['phone'] ?? '').toString();
                        final aEmail = (app['email'] ?? '').toString();
                        final sub = aPhone.isNotEmpty ? aPhone : aEmail;
                        return DropdownMenuItem<String?>(
                          value: app['uid']?.toString(),
                          child: Text('$aName ($sub)', overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedApplicantUid = val;
                        if (val != null) {
                          final match = _doctorApplications.firstWhere(
                            (a) => a['uid']?.toString() == val,
                            orElse: () => {},
                          );
                          if (match.isNotEmpty) {
                            final mApp = match['doctorApplication'] as Map? ?? {};
                            final mName = (mApp['name'] ?? match['name'] ?? '').toString();
                            final mPhone = (mApp['phone'] ?? match['phone'] ?? '').toString();
                            final mBmdc = (mApp['bmdcNumber'] ?? match['bmdcRegNumber'] ?? '').toString();
                            final mSpec = (mApp['speciality'] ?? '').toString();
                            if (mName.isNotEmpty) {
                              nameCtrl.text = mName.startsWith('Dr.') ? mName : 'Dr. $mName';
                            }
                            if (mPhone.isNotEmpty) phoneCtrl.text = mPhone;
                            if (mBmdc.isNotEmpty) bmdcCtrl.text = mBmdc;
                            if (mSpec.isNotEmpty) specCtrl.text = mSpec;
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (selectedApplicantUid != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 16, color: Colors.green.shade800),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Will link directory profile to UID: $selectedApplicantUid',
                            style: TextStyle(fontSize: 11.5, color: Colors.green.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Doctor Name (e.g. Dr. Jane Doe)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: specCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Speciality (e.g. General Medicine)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: chamberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Chamber / Hospital (e.g. Bup Medical)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: degreeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Degree (e.g. MBBS)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (e.g. +880 1...)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bmdcCtrl,
                  decoration: const InputDecoration(
                    labelText: 'BMDC Reg Number (e.g. A-98765)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: Text(selectedApplicantUid != null ? 'Add & Link Doctor' : 'Add Doctor'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _loading = true);
      try {
        final newId = await FirestoreService.addDoctor(
          name: nameCtrl.text.trim(),
          specialities: [
            specCtrl.text.trim().isNotEmpty
                ? specCtrl.text.trim()
                : 'General Medicine'
          ],
          designation: 'Specialist Consultant',
          education: [
            degreeCtrl.text.trim().isNotEmpty ? degreeCtrl.text.trim() : 'MBBS'
          ],
          bmdcRegNumber: bmdcCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          applicantUid: selectedApplicantUid,
          chambers: [
            {
              'hospitalName': chamberCtrl.text.trim().isNotEmpty
                  ? chamberCtrl.text.trim()
                  : 'Bup Medical',
              'area': 'Mirpur',
              'location': 'Dhaka',
            }
          ],
        );
        setState(() {
          _lastActionMessage = selectedApplicantUid != null
              ? 'Added doctor "${nameCtrl.text.trim()}" (ID: $newId) and linked to applicant $selectedApplicantUid.'
              : 'Added doctor "${nameCtrl.text.trim()}" successfully (ID: $newId).';
        });
        await _loadDoctorApplications();
        await _refreshBackendStats();
      } catch (e) {
        setState(() => _lastActionMessage = 'Error adding doctor: $e');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggleModeratorRole(String uid, bool grant) async {
    final isAdmin = AuthService.userRoles.isAdmin;
    if (!isAdmin) {
      setState(() {
        _lastActionMessage =
            'Permission Denied: Only System Administrators can add or remove moderators. Moderators cannot remove other moderators.';
      });
      return;
    }

    setState(() => _loading = true);
    try {
      await DataService.setModeratorRole(uid: uid, isModerator: grant);
      setState(() {
        _lastActionMessage = grant
            ? 'Granted Moderator role to $uid in database.'
            : 'Revoked Moderator role from $uid in database.';
        _moderatorUidController.clear();
      });
      await _loadModerators();
      await _refreshBackendStats();
    } catch (e) {
      setState(() => _lastActionMessage = 'Error updating moderator role: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manualToggleDoctorRole(bool grant) async {
    final uid = _manualUidController.text.trim();
    if (uid.isEmpty) {
      setState(() => _lastActionMessage = 'Please enter a valid user UID.');
      return;
    }
    setState(() => _loading = true);
    try {
      await DataService.setDoctorRole(
        uid: uid,
        isDoctor: grant,
        isBmdcVerified: grant && _manualGrantVerified,
      );
      setState(() {
        _lastActionMessage = grant
            ? 'Granted Doctor role${_manualGrantVerified ? ' (Verified)' : ''} to $uid via database.'
            : 'Revoked Doctor role from $uid via database.';
        _manualUidController.clear();
      });
      await _loadDoctorApplications();
      await _refreshBackendStats();
    } catch (e) {
      setState(() => _lastActionMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshBackendStats() async {
    setState(() => _loading = true);
    final stopwatch = Stopwatch()..start();

    try {
      if (FirestoreConfig.useFirestore) {
        await ApiService.fetchSpecialities();
        stopwatch.stop();

        final qData = await ApiService.fetchTodayQueue('demo-chamber');
        final dRes = await ApiService.fetchDoctors(limit: 1);

        if (mounted) {
          setState(() {
            _loading = false;
            _serverStatus = 'Online (Cloud Firestore)';
            _latencyMs = stopwatch.elapsedMilliseconds;
            _appointmentCount = qData.length;
            _doctorCount = dRes['total'] ?? 0;
          });
        }
        return;
      }

      final res = await ApiService.getRequest('/health');
      stopwatch.stop();

      int apptCount = 0;
      try {
        final qRes = await ApiService.getRequest(
            '/appointments/today?chamberId=demo-chamber');
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
          _serverStatus = res.statusCode == 200
              ? 'Online & Healthy'
              : 'Status code: ${res.statusCode}';
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
          'This will delete all seeded and live appointments from the database.\n\nYou can re-seed them anytime from this console.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
      await ApiService.clearAllAppointments();
      setState(() {
        _lastActionMessage = 'All appointments deleted successfully.';
      });
    } catch (e) {
      setState(() => _lastActionMessage = 'Clear error: $e');
    }
    await _refreshBackendStats();
  }

  Future<void> _seedDemoAppointments() async {
    setState(() => _loading = true);
    try {
      final sampleNames = [
        'Karim Uddin',
        'Fatema Begum',
        'Rahim Mia',
        'Nasrin Akter',
        'Mohammad Hasan'
      ];
      for (int i = 0; i < sampleNames.length; i++) {
        final t = DateTime.now().add(Duration(minutes: (i + 1) * 30));
        await ApiService.createAppointment(
          patientName: sampleNames[i],
          scheduledTime: t,
          status: i == 0 ? 'in_progress' : 'waiting',
          operatorNote: '',
          chamberId: 'demo-chamber',
        );
      }
      setState(() {
        _lastActionMessage = 'Successfully seeded 5 appointments.';
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
            Text('Admin Console',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
            // Active Firebase backend status card.
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
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
                          child: const Icon(Icons.dns,
                              color: Colors.greenAccent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DoctorDesk Firebase',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16),
                              ),
                              Text(
                                'Cloud Firestore shared backend',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _serverStatus.contains('Online')
                                ? Colors.green
                                : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _serverStatus.contains('Online')
                                ? 'ONLINE'
                                : 'ERROR',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
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
                        _metric('Firestore', 'Connected', Colors.greenAccent),
                        _metric(
                            'Latency',
                            _latencyMs != null ? '$_latencyMs ms' : '--',
                            Colors.amberAccent),
                        _metric(
                            'Doctors',
                            _doctorCount != null ? '$_doctorCount' : '--',
                            Colors.cyanAccent),
                        _metric(
                            'Queue',
                            _appointmentCount != null
                                ? '$_appointmentCount'
                                : '--',
                            Colors.purpleAccent),
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
                    const Icon(Icons.info_outline,
                        color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_lastActionMessage!,
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.blue)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Doctor Role Allocation Section (Role allocation via database only)
            _sectionTitle('DOCTOR ROLE ALLOCATION & DATABASE APPROVALS'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Doctor roles are allocated strictly via the database. Users who apply for a doctor account remain pending until approved here.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pending Applications (${_doctorApplications.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Refresh applications',
                          onPressed: _loading ? null : _loadDoctorApplications,
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    if (_doctorApplications.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'No pending doctor applications.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ..._doctorApplications.map((app) {
                        final uid = app['uid'] ?? '';
                        final docApp =
                            app['doctorApplication'] as Map<String, dynamic>? ??
                                {};
                        final name = app['name']?.toString().isNotEmpty == true
                            ? app['name']
                            : (docApp['name'] ?? 'Doctor Applicant');
                        final email = app['email'] ?? docApp['email'] ?? '';
                        final phone = app['phone'] ?? docApp['phone'] ?? '';
                        final nid = docApp['nid'] ?? app['nid'] ?? '';
                        final bmdcNumber =
                            docApp['bmdcNumber'] ?? app['bmdcRegNumber'] ?? '';
                        final hasDocs =
                            docApp['hasProvidedVerificationDocs'] == true ||
                                (nid.toString().isNotEmpty ||
                                    bmdcNumber.toString().isNotEmpty);

                        return Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('$name',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                  ),
                                  if (hasDocs)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified,
                                              size: 12,
                                              color: Colors.green.shade800),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Docs Provided',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade800),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('UID: $uid',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black54)),
                              if (phone.isNotEmpty)
                                Text(
                                    'Doctor Phone (Required for Login): $phone',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87)),
                              if (email.isNotEmpty)
                                Text('Email: $email',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.black54)),
                              if (nid.isNotEmpty)
                                Text('NID: $nid',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Colors.indigo)),
                              if (bmdcNumber.isNotEmpty)
                                Text('BMDC Reg No: $bmdcNumber',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Colors.teal)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: Colors.green),
                                    onPressed: _loading
                                        ? null
                                        : () => _approveDoctorApplication(uid),
                                    child: const Text('Approve Application'),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: _loading
                                        ? null
                                        : () => _showAddDoctorDialog(applicant: app),
                                    child: const Text('Review & Create Profile'),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: _loading
                                        ? null
                                        : () => _reopenDoctorApplication(uid),
                                    child: const Text('Appeal / Reopen'),
                                  ),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red),
                                    onPressed: _loading
                                        ? null
                                        : () => _rejectDoctorApplication(uid),
                                    child: const Text('Reject'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Manual Doctor Role Assignment (by UID):',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: _manualGrantVerified,
                          onChanged: (val) {
                            setState(() => _manualGrantVerified = val ?? false);
                          },
                        ),
                        const Text('Include BMDC & NID Verified Status',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualUidController,
                            decoration: const InputDecoration(
                              hintText: 'Enter user UID',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _loading
                              ? null
                              : () => _manualToggleDoctorRole(true),
                          child: const Text('Grant'),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red),
                          onPressed: _loading
                              ? null
                              : () => _manualToggleDoctorRole(false),
                          child: const Text('Revoke'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Doctor Directory Management Section
            _sectionTitle('DOCTOR DIRECTORY (ADD & DELETE DOCTOR)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Doctor Profiles Directory',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.person_add, size: 16),
                          label: const Text('Add Doctor'),
                          onPressed: _showAddDoctorDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Admins can add verified doctors directly or manage profiles in the directory.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Moderator Management Section
            _sectionTitle('MODERATOR APPOINTMENTS & PERMISSIONS'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Administrators can appoint and remove moderators. Moderators can post YouTube videos, publish clinical tips, and answer community Q&A. Moderators cannot remove other moderators.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    if (!AuthService.userRoles.isAdmin)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 18, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Restricted: You are viewing as a Moderator. Moderators cannot add or remove other moderators.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.amber.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Active Moderators (${_moderators.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Refresh moderators',
                          onPressed: _loading ? null : _loadModerators,
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    if (_moderators.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'No moderators appointed yet.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ..._moderators.map((mod) {
                        final uid = mod['uid'] ?? '';
                        final name = mod['name'] ?? 'Moderator User';
                        final email = mod['email'] ?? '';
                        final isAdmin = AuthService.userRoles.isAdmin;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Colors.deepOrange,
                            child: Icon(Icons.security,
                                color: Colors.white, size: 18),
                          ),
                          title: Text('$name',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13.5)),
                          subtitle: Text(
                              'UID: $uid${email.isNotEmpty ? ' • $email' : ''}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: isAdmin
                              ? OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  onPressed: _loading
                                      ? null
                                      : () => _toggleModeratorRole(uid, false),
                                  child: const Text('Revoke'),
                                )
                              : null,
                        );
                      }),
                    if (AuthService.userRoles.isAdmin) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Appoint New Moderator (by UID):',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _moderatorUidController,
                              decoration: const InputDecoration(
                                hintText: 'Enter user UID to make moderator',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.deepOrange),
                            onPressed: _loading
                                ? null
                                : () {
                                    final uid =
                                        _moderatorUidController.text.trim();
                                    if (uid.isNotEmpty) {
                                      _toggleModeratorRole(uid, true);
                                    }
                                  },
                            child: const Text('Appoint'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Appointment & Queue Controls
            _sectionTitle('APPOINTMENTS & QUEUE MANAGEMENT'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined,
                        color: Colors.redAccent),
                    title: const Text('Clear All Appointments'),
                    subtitle: const Text(
                        'Deletes all seeded and live patient appointments from Firestore'),
                    trailing: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade50),
                      onPressed: _loading ? null : _clearAllAppointments,
                      child: const Text('Purge',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        const Icon(Icons.playlist_add, color: Colors.green),
                    title: const Text('Seed 5 Sample Appointments'),
                    subtitle: const Text(
                        'Populates live chamber queue with fresh test appointments'),
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
                    leading: const Icon(Icons.medical_services_outlined,
                        color: Colors.blue),
                    title: const Text('Switch to Doctor Portal'),
                    subtitle: const Text(
                        'Active chamber management and live patient queue view'),
                    onTap: () {
                      widget.onRoleChanged?.call(UserRole.doctor);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Switched to Doctor portal view')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.desktop_windows_outlined,
                        color: Colors.indigo),
                    title: const Text('Switch to Operator Desk'),
                    subtitle: const Text(
                        'Reception queue desk for patient check-ins and tickets'),
                    onTap: () {
                      widget.onRoleChanged?.call(UserRole.operator);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Switched to Operator Desk view')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        const Icon(Icons.person_outline, color: Colors.teal),
                    title: const Text('Switch to Guest Patient Mode'),
                    subtitle: const Text(
                        'Clean guest view without doctor/operator tabs'),
                    onTap: () async {
                      await AuthService.setGuestMode(true);
                      widget.onRoleChanged?.call(UserRole.patient);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Switched to Guest Patient view')),
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
                    leading: const Icon(Icons.star_outline,
                        color: Colors.deepOrangeAccent),
                    title: const Text('Firestore Reviews Database Check'),
                    subtitle: const Text('Check reviews collection status'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      setState(() => _loading = true);
                      try {
                        final ratings =
                            await FirestoreService.fetchReviews('doctor_1');
                        setState(() {
                          _lastActionMessage =
                              'Cloud Firestore Reviews Connected (${ratings.length} reviews retrieved).';
                        });
                      } catch (e) {
                        setState(() =>
                            _lastActionMessage = 'Reviews check error: $e');
                      } finally {
                        setState(() => _loading = false);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cable, color: Colors.amber),
                    title: const Text('Test Backend Connection Ping'),
                    subtitle: Text('Current resolved: ${ApiService.baseUrl}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _refreshBackendStats,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined,
                        color: Colors.grey),
                    title: const Text('Reset All Local App Storage'),
                    subtitle: const Text(
                        'Clears SharedPreferences roles, guest mode, and mood keys'),
                    onTap: () async {
                      await AuthService.signOut();
                      await AuthService.setGuestMode(true);
                      widget.onRoleChanged?.call(UserRole.patient);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'All local app storage reset to clean state.')),
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
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 14)),
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
