import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChamberResolver {
  static final Map<String, String> _cache = {};

  static String getCached(String? chamberId) {
    if (chamberId == null || chamberId.isEmpty) return 'Chamber';
    return _cache[chamberId] ?? 'Chamber';
  }

  static void cache(String chamberId, String name) {
    if (chamberId.isNotEmpty && name.isNotEmpty && !name.startsWith('chamber-')) {
      _cache[chamberId] = name;
    }
  }

  static Future<String> resolveChamberName({
    String? chamberId,
    String? storedName,
    String? doctorId,
  }) async {
    if (storedName != null &&
        storedName.isNotEmpty &&
        storedName != chamberId &&
        !storedName.startsWith('chamber-')) {
      if (chamberId != null && chamberId.isNotEmpty) {
        _cache[chamberId] = storedName;
      }
      return storedName;
    }

    if (chamberId == null || chamberId.isEmpty || chamberId == 'demo-chamber') {
      return 'Main Chamber';
    }

    if (_cache.containsKey(chamberId)) {
      return _cache[chamberId]!;
    }

    try {
      // 1. Try chambers collection
      final chamberSnap = await FirebaseFirestore.instance
          .collection('chambers')
          .doc(chamberId)
          .get();
      if (chamberSnap.exists) {
        final data = chamberSnap.data() ?? {};
        final name = (data['hospitalName'] ?? data['name'] ?? '').toString().trim();
        if (name.isNotEmpty && !name.startsWith('chamber-')) {
          _cache[chamberId] = name;
          return name;
        }
      }

      // 2. Try doctor document's chambers list
      if (doctorId != null && doctorId.isNotEmpty) {
        final docSnap = await FirebaseFirestore.instance
            .collection('doctors')
            .doc(doctorId)
            .get();
        if (docSnap.exists) {
          final rawChambers = (docSnap.data()?['chambers'] as List?) ?? [];
          for (final c in rawChambers) {
            final cMap = Map<String, dynamic>.from(c as Map);
            final cId = (cMap['id'] ?? '').toString();
            final cName = (cMap['hospitalName'] ?? cMap['name'] ?? '').toString().trim();
            if (cId == chamberId && cName.isNotEmpty && !cName.startsWith('chamber-')) {
              _cache[chamberId] = cName;
              return cName;
            }
          }
        }
      }
    } catch (_) {}

    debugPrint('[ChamberResolver] Could not resolve chamberId: $chamberId');
    return 'Chamber';
  }
}
