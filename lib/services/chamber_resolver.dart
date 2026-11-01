import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChamberRecord {
  final String id;
  final String name;
  final String? doctorId;
  final String? visitingHours;
  final int slotMinutes;
  final bool hasOperator;
  final String? operatorUid;
  final Map<String, dynamic> raw;

  const ChamberRecord({
    required this.id,
    required this.name,
    this.doctorId,
    this.visitingHours,
    this.slotMinutes = 10,
    this.hasOperator = false,
    this.operatorUid,
    this.raw = const {},
  });
}

class ChamberResolver {
  static final Map<String, String> _cache = {};
  static final Map<String, ChamberRecord> _recordCache = {};

  static String getCached(String? chamberId) {
    if (chamberId == null || chamberId.isEmpty) return 'Chamber';
    return _cache[chamberId] ?? 'Chamber';
  }

  static void cache(String chamberId, String name) {
    if (chamberId.isNotEmpty && name.isNotEmpty && !name.startsWith('chamber-')) {
      _cache[chamberId] = name;
    }
  }

  static void cacheRecord(String chamberId, ChamberRecord record) {
    if (chamberId.isNotEmpty) {
      _recordCache[chamberId] = record;
      if (record.name.isNotEmpty && !record.name.startsWith('chamber-')) {
        _cache[chamberId] = record.name;
      }
    }
  }

  static Future<ChamberRecord?> resolveChamberRecord({
    String? chamberId,
    String? doctorId,
    String? storedName,
  }) async {
    final key = chamberId ?? storedName ?? '';
    if (key.isNotEmpty && _recordCache.containsKey(key)) {
      return _recordCache[key];
    }

    try {
      // 1. Check top-level chambers collection by ID
      if (chamberId != null && chamberId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('chambers')
            .doc(chamberId)
            .get();
        if (snap.exists) {
          final d = snap.data() ?? {};
          final name = (d['hospitalName'] ?? d['name'] ?? d['chamberName'] ?? '').toString().trim();
          final cleanName = (name.isNotEmpty && !name.startsWith('chamber-'))
              ? name
              : (storedName != null && storedName.isNotEmpty && !storedName.startsWith('chamber-'))
                  ? storedName
                  : 'Chamber';
          final rec = ChamberRecord(
            id: snap.id,
            name: cleanName,
            doctorId: (d['doctorId'] ?? doctorId)?.toString(),
            visitingHours: d['visitingHours']?.toString(),
            slotMinutes: ((d['slotMinutes'] as num?)?.toInt() ?? 10).clamp(5, 15),
            hasOperator: d['hasOperator'] == true || d['operatorUid'] != null,
            operatorUid: d['operatorUid']?.toString(),
            raw: d,
          );
          cacheRecord(snap.id, rec);
          if (chamberId != snap.id) cacheRecord(chamberId, rec);
          return rec;
        }
      }

      // 2. Check doctor's embedded chambers list
      if (doctorId != null && doctorId.isNotEmpty) {
        final docSnap = await FirebaseFirestore.instance
            .collection('doctors')
            .doc(doctorId)
            .get();
        if (docSnap.exists) {
          final rawChambers = (docSnap.data()?['chambers'] as List?) ?? [];
          for (final c in rawChambers) {
            if (c is! Map) continue;
            final cMap = Map<String, dynamic>.from(c);
            final cId = (cMap['id'] ?? '').toString().trim();
            final cName = (cMap['hospitalName'] ?? cMap['name'] ?? '').toString().trim();

            final matchesId = chamberId != null && chamberId.isNotEmpty && (cId == chamberId || cName == chamberId);
            final matchesName = storedName != null && storedName.isNotEmpty && (cName == storedName || cId == storedName);

            if (matchesId || matchesName || rawChambers.length == 1) {
              final cleanName = (cName.isNotEmpty && !cName.startsWith('chamber-'))
                  ? cName
                  : (storedName != null && storedName.isNotEmpty && !storedName.startsWith('chamber-'))
                      ? storedName
                      : 'Chamber';
              final resolvedId = cId.isNotEmpty ? cId : (chamberId ?? 'demo-chamber');
              final rec = ChamberRecord(
                id: resolvedId,
                name: cleanName,
                doctorId: doctorId,
                visitingHours: (cMap['visitingHours'] ?? cMap['hours'])?.toString(),
                slotMinutes: ((cMap['slotMinutes'] as num?)?.toInt() ?? 10).clamp(5, 15),
                hasOperator: cMap['hasOperator'] == true || cMap['operatorUid'] != null,
                operatorUid: cMap['operatorUid']?.toString(),
                raw: cMap,
              );
              cacheRecord(resolvedId, rec);
              if (chamberId != null && chamberId.isNotEmpty) cacheRecord(chamberId, rec);
              return rec;
            }
          }
        }
      }

      // 3. Fallback: query chambers collection by name or doctorId
      if (storedName != null && storedName.isNotEmpty && !storedName.startsWith('chamber-')) {
        final nameSnap = await FirebaseFirestore.instance
            .collection('chambers')
            .where('name', isEqualTo: storedName)
            .limit(1)
            .get();
        if (nameSnap.docs.isNotEmpty) {
          final doc = nameSnap.docs.first;
          final d = doc.data();
          final rec = ChamberRecord(
            id: doc.id,
            name: storedName,
            doctorId: (d['doctorId'] ?? doctorId)?.toString(),
            visitingHours: d['visitingHours']?.toString(),
            slotMinutes: ((d['slotMinutes'] as num?)?.toInt() ?? 10).clamp(5, 15),
            hasOperator: d['hasOperator'] == true || d['operatorUid'] != null,
            operatorUid: d['operatorUid']?.toString(),
            raw: d,
          );
          cacheRecord(doc.id, rec);
          return rec;
        }
      }
    } catch (e) {
      debugPrint('[ChamberResolver] Error resolving chamber: $e');
    }

    final fallbackName = (storedName != null && storedName.isNotEmpty && !storedName.startsWith('chamber-'))
        ? storedName
        : 'Chamber';
    final fallbackRec = ChamberRecord(
      id: chamberId ?? 'chamber',
      name: fallbackName,
      doctorId: doctorId,
      slotMinutes: 10,
    );
    if (chamberId != null && chamberId.isNotEmpty) {
      cacheRecord(chamberId, fallbackRec);
    }
    return fallbackRec;
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

    final rec = await resolveChamberRecord(
      chamberId: chamberId,
      doctorId: doctorId,
      storedName: storedName,
    );
    return rec?.name ?? 'Chamber';
  }
}
