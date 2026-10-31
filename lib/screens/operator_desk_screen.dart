import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/appointment_queries.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar_button.dart';

/// Operator Desk starts with assigned chambers. Selecting one opens a focused
/// request / queue / completed workspace without exposing document IDs.
class OperatorDeskScreen extends StatefulWidget {
  const OperatorDeskScreen({super.key, this.chamberId, this.showAppBar = true});

  final String? chamberId;
  final bool showAppBar;

  @override
  State<OperatorDeskScreen> createState() => _OperatorDeskScreenState();
}

class _OperatorDeskScreenState extends State<OperatorDeskScreen> {
  final Map<String, String> _chamberNames = {};
  final Map<String, Future<List<String>>> _doctorFutures = {};
  List<String> _assignedChambers = const [];
  bool _loading = true;
  String? _error;

  bool get _isDetail => widget.chamberId != null && widget.chamberId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    try {
      final uid = AuthService.currentUser?.uid;
      final profile = uid == null ? null : await DataService.fetchUserProfile(uid);
      final assigned = (profile?['operatorAssignments'] as List?)
              ?.map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList() ??
          AuthService.userRoles.operatorAssignments;
      final assignedDetails = (profile?['assignedChambers'] as List?) ?? const [];
      for (final detail in assignedDetails) {
        if (detail is Map) {
          final id = (detail['chamberId'] ?? detail['id'] ?? '').toString();
          final name = (detail['chamberName'] ?? detail['name'] ?? '').toString().trim();
          if (id.isNotEmpty && name.isNotEmpty) _chamberNames[id] = name;
        }
      }
      for (final chamberId in assigned) {
        if (_chamberNames.containsKey(chamberId)) continue;
        final chamber = await FirebaseFirestore.instance.collection('chambers').doc(chamberId).get();
        final data = chamber.data();
        final name = (data?['name'] ?? data?['chamberName'] ?? data?['hospitalName'] ?? '').toString().trim();
        if (name.isNotEmpty) _chamberNames[chamberId] = name;
      }
      if (!mounted) return;
      setState(() {
        _assignedChambers = assigned;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load chamber assignments.';
      });
    }
  }

  String _chamberName(String chamberId) => _chamberNames[chamberId] ?? 'Assigned chamber';

  Future<List<String>> _doctorsFor(String chamberId) =>
      _doctorFutures.putIfAbsent(chamberId, () => DataService.fetchChamberDoctors(chamberId));

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _ErrorState(message: _error!, onRetry: _loadAssignments)
            : _isDetail
                ? _ChamberDeskDetail(chamberId: widget.chamberId!, chamberName: _chamberName(widget.chamberId!))
                : _ChamberOverview(
                    chamberIds: _assignedChambers,
                    chamberName: _chamberName,
                    doctorsFor: _doctorsFor,
                  );
    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isDetail ? _chamberName(widget.chamberId!) : 'Desk status'),
        actions: const [ProfileAvatarButton(role: UserRole.operator)],
      ),
      body: body,
    );
  }
}

class _ChamberOverview extends StatelessWidget {
  const _ChamberOverview({
    required this.chamberIds,
    required this.chamberName,
    required this.doctorsFor,
  });

  final List<String> chamberIds;
  final String Function(String) chamberName;
  final Future<List<String>> Function(String) doctorsFor;

