import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/user_role.dart';
import '../widgets/profile_avatar_button.dart';
import '../services/api_service.dart';

// ---------------------------------------------------------------------------
// Local data model — mirrors the MongoDB Appointment schema fields we need.
// ---------------------------------------------------------------------------

class QueueEntry {
  final String id;
  String patientName;
  DateTime scheduledTime;
  String status; // 'waiting' | 'in_progress' | 'done'
  int queuePosition;
  String operatorNote;

  QueueEntry({
    required this.id,
    required this.patientName,
    required this.scheduledTime,
    required this.status,
    required this.queuePosition,
    required this.operatorNote,
  });

  factory QueueEntry.fromJson(Map<String, dynamic> json) => QueueEntry(
        id: json['_id'] as String,
        patientName: (json['patientName'] as String?) ?? 'Patient',
        scheduledTime: DateTime.parse(json['scheduledTime'] as String),
        status: (json['status'] as String?) ?? 'waiting',
        queuePosition: (json['queuePosition'] as int?) ?? 0,
        operatorNote: (json['operatorNote'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------------------
// Main Operator Desk screen
// ---------------------------------------------------------------------------

class OperatorDeskScreen extends StatefulWidget {
  final String chamberId;
  final bool showAppBar;

  const OperatorDeskScreen({
    super.key,
    this.chamberId = 'demo-chamber',
    this.showAppBar = true,
  });

  @override
  State<OperatorDeskScreen> createState() => _OperatorDeskScreenState();
}

class _OperatorDeskScreenState extends State<OperatorDeskScreen> {
  List<QueueEntry> _queue = [];
  bool _loading = true;
  String? _errorMessage;

  /// Tracks which entries have their note editor expanded (by entry id).
  final Set<String> _expandedNotes = {};

  /// TextEditingControllers keyed by entry id, created lazily.
  final Map<String, TextEditingController> _noteControllers = {};

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void dispose() {
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // API helpers
  // ---------------------------------------------------------------------------

  Future<void> _loadQueue() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse(
        '${ApiService.baseUrl}/appointments/today?chamberId=${widget.chamberId}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>? ?? [];
        final entries = data
            .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
            .toList();

        _applyQueue(entries);
        return;
      } else {
        setState(() {
          _loading = false;
          _errorMessage = 'Server error (${response.statusCode}). Please retry.';
        });
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _errorMessage = 'Could not reach server. Check your connection.';
      });
    }
  }

  void _applyQueue(List<QueueEntry> entries) {
    entries.sort((a, b) => a.queuePosition.compareTo(b.queuePosition));

    // Dispose controllers for entries that are no longer present.
    final incomingIds = entries.map((e) => e.id).toSet();
    for (final id in _noteControllers.keys.toSet().difference(incomingIds)) {
      _noteControllers[id]?.dispose();
      _noteControllers.remove(id);
    }

    // Initialise controllers for new entries.
    for (final entry in entries) {
      _noteControllers.putIfAbsent(
        entry.id,
        () => TextEditingController(text: entry.operatorNote),
      );
    }

    setState(() {
      _queue = entries;
      _loading = false;
      _errorMessage = null;
    });
  }

  /// PATCH /appointments/queue-order — persist reordered positions.
  Future<void> _persistQueueOrder() async {
    try {
      final updates = _queue
          .asMap()
          .entries
          .map((e) => {'id': e.value.id, 'queuePosition': e.key + 1})
          .toList();

      await http
          .patch(
            Uri.parse('${ApiService.baseUrl}/appointments/queue-order'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'updates': updates}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Local state already updated
    }
  }

  /// PATCH /appointments/:id — update one or more fields on a single entry.
  Future<void> _patchAppointment(
    String id,
    Map<String, dynamic> fields,
  ) async {
    try {
      await http
          .patch(
            Uri.parse('${ApiService.baseUrl}/appointments/$id'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(fields),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Optimistic update
    }
  }

  // ---------------------------------------------------------------------------
  // Interaction handlers
  // ---------------------------------------------------------------------------

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final entry = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, entry);
      for (int i = 0; i < _queue.length; i++) {
        _queue[i].queuePosition = i + 1;
      }
    });
    _persistQueueOrder();
  }

  void _toggleNote(String id) {
    setState(() {
      if (_expandedNotes.contains(id)) {
        _expandedNotes.remove(id);
      } else {
        _expandedNotes.add(id);
      }
    });
  }

  void _submitNote(QueueEntry entry) {
    final note = _noteControllers[entry.id]?.text.trim() ?? '';
    if (note == entry.operatorNote) return;
    setState(() => entry.operatorNote = note);
    _patchAppointment(entry.id, {'operatorNote': note});
  }

  Future<void> _deleteAppointment(QueueEntry entry) async {
    setState(() {
      _queue.removeWhere((e) => e.id == entry.id);
      for (int i = 0; i < _queue.length; i++) {
        _queue[i].queuePosition = i + 1;
      }
    });
    try {
      await http.delete(Uri.parse('${ApiService.baseUrl}/appointments/${entry.id}')).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Future<void> _clearAllAppointments() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Appointments?'),
        content: const Text('This will remove all hardcoded and current appointments from the queue.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Queue'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _queue.clear());
    try {
      await http.delete(Uri.parse('${ApiService.baseUrl}/appointments/clear/all')).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  void _showAddAppointmentDialog() {
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Add Patient to Queue'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Patient Name', hintText: 'e.g. John Doe'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: Text('Scheduled Time: ${selectedTime.format(context)}'),
                trailing: TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: selectedTime);
                    if (t != null) setDlgState(() => selectedTime = t);
                  },
                  child: const Text('Change'),
                ),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Desk Note (Optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final now = DateTime.now();
                final sched = DateTime(now.year, now.month, now.day, selectedTime.hour, selectedTime.minute);

                try {
                  final res = await ApiService.postRequest(
                    '/appointments',
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'patientName': name,
                      'scheduledTime': sched.toIso8601String(),
                      'chamberId': widget.chamberId,
                      'status': 'waiting',
                      'operatorNote': noteController.text.trim(),
                    }),
                  );
                  if (res.statusCode == 201 || res.statusCode == 200) {
                    await _loadQueue();
                  }
                } catch (_) {}
              },
              child: const Text('Add Patient'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAppointmentDialog(QueueEntry entry) {
    final nameController = TextEditingController(text: entry.patientName);
    final noteController = TextEditingController(text: entry.operatorNote);
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(entry.scheduledTime);
    String currentStatus = entry.status;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Edit Appointment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Patient Name'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: Text('Time: ${selectedTime.format(context)}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: selectedTime);
                      if (t != null) setDlgState(() => selectedTime = t);
                    },
                    child: const Text('Pick Time'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Status:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['waiting', 'in_progress', 'done'].map((s) {
                    return ChoiceChip(
                      label: Text(_chipLabel(s)),
                      selected: currentStatus == s,
                      onSelected: (_) => setDlgState(() => currentStatus = s),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Desk Note', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
              onPressed: () {
                Navigator.pop(ctx);
                _deleteAppointment(entry);
              },
            ),
            FilledButton(
              onPressed: () {
                final newName = nameController.text.trim();
                final now = entry.scheduledTime;
                final newTime = DateTime(now.year, now.month, now.day, selectedTime.hour, selectedTime.minute);
                final newNote = noteController.text.trim();

                setState(() {
                  if (newName.isNotEmpty) entry.patientName = newName;
                  entry.scheduledTime = newTime;
                  entry.status = currentStatus;
                  entry.operatorNote = newNote;
                });
                _patchAppointment(entry.id, {
                  'patientName': entry.patientName,
                  'scheduledTime': newTime.toIso8601String(),
                  'status': currentStatus,
                  'operatorNote': newNote,
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save Details'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Display helpers
  // ---------------------------------------------------------------------------

  int get _remainingCount => _queue.where((e) => e.status != 'done').length;

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Color _chipBg(String status, ColorScheme cs) => switch (status) {
        'in_progress' => cs.primaryContainer,
        'done' => const Color(0xFFC8E6C9), // green[100]
        _ => const Color(0xFFE0E0E0), // grey[300]
      };

  Color _chipFg(String status, ColorScheme cs) => switch (status) {
        'in_progress' => cs.onPrimaryContainer,
        'done' => const Color(0xFF2E7D32), // green[800]
        _ => const Color(0xFF616161), // grey[700]
      };

  String _chipLabel(String status) => switch (status) {
        'in_progress' => 'In Progress',
        'done' => 'Done',
        _ => 'Waiting',
      };

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final body = _buildBody(cs);

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chamber Queue — Today'),
            if (!_loading && _errorMessage == null)
              Text(
                '${_queue.length} patient${_queue.length == 1 ? '' : 's'}'
                ' · $_remainingCount remaining',
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
              ),
          ],
        ),
        actions: const [
          ProfileAvatarButton(role: UserRole.operator),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadQueue,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      body: body,
    );
  }

  Widget _buildBody(ColorScheme cs) {
    // 1. Loading State
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading live patient queue...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // 2. Error State + Retry Button (Standardized across app)
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined, size: 56, color: cs.error),
              const SizedBox(height: 16),
              Text(
                'Error loading queue',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.error),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadQueue,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Honest Empty State (No fake fallback)
    if (_queue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_available_outlined, size: 56, color: Colors.grey[350]),
              const SizedBox(height: 16),
              Text(
                'No patients in queue today.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'New patient appointments scheduled for this chamber will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadQueue,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Check for Updates'),
              ),
            ],
          ),
        ),
      );
    }

    // 4. Success State — Interactive Reorderable List with controls
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Live Queue (${_queue.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _showAddAppointmentDialog,
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('Add Patient'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                    tooltip: 'Clear all/hardcoded appointments',
                    onPressed: _clearAllAppointments,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 88),
            itemCount: _queue.length,
            buildDefaultDragHandles: false,
            // ignore: deprecated_member_use
            onReorder: _onReorder,
            proxyDecorator: (child, index, animation) => Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: Colors.transparent,
              child: child,
            ),
            itemBuilder: (context, index) {
              final entry = _queue[index];
              final expanded = _expandedNotes.contains(entry.id);
              return _buildTile(
                context: context,
                entry: entry,
                index: index,
                cs: cs,
                expanded: expanded,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required QueueEntry entry,
    required int index,
    required ColorScheme cs,
    required bool expanded,
  }) {
    return Padding(
      key: ValueKey(entry.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color: cs.surface,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.only(
                  left: 4,
                  right: 4,
                  top: 2,
                  bottom: 2,
                ),
                onTap: () => _showEditAppointmentDialog(entry),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        entry.status == 'done' ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: entry.status == 'done' ? const Color(0xFF16A34A) : Colors.grey.shade400,
                        size: 24,
                      ),
                      tooltip: entry.status == 'done' ? 'Mark as Waiting' : 'Tick as Done',
                      onPressed: () {
                        final nextStatus = entry.status == 'done' ? 'waiting' : 'done';
                        setState(() => entry.status = nextStatus);
                        _patchAppointment(entry.id, {'status': nextStatus});
                      },
                    ),
                    _PositionBadge(
                      position: entry.queuePosition,
                      bgColor: cs.primary,
                      fgColor: cs.onPrimary,
                    ),
                  ],
                ),
                title: Text(
                  entry.patientName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: entry.status == 'done' ? TextDecoration.lineThrough : null,
                    color: entry.status == 'done' ? Colors.grey : null,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Text(
                      _formatTime(entry.scheduledTime),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: _chipLabel(entry.status),
                      bgColor: _chipBg(entry.status, cs),
                      fgColor: _chipFg(entry.status, cs),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit details',
                      icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey[700]),
                      onPressed: () => _showEditAppointmentDialog(entry),
                    ),
                    IconButton(
                      tooltip: expanded ? 'Hide note' : 'Add / view note',
                      icon: Icon(
                        expanded ? Icons.notes : Icons.edit_note_outlined,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      onPressed: () => _toggleNote(entry.id),
                      visualDensity: VisualDensity.compact,
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.drag_handle, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: _NoteEditor(
                  controller: _noteControllers[entry.id]!,
                  onSubmitted: () => _submitNote(entry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  final int position;
  final Color bgColor;
  final Color fgColor;

  const _PositionBadge({
    required this.position,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: bgColor,
      child: Text(
        '$position',
        style: TextStyle(
          color: fgColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color fgColor;

  const _StatusChip({
    required this.label,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
    );
  }
}

class _NoteEditor extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const _NoteEditor({
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: controller,
        maxLines: 2,
        minLines: 1,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Operator note…',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        onEditingComplete: onSubmitted,
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}
