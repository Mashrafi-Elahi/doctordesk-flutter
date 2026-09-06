import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../widgets/profile_avatar_button.dart';
import '../widgets/chamber_accessibility.dart';
import 'operator_desk_screen.dart';

/// Doctor's Manage Tab — Exactly 2 sections:
/// 1. Patient Queue (today's live line, intake info, serial numbers, reorderable)
/// 2. Chamber Cards (manage chamber details, assign/add/remove operators)
class DoctorManagerScreen extends StatefulWidget {
  const DoctorManagerScreen({super.key});

  @override
  State<DoctorManagerScreen> createState() => _DoctorManagerScreenState();
}

class _DoctorManagerScreenState extends State<DoctorManagerScreen> {
  // Sample chambers for the logged-in doctor
  final List<Map<String, dynamic>> _chambers = [
    {
      'id': 'chamber-1',
      'name': 'Aalok Healthcare Ltd.',
      'area': 'Mirpur 10, Dhaka',
      'visitingHours': '5:00 PM – 9:00 PM (Sat–Thu)',
      'fee': 800,
      'hasOperator': true,
      'operatorName': 'Popular Diagnostic Desk Operator',
      'operatorEmail': 'operator@mail.com',
      'wheelchairEntrance': true,
      'wheelchairParking': true,
      'liftAvailable': true,
      'accessibleToilet': true,
    },
    {
      'id': 'chamber-2',
      'name': 'Ibn Sina Diagnostic Center',
      'area': 'Dhanmondi, Dhaka',
      'visitingHours': '10:00 AM – 1:00 PM (Fri Only)',
      'fee': 1000,
      'hasOperator': false,
      'operatorName': null,
      'operatorEmail': null,
      'wheelchairEntrance': true,
      'wheelchairParking': false,
      'liftAvailable': true,
      'accessibleToilet': false,
    },
  ];

  void _toggleOperator(int index) {
    setState(() {
      final ch = _chambers[index];
      if (ch['hasOperator'] == true) {
        ch['hasOperator'] = false;
        ch['operatorName'] = null;
        ch['operatorEmail'] = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operator removed from ${ch['name']}. You are now running this queue directly.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ch['hasOperator'] = true;
        ch['operatorName'] = 'Assigned Desk Operator';
        ch['operatorEmail'] = 'operator@docdesk.local';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operator assigned to ${ch['name']}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Doctor Management'),
          actions: const [
            ProfileAvatarButton(role: UserRole.doctor),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(
                icon: Icon(Icons.people_outline, size: 20),
                text: 'Patient Queue',
              ),
              Tab(
                icon: Icon(Icons.apartment_outlined, size: 20),
                text: 'Chambers',
              ),
            ],
            labelColor: colorScheme.primary,
            indicatorColor: colorScheme.primary,
          ),
        ),
        body: TabBarView(
          children: [
            // Section 1: Patient Queue (Live Queue Desk)
            const OperatorDeskScreen(showAppBar: false),

            // Section 2: Chamber Cards & Operator Assignment
            _buildChambersSection(colorScheme),
          ],
        ),
      ),
    );
  }

  void _showAddChamberDialog() {
    final nameCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final hoursCtrl = TextEditingController(text: '5:00 PM – 9:00 PM (Sat–Thu)');
    final feeCtrl = TextEditingController(text: '800');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Chamber Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Hospital / Clinic Name', hintText: 'e.g. Popular Diagnostic'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: areaCtrl,
                decoration: const InputDecoration(labelText: 'Area / Location', hintText: 'e.g. Dhanmondi, Dhaka'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hoursCtrl,
                decoration: const InputDecoration(labelText: 'Visiting Hours'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Consultation Fee (৳)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final area = areaCtrl.text.trim();
              if (name.isEmpty) return;
              setState(() {
                _chambers.add({
                  'id': 'chamber-${DateTime.now().millisecondsSinceEpoch}',
                  'name': name,
                  'area': area.isEmpty ? 'Dhaka' : area,
                  'visitingHours': hoursCtrl.text.trim(),
                  'fee': int.tryParse(feeCtrl.text.trim()) ?? 800,
                  'hasOperator': false,
                  'operatorName': null,
                  'operatorEmail': null,
                  'wheelchairEntrance': true,
                  'wheelchairParking': true,
                  'liftAvailable': true,
                  'accessibleToilet': true,
                });
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$name added to your active chambers.')),
              );
            },
            child: const Text('Save Chamber'),
          ),
        ],
      ),
    );
  }

  void _showAssignOperatorDialog(int index) {
    final nameCtrl = TextEditingController(text: 'Desk Assistant 01');
    final emailCtrl = TextEditingController(text: 'operator@popular.com');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign Desk Operator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Assign a hospital receptionist or chamber assistant to manage live serial tickets.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Operator Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Operator Email'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _chambers[index]['hasOperator'] = true;
                _chambers[index]['operatorName'] = nameCtrl.text.trim();
                _chambers[index]['operatorEmail'] = emailCtrl.text.trim();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Operator assigned to ${_chambers[index]['name']}.')),
              );
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  Widget _buildChambersSection(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Chambers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_chambers.length} active chamber locations',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            FilledButton.tonalIcon(
              onPressed: _showAddChamberDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Chamber'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._chambers.asMap().entries.map((entry) {
          final i = entry.key;
          final chamber = entry.value;
          final hasOp = chamber['hasOperator'] == true;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        child: Icon(Icons.local_hospital_outlined, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chamber['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chamber['area'] as String,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      AccessibilityIcon(
                        accessibility: ChamberAccessibility(
                          wheelchairEntrance: chamber['wheelchairEntrance'] == true,
                          wheelchairParking: chamber['wheelchairParking'] == true,
                          liftAvailable: chamber['liftAvailable'] == true,
                          accessibleToilet: chamber['accessibleToilet'] == true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        chamber['visitingHours'] as String,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      const Spacer(),
                      Text(
                        '৳${chamber['fee']}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Operator Status Box
                  if (hasOp) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Color(0xFF16A34A), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Assigned Operator',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                                Text(
                                  chamber['operatorName'] as String,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _toggleOperator(i),
                            child: const Text('Remove', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Nudge/Banner: Doctor runs queue themselves
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: Colors.amber.shade900),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No operator assigned — you run this queue directly',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Assign a desk assistant or hospital receptionist to manage tickets and call patients.',
                            style: TextStyle(fontSize: 11.5, color: Colors.brown.shade700),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => _showAssignOperatorDialog(i),
                            icon: const Icon(Icons.person_add_alt_1, size: 16),
                            label: const Text('Assign Operator'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