  @override
  Widget build(BuildContext context) {
    if (chamberIds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No chamber assignments are available for this operator.'),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AppointmentQueries.pendingRequestsForOperator(chamberIds).snapshots(),
      builder: (context, requestSnapshot) {
        final requests = requestSnapshot.data?.docs ?? const [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Assigned chambers', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Open a chamber to manage requests and today\'s queue.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final chamberId in chamberIds)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ChamberCard(
                  chamberId: chamberId,
                  name: chamberName(chamberId),
                  requestCount: requests.where((doc) => doc.data()['chamberId'] == chamberId).length,
                  doctors: doctorsFor(chamberId),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChamberCard extends StatelessWidget {
  const _ChamberCard({
    required this.chamberId,
    required this.name,
    required this.requestCount,
    required this.doctors,
  });

  final String chamberId;
  final String name;
  final int requestCount;
  final Future<List<String>> doctors;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AppointmentQueries.todayQueueForChamber(chamberId).snapshots(),
      builder: (context, queueSnapshot) {
        final waiting = queueSnapshot.data?.docs.length ?? 0;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            leading: const CircleAvatar(child: Icon(Icons.local_hospital_outlined)),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 5),
                FutureBuilder<List<String>>(
                  future: doctors,
                  builder: (context, snapshot) {
                    final doctorNames = snapshot.data ?? const [];
                    return Text(
                      doctorNames.isEmpty ? 'No doctors listed' : doctorNames.join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                const SizedBox(height: 7),
                Text('$requestCount requests, $waiting waiting', style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OperatorDeskScreen(chamberId: chamberId)),
            ),
          ),
        );
      },
    );
  }
}

class _ChamberDeskDetail extends StatelessWidget {
  const _ChamberDeskDetail({required this.chamberId, required this.chamberName});

  final String chamberId;
  final String chamberName;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(chamberName, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          const TabBar(tabs: [Tab(text: 'Requests'), Tab(text: "Today's Queue"), Tab(text: 'Done')]),
          Expanded(
            child: TabBarView(
              children: [
                _AppointmentList(query: AppointmentQueries.pendingRequestsForOperator([chamberId]), view: _DeskView.requests),
                _AppointmentList(query: AppointmentQueries.todayQueueForChamber(chamberId), view: _DeskView.queue),
                _AppointmentList(query: AppointmentQueries.completedForChamber(chamberId), view: _DeskView.done),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _DeskView { requests, queue, done }

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({required this.query, required this.view});

  final Query<Map<String, dynamic>> query;
  final _DeskView view;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorState(message: 'Unable to load appointments.', onRetry: () {});
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          final message = switch (view) {
            _DeskView.requests => 'No appointment requests.',
            _DeskView.queue => 'No patients are waiting today.',
            _DeskView.done => 'No completed appointments today.',
          };
          return Center(child: Text(message));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _AppointmentRow(
            reference: docs[index].reference,
            data: docs[index].data(),
            view: view,
          ),
        );
      },
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.reference, required this.data, required this.view});

  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> data;
  final _DeskView view;

  DateTime? get _scheduledTime {
    final value = data['scheduledTime'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String get _patientName {
    final value = data['patientName']?.toString().trim() ?? '';
    return value.isEmpty ? 'Patient' : value;
  }

  String get _doctorName {
    final value = data['doctorName']?.toString().trim() ?? '';
    return value.isEmpty ? 'Doctor not specified' : value;
  }

  String _timeLabel(BuildContext context) {
    final time = _scheduledTime;
    if (time == null) return 'Time not selected';
    return TimeOfDay.fromDateTime(time).format(context);
  }

  Future<void> _confirm(BuildContext context) async {
    final initial = _scheduledTime ?? DateTime.now();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (picked == null || !context.mounted) return;
    final date = _scheduledTime ?? DateTime.now();
    final confirmed = DateTime(date.year, date.month, date.day, picked.hour, picked.minute);
    try {
      await DataService.confirmAppointment(appointmentId: reference.id, confirmedTime: confirmed);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment confirmed.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not confirm: $error')));
    }
  }

  Future<void> _reschedule(BuildContext context) async {
    final initial = _scheduledTime ?? DateTime.now();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (picked == null || !context.mounted) return;
    final moved = DateTime(initial.year, initial.month, initial.day, picked.hour, picked.minute);
    try {
      await DataService.rescheduleAppointment(appointmentId: reference.id, newTime: moved);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment rescheduled.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reschedule: $error')));
    }
  }

  Future<void> _reject(BuildContext context) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject request'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Reason required'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Enter a rejection reason.')));
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DataService.rejectAppointment(appointmentId: reference.id, reason: reason.text.trim());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment rejected.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reject: $error')));
    }
  }

  Future<void> _markDone(BuildContext context) async {
    try {
      await FirestoreService.markAppointmentCompletedAndUnlockChat(reference.id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment marked done; follow-up chat unlocked.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not complete: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final queuePosition = (data['queuePosition'] as num?)?.toInt();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(queuePosition == null ? '–' : '#$queuePosition')),
                const SizedBox(width: 12),
                Expanded(child: Text(_patientName, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(_timeLabel(context), style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 7),
            Text(_doctorName, style: Theme.of(context).textTheme.bodySmall),
            if (view == _DeskView.requests) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: FilledButton(onPressed: () => _confirm(context), child: const Text('Confirm'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: () => _reschedule(context), child: const Text('Reschedule'))),
                  IconButton(onPressed: () => _reject(context), tooltip: 'Reject', icon: const Icon(Icons.close, color: Colors.red)),
                ],
              ),
            ] else if (view == _DeskView.queue)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: () => _markDone(context), icon: const Icon(Icons.check_circle_outline), label: const Text('Mark done')),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
