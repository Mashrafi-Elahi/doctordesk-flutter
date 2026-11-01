import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChamberRecord {
  final String id;
  final String name;
  final String address;
  final String area;
  final String? visitingHours; // display string
  final Map<String, dynamic>? visitingHoursStructured;
  final int slotMinutes;
  final String? ownerDoctorId;
  final List<String> doctorIds;
  final Map<String, String> members; // { doctorId: 'owner' | 'visiting' }
  final bool isAccessible;
  final double fee;
  final bool hasOperator;
  final String? operatorUid;
  final List<String> aliases;
  final Map<String, dynamic> raw;

  const ChamberRecord({
    required this.id,
    required this.name,
    this.address = '',
    this.area = '',
    this.visitingHours,
    this.visitingHoursStructured,
    this.slotMinutes = 10,
    this.ownerDoctorId,
    this.doctorIds = const [],
    this.members = const {},
    this.isAccessible = false,
    this.fee = 500.0,
    this.hasOperator = false,
    this.operatorUid,
    this.aliases = const [],
    this.raw = const {},
  });

  String? get doctorId => ownerDoctorId ?? (doctorIds.isNotEmpty ? doctorIds.first : null);
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
    if (chamberId.isEmpty) return;
    _recordCache[chamberId] = record;
    if (record.id.isNotEmpty) _recordCache[record.id] = record;
    if (record.name.isNotEmpty && !record.name.startsWith('chamber-')) {
      _cache[chamberId] = record.name;
      _cache[record.id] = record.name;
      _cache[record.name] = record.name;
    }
    for (final alias in record.aliases) {
      if (alias.isNotEmpty) {
        _recordCache[alias] = record;
        if (!alias.startsWith('chamber-')) {
          _cache[alias] = record.name;
        }
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
    if (storedName != null && storedName.isNotEmpty && _recordCache.containsKey(storedName)) {
      return _recordCache[storedName];
    }

    try {
      final db = FirebaseFirestore.instance;

      // 1. Check top-level chambers collection by ID
      if (chamberId != null && chamberId.isNotEmpty) {
        var snap = await db.collection('chambers').doc(chamberId).get();
        if (snap.exists) {
          var d = snap.data() ?? {};
          // If this document is an alias pointer, resolve the canonical document
          if (d['canonicalChamberId'] != null && d['canonicalChamberId'].toString().isNotEmpty) {
            final canonId = d['canonicalChamberId'].toString();
            final canonSnap = await db.collection('chambers').doc(canonId).get();
            if (canonSnap.exists) {
              snap = canonSnap;
              d = canonSnap.data() ?? {};
            }
          }

          final rec = _parseDoc(snap.id, d, storedName: storedName, defaultDoctorId: doctorId);
          cacheRecord(snap.id, rec);
          if (chamberId != snap.id) cacheRecord(chamberId, rec);
          return rec;
        }

        // Check if any canonical chamber has this chamberId in its aliases
        final aliasSnap = await db.collection('chambers')
            .where('aliases', arrayContains: chamberId)
            .limit(1)
            .get();
        if (aliasSnap.docs.isNotEmpty) {
          final doc = aliasSnap.docs.first;
          final rec = _parseDoc(doc.id, doc.data(), storedName: storedName, defaultDoctorId: doctorId);
          cacheRecord(doc.id, rec);
          cacheRecord(chamberId, rec);
          return rec;
        }
      }

      // 2. Check chambers collection by storedName / aliases
      if (storedName != null && storedName.isNotEmpty && !storedName.startsWith('chamber-')) {
        final nameSnap = await db.collection('chambers')
            .where('name', isEqualTo: storedName)
            .limit(1)
            .get();
        if (nameSnap.docs.isNotEmpty) {
          final doc = nameSnap.docs.first;
          final rec = _parseDoc(doc.id, doc.data(), storedName: storedName, defaultDoctorId: doctorId);
          cacheRecord(doc.id, rec);
          return rec;
        }

        final aliasNameSnap = await db.collection('chambers')
            .where('aliases', arrayContains: storedName)
            .limit(1)
            .get();
        if (aliasNameSnap.docs.isNotEmpty) {
          final doc = aliasNameSnap.docs.first;
          final rec = _parseDoc(doc.id, doc.data(), storedName: storedName, defaultDoctorId: doctorId);
          cacheRecord(doc.id, rec);
          return rec;
        }
      }

      // 3. Check doctor's embedded chambers list
      if (doctorId != null && doctorId.isNotEmpty) {
        final docSnap = await db.collection('doctors').doc(doctorId).get();
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
              final resolvedId = cId.isNotEmpty ? cId : (chamberId ?? 'demo-chamber');
              final rec = _parseDoc(resolvedId, cMap, storedName: storedName, defaultDoctorId: doctorId);
              cacheRecord(resolvedId, rec);
              if (chamberId != null && chamberId.isNotEmpty) cacheRecord(chamberId, rec);
              return rec;
            }
          }
        }
      }

      // 4. Search registered target doctors (by doctorProfileId or doctor document)
      if (chamberId != null && chamberId.isNotEmpty) {
        final docsSnap = await db.collection('doctors').limit(150).get();
        for (final doc in docsSnap.docs) {
          final d = doc.data();
          if (d['isDeleted'] == true || d['isHidden'] == true ||
              d['status'] == 'deleted' || d['status'] == 'hidden') {
            continue;
          }
          final rawChambers = (d['chambers'] as List?) ?? [];
          for (final c in rawChambers) {
            if (c is! Map) continue;
            final cMap = Map<String, dynamic>.from(c);
            final cId = (cMap['id'] ?? '').toString().trim();
            final cName = (cMap['name'] ?? '').toString().trim();
            final cHospital = (cMap['hospitalName'] ?? '').toString().trim();

            final matchesId = (cId.isNotEmpty && cId == chamberId) ||
                (cName.isNotEmpty && cName == chamberId) ||
                (cHospital.isNotEmpty && cHospital == chamberId);
            final matchesName = storedName != null && storedName.isNotEmpty &&
                (cName == storedName || cHospital == storedName || cId == storedName);

            if (matchesId || matchesName) {
              final resolvedId = cId.isNotEmpty ? cId : chamberId;
              final rec = _parseDoc(resolvedId, cMap, storedName: storedName, defaultDoctorId: doc.id);
              cacheRecord(resolvedId, rec);
              cacheRecord(chamberId, rec);
              return rec;
            }
          }
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
      ownerDoctorId: doctorId,
      slotMinutes: 10,
    );
    if (chamberId != null && chamberId.isNotEmpty) {
      cacheRecord(chamberId, fallbackRec);
    }
    return fallbackRec;
  }

  static ChamberRecord _parseDoc(
    String id,
    Map<String, dynamic> d, {
    String? storedName,
    String? defaultDoctorId,
  }) {
    final rawName = (d['name'] ?? d['hospitalName'] ?? d['chamberName'] ?? '').toString().trim();
    final cleanName = (rawName.isNotEmpty && !rawName.startsWith('chamber-'))
        ? rawName
        : (storedName != null && storedName.isNotEmpty && !storedName.startsWith('chamber-'))
            ? storedName
            : 'Chamber';

    // Parse visiting hours
    String? hoursDisplay;
    Map<String, dynamic>? hoursStructured;
    final vh = d['visitingHours'] ?? d['hours'];
    if (vh is Map) {
      hoursStructured = Map<String, dynamic>.from(vh);
      hoursDisplay = (hoursStructured['display'] ?? d['visitingHoursDisplay'])?.toString();
    } else if (vh is String && vh.trim().isNotEmpty) {
      hoursDisplay = vh.trim();
    } else if (d['visitingHoursDisplay'] is String && (d['visitingHoursDisplay'] as String).isNotEmpty) {
      hoursDisplay = (d['visitingHoursDisplay'] as String).trim();
    }

    // Parse doctorIds and members
    final rawDoctorIds = d['doctorIds'];
    List<String> doctorIds = [];
    if (rawDoctorIds is List) {
      doctorIds = rawDoctorIds.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    final ownerDoctorId = (d['ownerDoctorId'] ?? d['doctorId'] ?? defaultDoctorId)?.toString();
    if (ownerDoctorId != null && ownerDoctorId.isNotEmpty && !doctorIds.contains(ownerDoctorId)) {
      doctorIds.insert(0, ownerDoctorId);
    }

    final rawMembers = d['members'];
    Map<String, String> members = {};
    if (rawMembers is Map) {
      members = rawMembers.map((k, v) => MapEntry(k.toString(), v.toString()));
    } else {
      for (final docId in doctorIds) {
        members[docId] = docId == ownerDoctorId ? 'owner' : 'visiting';
      }
    }

    // Aliases
    final rawAliases = d['aliases'];
    List<String> aliases = [];
    if (rawAliases is List) {
      aliases = rawAliases.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (!aliases.contains(id)) aliases.add(id);
    if (cleanName.isNotEmpty && !aliases.contains(cleanName)) aliases.add(cleanName);

    final isAccessible = d['isAccessible'] == true ||
        d['wheelchairEntrance'] == true ||
        (d['accessibility'] is Map && (d['accessibility'] as Map)['wheelchairEntrance'] == true);

    final fee = (d['fee'] as num?)?.toDouble() ?? 500.0;
    final slotMin = ((d['slotMinutes'] as num?)?.toInt() ?? 10).clamp(5, 15);

    return ChamberRecord(
      id: id,
      name: cleanName,
      address: (d['address'] ?? d['location'] ?? '').toString(),
      area: (d['area'] ?? '').toString(),
      visitingHours: hoursDisplay,
      visitingHoursStructured: hoursStructured,
      slotMinutes: slotMin,
      ownerDoctorId: ownerDoctorId,
      doctorIds: doctorIds,
      members: members,
      isAccessible: isAccessible,
      fee: fee,
      hasOperator: d['hasOperator'] == true || d['operatorUid'] != null,
      operatorUid: d['operatorUid']?.toString(),
      aliases: aliases,
      raw: d,
    );
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
