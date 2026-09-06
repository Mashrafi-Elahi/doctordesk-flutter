// chamber_accessibility.dart
//
// Wheelchair-accessibility tiering for chambers. Entrance access is a mandatory
// gate — no entrance access, no icon, regardless of other amenities. Above the
// gate, tier color is computed client-side from a weighted score (toilet counts
// double since it's the rarest amenity). Change WEIGHTS below to retune —
// no backend/data migration needed since raw booleans are the source of truth.

import 'package:flutter/material.dart';

enum AccessibilityTier { none, orange, yellow, green }

class ChamberAccessibility {
  final bool wheelchairEntrance; // GATE — ramp / no stairs at entrance
  final bool wheelchairParking;
  final bool liftAvailable;
  final bool accessibleToilet; // rarest amenity — weighted higher

  const ChamberAccessibility({
    required this.wheelchairEntrance,
    required this.wheelchairParking,
    required this.liftAvailable,
    required this.accessibleToilet,
  });

  factory ChamberAccessibility.fromJson(Map<String, dynamic> j) => ChamberAccessibility(
        wheelchairEntrance: j['wheelchairEntrance'] as bool? ?? false,
        wheelchairParking: j['wheelchairParking'] as bool? ?? false,
        liftAvailable: j['liftAvailable'] as bool? ?? false,
        accessibleToilet: j['accessibleToilet'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'wheelchairEntrance': wheelchairEntrance,
        'wheelchairParking': wheelchairParking,
        'liftAvailable': liftAvailable,
        'accessibleToilet': accessibleToilet,
      };

  // Tune these without touching backend data.
  static const int _parkingWeight = 1;
  static const int _liftWeight = 1;
  static const int _toiletWeight = 2; // rarer amenity, counts double
  static const int _maxScore = _parkingWeight + _liftWeight + _toiletWeight; // 4

  AccessibilityTier get tier {
    if (!wheelchairEntrance) return AccessibilityTier.none; // gate — no icon at all

    int score = 0;
    if (wheelchairParking) score += _parkingWeight;
    if (liftAvailable) score += _liftWeight;
    if (accessibleToilet) score += _toiletWeight;

    if (score >= _maxScore) return AccessibilityTier.green; // all amenities
    if (score > _maxScore / 2) return AccessibilityTier.yellow; // more than half
    if (score >= 1) return AccessibilityTier.orange; // at least one amenity
    return AccessibilityTier.none; // entrance only, nothing else — not worth showing
  }
}

class AccessibilityIcon extends StatelessWidget {
  final ChamberAccessibility accessibility;
  const AccessibilityIcon({super.key, required this.accessibility});

  @override
  Widget build(BuildContext context) {
    final tier = accessibility.tier;
    if (tier == AccessibilityTier.none) return const SizedBox.shrink();

    final Color color = switch (tier) {
      AccessibilityTier.orange => Colors.orange,
      AccessibilityTier.yellow => Colors.amber.shade800,
      AccessibilityTier.green => Colors.green,
      AccessibilityTier.none => Colors.transparent,
    };

    final String label = switch (tier) {
      AccessibilityTier.orange => 'Basic wheelchair accessibility',
      AccessibilityTier.yellow => 'Good wheelchair accessibility',
      AccessibilityTier.green => 'Full wheelchair accessibility, including accessible toilet',
      AccessibilityTier.none => '',
    };

    return Tooltip(
      message: label,
      child: Semantics(
        label: label, // screen-reader support
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.accessible, size: 16, color: color),
        ),
      ),
    );
  }
}

/// Toggle form used in the chamber add/edit flow (doctor or desk operator side).
class ChamberAccessibilityForm extends StatefulWidget {
  final ChamberAccessibility initial;
  final ValueChanged<ChamberAccessibility> onChanged;

  const ChamberAccessibilityForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<ChamberAccessibilityForm> createState() => _ChamberAccessibilityFormState();
}

class _ChamberAccessibilityFormState extends State<ChamberAccessibilityForm> {
  late bool _entrance = widget.initial.wheelchairEntrance;
  late bool _parking = widget.initial.wheelchairParking;
  late bool _lift = widget.initial.liftAvailable;
  late bool _toilet = widget.initial.accessibleToilet;

  void _emit() {
    widget.onChanged(ChamberAccessibility(
      wheelchairEntrance: _entrance,
      wheelchairParking: _parking,
      liftAvailable: _lift,
      accessibleToilet: _toilet,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Accessibility (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'A chamber needs at least wheelchair-accessible entrance to show an accessibility badge.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        SwitchListTile(
          title: const Text('Wheelchair-accessible entrance (no stairs / ramp)'),
          value: _entrance,
          onChanged: (v) { setState(() => _entrance = v); _emit(); },
        ),
        SwitchListTile(
          title: const Text('Wheelchair parking available'),
          value: _parking,
          onChanged: (v) { setState(() => _parking = v); _emit(); },
        ),
        SwitchListTile(
          title: const Text('Lift / elevator available'),
          value: _lift,
          onChanged: (v) { setState(() => _lift = v); _emit(); },
        ),
        SwitchListTile(
          title: const Text('Accessible toilet available'),
          value: _toilet,
          onChanged: (v) { setState(() => _toilet = v); _emit(); },
        ),
      ],
    );
  }
}
