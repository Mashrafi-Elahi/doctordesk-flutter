import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/doctor.dart';
import 'doctor_search_index.dart';
import 'geofire_utils.dart';

/// Cloud Firestore service providing complete data access for DoctorDesk.
/// Matches the method signatures of [ApiService] for transparent backend switching.
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache for cursor pagination: key -> Map<pageNumber, DocumentSnapshot>
  static final Map<String, Map<int, DocumentSnapshot>> _pageCursors = {};

  // =========================================================================
  // DOCTORS DIRECTORY & SEARCH
  // =========================================================================

  static List<Map<String, dynamic>>? _cachedBundledMaps;

  /// Loads and caches raw maps for the 6,000+ bundled APK doctors with precomputed searchText
  static Future<List<Map<String, dynamic>>> _getIndexedBundledMaps() async {
    if (_cachedBundledMaps != null && _cachedBundledMaps!.isNotEmpty) {
      return _cachedBundledMaps!;
    }
    final docs = await getBundledDoctors();
    _cachedBundledMaps = docs.map((d) {
      final m = d.toJson();
      m['_id'] = d.id;
      m['searchText'] = DoctorSearchIndex.fieldsFor(m)['searchText'];
      return m;
    }).toList();
    return _cachedBundledMaps!;
  }

  static bool _matchesSpecialtyFilter(List<String> docSpecs, String filter) {
    final normFilter = DoctorSearchIndex.normalize(filter);
    if (normFilter.isEmpty || normFilter == 'all') return true;
    final filterAbbrevs = <String>{
      normFilter,
      ...(DoctorSearchIndex.specialtyAbbreviations[normFilter] ?? const [])
          .map(DoctorSearchIndex.normalize),
    };
    for (final ft in DoctorSearchIndex.tokens(normFilter)) {
      final ab = DoctorSearchIndex.specialtyAbbreviations[ft];
      if (ab != null) {
        filterAbbrevs.addAll(ab.map(DoctorSearchIndex.normalize));
      }
    }
    for (final s in docSpecs) {
      final normS = DoctorSearchIndex.normalize(s);
      if (normS == normFilter ||
          normS.contains(normFilter) ||
          normFilter.contains(normS)) {
        return true;
      }
      final sToks = DoctorSearchIndex.tokens(normS);
      if (sToks.any(filterAbbrevs.contains) || filterAbbrevs.contains(normS)) {
        return true;
      }
    }
    return false;
  }

  /// Fetches doctors with pagination, optional specialty filter, and indexed
  /// multilingual token search across names, specialties, symptoms, chambers, and degrees.
  /// Uses the 6,000+ bundled APK directory directly to avoid hitting Firestore 50k read limits.
  static Future<Map<String, dynamic>> fetchDoctors({
    int page = 1,
    int limit = 20,
    String? search,
    String? speciality,
  }) async {
    final allMaps = await _getIndexedBundledMaps();
    List<Map<String, dynamic>> records = List<Map<String, dynamic>>.from(allMaps);

    if (speciality != null &&
        speciality.trim().isNotEmpty &&
        speciality != 'All') {
      records = records.where((data) {
        final specs = (data['specialities'] as List? ?? const [])
            .map((e) => e.toString())
            .toList();
        return _matchesSpecialtyFilter(specs, speciality);
      }).toList();
    }

    final hasSearch = search?.trim().isNotEmpty == true;
    if (hasSearch) {
      records = DoctorSearchIndex.rank(records, search!.trim());
    }

    final totalCount = records.length;
    final totalPages = (totalCount / limit).ceil().clamp(1, 9999);
    final startIndex = (page - 1) * limit;
    final pagedRecords = startIndex < totalCount
        ? records.sublist(startIndex, (startIndex + limit).clamp(0, totalCount))
        : <Map<String, dynamic>>[];

    final doctors = pagedRecords.map(Doctor.fromJson).toList();

    return {
      'doctors': doctors,
      'total': totalCount,
      'totalPages': totalPages,
      'isOffline': false,
    };
  }

  /// Fetches a doctor by document ID from bundled APK directory first, then Firestore if needed.
  static Future<Doctor> fetchDoctorById(String id) async {
    try {
      final bundled = await getBundledDoctors();
      final normalizedId = id.replaceFirst('doctor_', 'doc_');
      for (final doc in bundled) {
        if (doc.id == id ||
            doc.id == normalizedId ||
            doc.id == 'doc_$id' ||
            doc.id == 'doctor_$id') {
          return doc;
        }
      }
    } catch (_) {}

    try {
      final docRef = _db.collection('doctors').doc(id);
      var snapshot = await docRef.get();

      if (!snapshot.exists && !id.startsWith('doctor_')) {
        snapshot = await _db.collection('doctors').doc('doctor_$id').get();
      }

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        data['_id'] = snapshot.id;
        return Doctor.fromJson(data);
      }
    } catch (e) {
      debugPrint('Firestore fetchDoctorById error: $e');
    }

    throw Exception('Failed to load doctor profile');
  }

  static Future<String> addDoctor({
    required String name,
    required List<String> specialities,
    String? designation,
    double experienceYears = 5.0,
    List<String> education = const ['MBBS'],
    String? bmdcRegNumber,
    List<Map<String, dynamic>> chambers = const [],
    String? phone,
    String? applicantUid,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Doctor name is required.');
    }
    final normalizedSpecialities = specialities
        .map((speciality) => speciality.trim())
        .where((speciality) => speciality.isNotEmpty)
        .toList();
    if (normalizedSpecialities.isEmpty) {
      throw ArgumentError('At least one speciality is required.');
    }
    final normalizedBmdc = bmdcRegNumber?.trim() ?? '';
    final duplicateQuery = normalizedBmdc.isNotEmpty
        ? _db
            .collection('doctors')
            .where('bmdcRegNumber', isEqualTo: normalizedBmdc)
            .limit(1)
        : _db
            .collection('doctors')
            .where('name_lower', isEqualTo: normalizedName.toLowerCase())
            .limit(1);
    final duplicate = await duplicateQuery.get();

    DocumentReference<Map<String, dynamic>> docRef;
    if (applicantUid != null && applicantUid.trim().isNotEmpty) {
      final existingClaim = await _db
          .collection('doctors')
          .where('claimedByUid', isEqualTo: applicantUid.trim())
          .limit(1)
          .get();
      docRef = existingClaim.docs.isNotEmpty
          ? existingClaim.docs.first.reference
          : _db.collection('doctors').doc('doctor_${applicantUid.trim()}');
    } else {
      docRef = _db.collection('doctors').doc();
    }

    if (duplicate.docs.isNotEmpty && duplicate.docs.first.id != docRef.id) {
      throw StateError(
          'A doctor with the same name or BMDC number already exists.');
    }

    final isClaimed = applicantUid != null && applicantUid.trim().isNotEmpty;
    final data = <String, dynamic>{
      'name': normalizedName.startsWith('Dr.')
          ? normalizedName
          : 'Dr. $normalizedName',
      'name_lower': normalizedName.toLowerCase(),
      'specialities': normalizedSpecialities,
      'designation': designation ?? 'Consultant',
      'experienceYears': experienceYears,
      'education': education,
      'bmdcRegNumber': normalizedBmdc,
      'isBmdcVerified': isClaimed && normalizedBmdc.isNotEmpty,
      'isClaimed': isClaimed,
      if (isClaimed) 'claimedByUid': applicantUid.trim(),
      'ratingAverage': 0.0,
      'ratingCount': 0,
      'reviewCount': 0,
      'phone': phone ?? '',
      'chambers': chambers.isNotEmpty
          ? chambers
          : [
              {
                'hospitalName': 'Bup Medical',
                'area': 'Mirpur',
                'location': 'Dhaka',
              }
            ],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      ...DoctorSearchIndex.fieldsFor({
        'name': normalizedName,
        'designation': designation ?? 'Consultant',
        'specialities': normalizedSpecialities,
        'education': education,
        'chambers': chambers,
      }),
    };

    if (isClaimed) {
      final userRef = _db.collection('users').doc(applicantUid.trim());
      final userSnap = await userRef.get();
      final userData = userSnap.data() ?? {};
      final appData = Map<String, dynamic>.from(
          (userData['doctorApplication'] as Map?) ?? const {});

      final batch = _db.batch();
      batch.set(docRef, data, SetOptions(merge: true));
      batch.set(
        userRef,
        {
          'roles': {
            ...Map<String, dynamic>.from(
                (userData['roles'] as Map?) ?? const {}),
            'isDoctor': true,
          },
          'chamberCount': chambers.isNotEmpty ? chambers.length : 1,
          'doctorProfileId': docRef.id,
          'isBmdcVerified': normalizedBmdc.isNotEmpty,
          if (normalizedBmdc.isNotEmpty) 'bmdcRegNumber': normalizedBmdc,
          if (phone != null && phone.trim().isNotEmpty)
            'phone': phone.trim(),
          'doctorApplication': {
            ...appData,
            'status': 'approved',
            'name': normalizedName,
            if (normalizedBmdc.isNotEmpty) 'bmdcNumber': normalizedBmdc,
            if (phone != null && phone.trim().isNotEmpty)
              'phone': phone.trim(),
            'reviewedAt': FieldValue.serverTimestamp(),
            'reviewedByUid': _auth.currentUser?.uid,
          },
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      return docRef.id;
    }

    // If no applicantUid was given, check if a user with this phone exists to link
    if (phone != null && phone.trim().isNotEmpty) {
      try {
        final matchSnap = await _db
            .collection('users')
            .where('phone', isEqualTo: phone.trim())
            .limit(1)
            .get();
        if (matchSnap.docs.isNotEmpty) {
          final matchedDoc = matchSnap.docs.first;
          final matchedUid = matchedDoc.id;
          final matchedUser = matchedDoc.data();
          data['isClaimed'] = true;
          data['claimedByUid'] = matchedUid;
          data['isBmdcVerified'] = normalizedBmdc.isNotEmpty;

          final batch = _db.batch();
          batch.set(docRef, data);
          batch.set(
            matchedDoc.reference,
            {
              'roles': {
                ...Map<String, dynamic>.from(
                    (matchedUser['roles'] as Map?) ?? const {}),
                'isDoctor': true,
              },
              'chamberCount': chambers.isNotEmpty ? chambers.length : 1,
              'doctorProfileId': docRef.id,
              'isBmdcVerified': normalizedBmdc.isNotEmpty,
              if (normalizedBmdc.isNotEmpty) 'bmdcRegNumber': normalizedBmdc,
              'doctorApplication': {
                ...Map<String, dynamic>.from(
                    (matchedUser['doctorApplication'] as Map?) ?? const {}),
                'status': 'approved',
                'name': normalizedName,
                if (normalizedBmdc.isNotEmpty) 'bmdcNumber': normalizedBmdc,
                'reviewedAt': FieldValue.serverTimestamp(),
                'reviewedByUid': _auth.currentUser?.uid,
              },
            },
            SetOptions(merge: true),
          );
          await batch.commit();
          return docRef.id;
        }
      } catch (_) {}
    }

    await docRef.set(data);
    return docRef.id;
  }

  static Future<void> deleteDoctor(String doctorId) async {
    await _db.collection('doctors').doc(doctorId).delete();
  }

  static List<Map<String, dynamic>>? _cachedSpecialitiesList;

  /// Computes specialities list and doctor counts directly from the 6,000+ bundled APK dataset (0 Firestore reads).
  static Future<List<Map<String, dynamic>>> fetchSpecialities() async {
    if (_cachedSpecialitiesList != null && _cachedSpecialitiesList!.isNotEmpty) {
      return _cachedSpecialitiesList!;
    }
    try {
      final docs = await getBundledDoctors();
      final Map<String, int> counts = {};
      for (final d in docs) {
        for (final s in d.specialities) {
          final clean = s.trim();
          if (clean.isNotEmpty) {
            counts[clean] = (counts[clean] ?? 0) + 1;
          }
        }
      }
      final list = counts.entries
          .map((e) => <String, dynamic>{'speciality': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      _cachedSpecialitiesList = list;
      return list;
    } catch (e) {
      debugPrint('Error computing bundled specialities: $e');
    }

    return const [
      {'speciality': 'GYNECOLOGIST & OBSTETRICIAN', 'count': 704},
      {'speciality': 'MEDICINE SPECIALIST', 'count': 579},
      {'speciality': 'CARDIOLOGIST', 'count': 380},
      {'speciality': 'PEDIATRICIAN', 'count': 339},
      {'speciality': 'GENERAL SURGEON', 'count': 284},
      {'speciality': 'DERMATOLOGIST', 'count': 283},
      {'speciality': 'OTOLARYNGOLOGISTS (ENT)', 'count': 270},
      {'speciality': 'ORTHOPEDIC SURGEON', 'count': 235},
      {'speciality': 'OPHTHALMOLOGIST', 'count': 231},
      {'speciality': 'NEUROLOGIST', 'count': 117},
      {'speciality': 'DENTIST', 'count': 120},
      {'speciality': 'ENDOCRINOLOGIST', 'count': 129},
    ];
  }

  /// Nearby doctors search across all 6,000+ bundled APK doctors using exact Haversine distance (0 Firestore reads).
  static Future<List<Doctor>> fetchNearbyDoctors({
    required double lat,
    required double lng,
    int radiusKm = 10,
    String? speciality,
    int page = 1,
    int limit = 20,
  }) async {
    final allMaps = await _getIndexedBundledMaps();
    final List<Doctor> matched = [];

    for (final data in allMaps) {
      final specs = (data['specialities'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      if (speciality != null &&
          speciality.isNotEmpty &&
          speciality != 'All' &&
          !_matchesSpecialtyFilter(specs, speciality)) {
        continue;
      }

      final chambers = (data['chambers'] as List? ?? const [])
          .whereType<Map>()
          .map((c) => Map<String, dynamic>.from(c))
          .toList();

      double? bestDist;
      Map<String, dynamic>? bestChamber;
      for (final ch in chambers) {
        final chLat = (ch['lat'] as num?)?.toDouble();
        final chLng = (ch['lng'] as num?)?.toDouble();
        if (chLat != null && chLng != null) {
          final dist = GeofireUtils.distanceBetweenKm([lat, lng], [chLat, chLng]);
          if (dist <= radiusKm && (bestDist == null || dist < bestDist)) {
            bestDist = dist;
            bestChamber = ch;
          }
        }
      }

      if (bestDist != null && bestChamber != null) {
        final copy = Map<String, dynamic>.from(data);
        copy['distance'] = bestDist;
        copy['chamber'] = bestChamber;
        matched.add(Doctor.fromJson(copy));
      }
    }

    matched.sort((a, b) => (a.distance ?? 999.0).compareTo(b.distance ?? 999.0));

    final startIndex = (page - 1) * limit;
    if (startIndex >= matched.length) return [];
    final endIndex = (startIndex + limit > matched.length)
        ? matched.length
        : startIndex + limit;

    return matched.sublist(startIndex, endIndex);
  }

  // =========================================================================
  // GEOCODING (Direct Nominatim client with BD filter)
  // =========================================================================

  /// Direct OpenStreetMap Nominatim geocoding with 1-req/sec safety header
  static Future<List<Map<String, dynamic>>> fetchGeocodeSuggestions(
      String query) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=2&countrycodes=bd',
      );
      final response = await http.get(uri, headers: {
        'User-Agent':
            'DoctorDesk-Flutter/1.0 (student project, contact: dev@doctordesk.bd)',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((item) {
          return {
            'displayName': item['display_name'] ?? '',
            'lat': double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0,
            'lng': double.tryParse(item['lon']?.toString() ?? '0') ?? 0.0,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Direct Nominatim geocode error: $e');
    }
    return [];
  }

  // =========================================================================
  // JOURNAL & MOOD
  // =========================================================================

  static Future<Map<String, dynamic>?> fetchTodayFeeling() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;

      final startOfDay = DateTime.now();
      final startTimestamp =
          DateTime(startOfDay.year, startOfDay.month, startOfDay.day);

      final snapshot = await _db
          .collection('journal')
          .where('userId', isEqualTo: uid)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startTimestamp))
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
    } catch (e) {
      debugPrint('Firestore fetchTodayFeeling error: $e');
    }
    return null;
  }

  static Future<bool> logFeeling({
    required String feeling,
    String? note,
    String? gratitudeText,
  }) async {
    try {
      final uid = _auth.currentUser?.uid ?? 'guest';
      await _db.collection('journal').add({
        'userId': uid,
        'feeling': feeling.toLowerCase(),
        'note': note ?? '',
        'gratitudeText': gratitudeText ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Firestore logFeeling error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchJournalEntries() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return [];

      final snapshot = await _db
          .collection('journal')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();

      return snapshot.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        final ts = data['createdAt'];
        if (ts is Timestamp) {
          data['createdAt'] = ts.toDate().toIso8601String();
        }
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Firestore fetchJournalEntries error: $e');
      return [];
    }
  }

  // =========================================================================
  // REVIEWS & BMDC CLAIMS
  // =========================================================================

  static Future<List<Map<String, dynamic>>> fetchReviews(
      String doctorId) async {
    try {
      final snapshot = await _db
          .collection('reviews')
          .where('doctorId', isEqualTo: doctorId)
          .get();

      final list = snapshot.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        final ts = data['createdAt'];
        if (ts is Timestamp) {
          data['createdAt'] = ts.toDate().toIso8601String();
        }
        return data;
      }).toList();

      list.sort((a, b) {
        final aDate = a['createdAt']?.toString() ?? '';
        final bDate = b['createdAt']?.toString() ?? '';
        return bDate.compareTo(aDate);
      });

      return list;
    } catch (e) {
      debugPrint('Firestore fetchReviews error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> submitReview(
    String doctorId, {
    required String patientUid,
    required int rating,
    String comment = '',
    String? proofImageUrl,
  }) async {
    final reviewDocId = '${doctorId}_$patientUid';
    final reviewData = <String, dynamic>{
      'doctorId': doctorId,
      'userId': patientUid,
      'patientUid': patientUid,
      'rating': rating,
      'comment': comment,
      'proofImageUrl': proofImageUrl ?? '',
      'isProofVerified': proofImageUrl != null && proofImageUrl.isNotEmpty,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db
        .collection('reviews')
        .doc(reviewDocId)
        .set(reviewData, SetOptions(merge: true));

    // Update doctor's aggregate rating in Firestore
    try {
      final allReviews = await fetchReviews(doctorId);
      if (allReviews.isNotEmpty) {
        double sum = 0;
        int count = 0;
        for (final r in allReviews) {
          final rScore = (r['rating'] as num?)?.toDouble() ?? 0.0;
          final hasProof = r['proofImageUrl'] != null &&
              r['proofImageUrl'].toString().isNotEmpty;
          final weight = hasProof ? 2 : 1;
          sum += (rScore * weight);
          count += weight;
        }
        final avg = count > 0 ? (sum / count) : 0.0;
        await _db.collection('doctors').doc(doctorId).set({
          'ratingAverage': double.parse(avg.toStringAsFixed(1)),
          'ratingCount': allReviews.length,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error updating doctor aggregate rating: $e');
    }

    return {
      'doctorId': doctorId,
      'rating': rating,
      'comment': comment,
    };
  }

  static Future<bool> checkCanReview(String doctorId, String patientUid,
      {Map<String, dynamic>? doctorData}) async {
    if (patientUid.isEmpty) return false;
    final claimedBy = doctorData?['claimedByUid'] ?? doctorData?['userId'];
    if (claimedBy != null && claimedBy == patientUid) {
      return false; // Doctor cannot review their own profile
    }
    return true;
  }

  static Future<Map<String, dynamic>> claimDoctor(
    String doctorId, {
    required String bmdcRegNumber,
    required String claimedByUid,
    String? certificateImageUrl,
  }) async {
    final doctorRef = _db.collection('doctors').doc(doctorId);
    await doctorRef.update({
      'bmdcRegNumber': bmdcRegNumber,
      'claimedByUid': claimedByUid,
      'certificateImageUrl': certificateImageUrl,
      'isClaimed': true,
      // isBmdcVerified stays false until manual admin review
    });

    return {
      'isClaimed': true,
      'isBmdcVerified': false,
    };
  }

  // =========================================================================
  // USER PROFILES & ROLES SYNC
  // =========================================================================

  static Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    try {
      final docSnap = await _db.collection('users').doc(uid).get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        data['uid'] = docSnap.id;
        final roles = Map<String, dynamic>.from(
            (data['roles'] as Map<String, dynamic>?) ?? {});

        // Check if user is an admin document
        final adminDoc = await _db.collection('admins').doc(uid).get();
        // A role flag by itself is not authority. Admin is granted only by
        // the protected admins collection.
        roles['isAdmin'] = adminDoc.exists;

        // A doctor role is tied to a claimed doctor profile. This prevents a
        // stale role flag or a normal applicant from receiving appointments.
        final doctorProfileId = data['doctorProfileId']?.toString();
        if (roles['isDoctor'] == true &&
            doctorProfileId != null &&
            doctorProfileId.isNotEmpty) {
          final doctorDoc =
              await _db.collection('doctors').doc(doctorProfileId).get();
          final doctorData = doctorDoc.data();
          if (!doctorDoc.exists ||
              doctorData?['isClaimed'] != true ||
              doctorData?['claimedByUid'] != uid) {
            roles['isDoctor'] = false;
            data['chamberCount'] = 0;
          }
        } else {
          roles['isDoctor'] = false;
          data['chamberCount'] = 0;
        }

        if (roles['isOperator'] == true &&
            ((data['operatorAssignments'] as List?)?.isNotEmpty != true)) {
          roles['isOperator'] = false;
        }
        data['roles'] = roles;

        return data;
      }
    } catch (e) {
      debugPrint('Firestore fetchUserProfile error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> syncUser({
    required String uid,
    String? email,
    String? name,
    String? phone,
    String? role,
    bool isDoctor = false,
  }) async {
    try {
      final userRef = _db.collection('users').doc(uid);
      final existing = await userRef.get();

      if (!existing.exists) {
        final userData = <String, dynamic>{
          'uid': uid,
          'email': email ?? '',
          'name': name ?? '',
          'phone': phone ?? '',
          'roles': {
            'isDoctor': false,
            'isOperator': false,
            'isAdmin': false,
          },
          'chamberCount': 0,
          'doctorProfileId': null,
          'operatorAssignments': [],
          'createdAt': FieldValue.serverTimestamp(),
        };

        // Normal signups applying for doctor get pending status, never client-granted role
        if (isDoctor) {
          userData['doctorApplication'] = {
            'status': 'pending',
            'appliedAt': FieldValue.serverTimestamp(),
            'phone': phone ?? '',
            'name': name ?? '',
            'email': email ?? '',
          };
        }

        await userRef.set(userData);
        return userData;
      } else {
        final updates = <String, dynamic>{};
        if (name != null &&
            name.isNotEmpty &&
            (existing.data()?['name'] == null ||
                existing.data()?['name'] == '')) {
          updates['name'] = name;
        }
        if (email != null &&
            email.isNotEmpty &&
            (existing.data()?['email'] == null ||
                existing.data()?['email'] == '')) {
          updates['email'] = email;
        }
        if (phone != null &&
            phone.isNotEmpty &&
            (existing.data()?['phone'] == null ||
                existing.data()?['phone'] == '')) {
          updates['phone'] = phone;
        }
        if (isDoctor) {
          final isAlreadyDoctor =
              existing.data()?['roles']?['isDoctor'] == true;
          if (!isAlreadyDoctor) {
            updates['doctorApplication'] = {
              'status': 'pending',
              'appliedAt': FieldValue.serverTimestamp(),
              'phone': phone ?? existing.data()?['phone'] ?? '',
              'name': name ?? existing.data()?['name'] ?? '',
              'email': email ?? existing.data()?['email'] ?? '',
            };
          }
        }
        if (updates.isNotEmpty) {
          await userRef.update(updates);
        }
        final merged = Map<String, dynamic>.from(existing.data() ?? {});
        merged.addAll(updates);
        return merged;
      }
    } catch (e) {
      debugPrint('Firestore syncUser error: $e');
      return null;
    }
  }

  /// Fetches pending doctor applications for admin review from the database
  static Future<List<Map<String, dynamic>>> fetchDoctorApplications() async {
    try {
      final snap = await _db
          .collection('users')
          .where('doctorApplication.status', whereIn: ['pending', 'under_appeal'])
          .get();
      return snap.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint('Firestore fetchDoctorApplications error: $e');
      return [];
    }
  }

  /// Allocates or revokes the Doctor role in the database for a user (Admin only).
  /// If NID and BMDC are provided, verified badge/status can be allocated.
  static Future<void> setDoctorRole({
    required String uid,
    required bool isDoctor,
    bool isBmdcVerified = false,
    String? doctorProfileId,
    String? nid,
    String? bmdcNumber,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final updates = <String, dynamic>{
      'roles.isDoctor': isDoctor,
      'chamberCount': isDoctor ? 1 : 0,
      'doctorApplication.status': isDoctor ? 'approved' : 'revoked',
      'doctorApplication.reviewedAt': FieldValue.serverTimestamp(),
      'doctorApplication.reviewedByUid': _auth.currentUser?.uid,
      'isBmdcVerified': isBmdcVerified,
    };
    if (nid != null && nid.isNotEmpty) updates['nid'] = nid;
    if (bmdcNumber != null && bmdcNumber.isNotEmpty) {
      updates['bmdcRegNumber'] = bmdcNumber;
    }
    if (doctorProfileId != null) {
      updates['doctorProfileId'] = doctorProfileId;
    }
    await userRef.update(updates);
  }

  /// Approves a pending application by creating (or restoring) exactly one
  /// claimed directory profile and linking it to the applicant's user record.
  /// This operation is admin-authorized by Firestore rules; client UI alone
  /// can never grant the doctor role.
  static Future<String> approveDoctorApplication({
    required String uid,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final userSnapshot = await userRef.get();
    if (!userSnapshot.exists) {
      throw StateError('The applicant user record no longer exists.');
    }
    final user = userSnapshot.data()!;
    final application = Map<String, dynamic>.from(
      (user['doctorApplication'] as Map?) ?? const {},
    );
    final status = application['status']?.toString();
    if (status != 'pending' &&
        status != 'under_appeal' &&
        status != 'approved') {
      throw StateError('This user does not have a pending doctor application.');
    }

    final applicantName =
        (application['name']?.toString().trim().isNotEmpty == true
                ? application['name']
                : user['name'])
            ?.toString()
            .trim();
    if (applicantName == null || applicantName.isEmpty) {
      throw StateError('The application is missing the doctor name.');
    }
    final speciality = application['speciality']?.toString().trim();
    final bmdcNumber = application['bmdcNumber']?.toString().trim() ?? '';
    final existingClaim = await _db
        .collection('doctors')
        .where('claimedByUid', isEqualTo: uid)
        .limit(1)
        .get();
    final doctorRef = existingClaim.docs.isNotEmpty
        ? existingClaim.docs.first.reference
        : _db.collection('doctors').doc('doctor_$uid');
    final displayName =
        applicantName.startsWith('Dr.') ? applicantName : 'Dr. $applicantName';

    final batch = _db.batch();
    batch.set(
        doctorRef,
        {
          'name': displayName,
          'name_lower': displayName.toLowerCase(),
          'specialities': [
            speciality == null || speciality.isEmpty
                ? 'General Medicine'
                : speciality,
          ],
          'designation': 'Consultant',
          'education': const <String>[],
          'bmdcRegNumber': bmdcNumber,
          'isClaimed': true,
          'claimedByUid': uid,
          // Approval records an application review, not automatic BMDC verification.
          'isBmdcVerified': false,
          'phone': application['phone']?.toString() ??
              user['phone']?.toString() ??
              '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          ...DoctorSearchIndex.fieldsFor({
            'name': displayName,
            'designation': 'Consultant',
            'specialities': [
              speciality == null || speciality.isEmpty
                  ? 'General Medicine'
                  : speciality,
            ],
            'education': const <String>[],
          }),
        },
        SetOptions(merge: true));
    batch.set(
        userRef,
        {
          'roles': {
            ...Map<String, dynamic>.from((user['roles'] as Map?) ?? const {}),
            'isDoctor': true,
          },
          'chamberCount': 0,
          'doctorProfileId': doctorRef.id,
          'doctorApplication': {
            ...application,
            'status': 'approved',
            'reviewedAt': FieldValue.serverTimestamp(),
            'reviewedByUid': _auth.currentUser?.uid,
          },
          'isBmdcVerified': false,
        },
        SetOptions(merge: true));
    await batch.commit();
    return doctorRef.id;
  }

  /// Submits an application for the doctor role to the database with optional NID and BMDC
  static Future<void> applyForDoctorRole({
    required String uid,
    required String phone,
    String? name,
    String? nid,
    String? bmdcNumber,
    String? speciality,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final hasDocs = (nid != null && nid.isNotEmpty) ||
        (bmdcNumber != null && bmdcNumber.isNotEmpty);
    await userRef.set({
      'phone': phone,
      'doctorApplication': {
        'status': 'pending',
        'appliedAt': FieldValue.serverTimestamp(),
        'phone': phone,
        'name': name ?? '',
        'nid': nid ?? '',
        'bmdcNumber': bmdcNumber ?? '',
        'speciality': speciality ?? '',
        'hasProvidedVerificationDocs': hasDocs,
      },
    }, SetOptions(merge: true));
  }

  /// Sets or revokes moderator role. Only Admins can execute this.
  static Future<void> setModeratorRole({
    required String uid,
    required bool isModerator,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    await userRef.update({
      'roles.isModerator': isModerator,
      'moderatorUpdatedBy': _auth.currentUser?.uid,
      'moderatorUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Fetches users with moderator role
  static Future<List<Map<String, dynamic>>> fetchModerators() async {
    try {
      final snap = await _db
          .collection('users')
          .where('roles.isModerator', isEqualTo: true)
          .get();
      return snap.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint('Firestore fetchModerators error: $e');
      return [];
    }
  }

  // =========================================================================
  // REAL-TIME FEED & VIDEO POSTS
  // =========================================================================

  /// Stream of feed posts ordered by newest first
  static Stream<QuerySnapshot<Map<String, dynamic>>> feedPostsStream(
      {String? typeFilter}) {
    Query<Map<String, dynamic>> query =
        _db.collection('posts').orderBy('timestamp', descending: true);
    if (typeFilter != null && typeFilter != 'All') {
      query = query.where('type', isEqualTo: typeFilter);
    }
    return query.snapshots();
  }

  /// Creates a post in the feed.
  /// Doctors, Admins, and Moderators can post videos and tips.
  /// Patients and Operators can ask questions.
  static Future<String> createFeedPost({
    required String type, // 'video' | 'tip' | 'question'
    required String title,
    String? content,
    String? youtubeUrl,
    String? authorName,
    String? authorRole,
    bool isBmdcVerified = false,
  }) async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? 'anonymous_user';
    final name = authorName ?? user?.displayName ?? 'Community Member';
    final role = authorRole ?? 'patient';

    final docRef = await _db.collection('posts').add({
      'type': type,
      'title': title,
      'content': content ?? '',
      'youtubeUrl': youtubeUrl ?? '',
      'userId': uid,
      'authorName': name,
      'authorRole': role,
      'isBmdcVerified': isBmdcVerified,
      'timestamp': FieldValue.serverTimestamp(),
      'answer': null,
      'likesCount': 0,
      'commentsCount': 0,
    });

    return docRef.id;
  }

  /// Answers a community question or FAQ.
  /// Allowed for Doctors, Admins, and Moderators.
  static Future<void> answerQuestion({
    required String postId,
    required String answerContent,
    String? doctorName,
    String? doctorRole,
  }) async {
    final name =
        doctorName ?? _auth.currentUser?.displayName ?? 'Dr. Specialist';
    final role = doctorRole ?? 'doctor';

    await _db.collection('posts').doc(postId).update({
      'answer': {
        'content': answerContent,
        'authorName': name,
        'authorRole': role,
        'authorUid': _auth.currentUser?.uid,
        'answeredAt': DateTime.now().toIso8601String(),
      },
    });
  }

  /// Adds a comment to a feed post.
  /// Allowed for all roles (patients, operators, doctors, admins).
  static Future<void> addPostComment({
    required String postId,
    required String comment,
    String? authorName,
    String? authorRole,
  }) async {
    final uid = _auth.currentUser?.uid ?? 'guest';
    final name =
        authorName ?? _auth.currentUser?.displayName ?? 'Community Member';
    final role = authorRole ?? 'patient';

    final postRef = _db.collection('posts').doc(postId);
    await postRef.collection('comments').add({
      'postId': postId,
      'userId': uid,
      'authorName': name,
      'authorRole': role,
      'comment': comment,
      'timestamp': FieldValue.serverTimestamp(),
    });

    try {
      await postRef.update({
        'commentsCount': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  /// Stream of comments for a specific post
  static Stream<QuerySnapshot<Map<String, dynamic>>> postCommentsStream(
      String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  /// Deletes a post (Author, Moderator, or Admin)
  static Future<void> deleteFeedPost(String postId) async {
    await _db.collection('posts').doc(postId).delete();
  }

  // =========================================================================
  // SPECIALTY FEEDBACK (Analytics / accuracy loop)
  // =========================================================================

  static Future<void> submitSpecialtyFeedback({
    required String inputText,
    required String matchedSpecialty,
    required String source,
    required bool liked,
    String language = 'unknown',
  }) async {
    try {
      await _db.collection('specialty_feedback').add({
        'inputText': inputText,
        'matchedSpecialty': matchedSpecialty,
        'source': source,
        'liked': liked,
        'language': language,
        'userUid': _auth.currentUser?.uid,
      });
    } catch (_) {}
  }

  // =========================================================================
  // APPOINTMENTS & QUEUE MANAGEMENT
  // =========================================================================

  static Future<List<Map<String, dynamic>>> fetchTodayQueue(
      String chamberId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return [];
      final profile = await fetchUserProfile(uid);
      final roles = (profile?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
      final doctorProfileId = profile?['doctorProfileId']?.toString();
      final assignments = (profile?['operatorAssignments'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const <String>[];

      Query<Map<String, dynamic>> query = _db.collection('appointments');
      if (roles['isDoctor'] == true &&
          doctorProfileId != null &&
          doctorProfileId.isNotEmpty) {
        query = query.where('doctorId', isEqualTo: doctorProfileId);
      } else if (roles['isOperator'] == true &&
          assignments.contains(chamberId)) {
        query = query.where('chamberId', isEqualTo: chamberId);
      } else {
        // A queue must never fall back to every appointment in the database.
        return [];
      }
      query = query.orderBy('queuePosition', descending: false);

      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['_id'] = doc.id;
        data['id'] = doc.id;
        final st = data['scheduledTime'];
        if (st is Timestamp) {
          data['scheduledTime'] = st.toDate().toIso8601String();
        }
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Firestore fetchTodayQueue error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> createAppointment({
    required String patientName,
    required DateTime scheduledTime,
    String? chamberId,
    String? doctorId,
    String? operatorNote,
    String status = 'waiting',
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('You must be signed in to book an appointment.');
    }

    final profile = await fetchUserProfile(uid);
    final roles = (profile?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
    final resolvedDoctorId =
        (doctorId ?? profile?['doctorProfileId']?.toString())?.trim();
    final isDoctorQueueEntry = roles['isDoctor'] == true &&
        resolvedDoctorId != null &&
        resolvedDoctorId.isNotEmpty;
    final assignments = (profile?['operatorAssignments'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const <String>[];
    final resolvedChamberId = (chamberId ?? '').trim();
    final isAssignedOperator = roles['isOperator'] == true &&
        resolvedChamberId.isNotEmpty &&
        assignments.contains(resolvedChamberId);

    if (!isDoctorQueueEntry && !isAssignedOperator) {
      if (doctorId == null || doctorId.trim().isEmpty) {
        throw StateError('This queue is not assigned to your account.');
      }
      final doctor = await _db.collection('doctors').doc(doctorId.trim()).get();
      if (!doctor.exists || doctor.data()?['isClaimed'] != true) {
        throw StateError(
            'Appointments are available only for claimed doctor profiles.');
      }
    }

    // Count only this creator's records. That query is allowed by the same
    // owner rule and avoids leaking the global appointment count.
    final countSnap = await _db
        .collection('appointments')
        .where('userId', isEqualTo: uid)
        .count()
        .get();
    final count = countSnap.count ?? 0;

    final data = <String, dynamic>{
      'patientName': patientName,
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'chamberId':
          resolvedChamberId.isEmpty ? 'demo-chamber' : resolvedChamberId,
      'doctorId': resolvedDoctorId,
      'operatorNote': operatorNote ?? '',
      'status': status,
      'queuePosition': count + 1,
      'userId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _db.collection('appointments').add(data);
    return {
      '_id': docRef.id,
      'id': docRef.id,
      ...data,
      'scheduledTime': scheduledTime.toIso8601String(),
    };
  }

  static Future<void> updateAppointment(
      String id, Map<String, dynamic> updates) async {
    final cleanUpdates = Map<String, dynamic>.from(updates);
    if (cleanUpdates.containsKey('scheduledTime') &&
        cleanUpdates['scheduledTime'] is String) {
      final dt = DateTime.tryParse(cleanUpdates['scheduledTime']);
      if (dt != null) {
        cleanUpdates['scheduledTime'] = Timestamp.fromDate(dt);
      }
    }
    await _db.collection('appointments').doc(id).update(cleanUpdates);
  }

  static Future<void> updateQueueOrder(
      List<Map<String, dynamic>> updates) async {
    final batch = _db.batch();
    for (final u in updates) {
      final id = (u['id'] ?? u['_id']) as String?;
      final pos = u['queuePosition'] as int?;
      if (id != null && pos != null) {
        final ref = _db.collection('appointments').doc(id);
        batch.update(ref, {'queuePosition': pos});
      }
    }
    await batch.commit();
  }

  static Future<void> deleteAppointment(String id) async {
    await _db.collection('appointments').doc(id).delete();
  }

  static Future<void> clearAllAppointments() async {
    final snapshot = await _db.collection('appointments').get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  static List<Doctor>? _cachedBundledDoctors;

  /// Loads the full 6,000+ doctors bundled in local APK assets (0 Firestore reads)
  static Future<List<Doctor>> getBundledDoctors() async {
    if (_cachedBundledDoctors != null && _cachedBundledDoctors!.isNotEmpty) {
      return _cachedBundledDoctors!;
    }
    try {
      final jsonStr = await rootBundle.loadString('assets/data/bundled_doctors.json');
      final List decoded = jsonDecode(jsonStr);
      _cachedBundledDoctors = decoded.map((j) => Doctor.fromJson(j as Map<String, dynamic>)).toList();
      return _cachedBundledDoctors!;
    } catch (e) {
      debugPrint('Error loading bundled doctors: $e');
      final fallbackSeed = _defaultFallbackDoctors();
      _cachedBundledDoctors = fallbackSeed.map((j) => Doctor.fromJson(j)).toList();
      return _cachedBundledDoctors!;
    }
  }

  static List<Map<String, dynamic>> _defaultFallbackDoctors() {
    return [
      {
        '_id': 'doc_fallback_1',
        'name': 'Dr. Nuzhat Saima',
        'designation': 'Specialist Consultant',
        'specialities': ['General Medicine'],
        'education': ['MBBS', 'FCPS'],
        'bmdcRegNumber': 'A-98765',
        'isBmdcVerified': true,
        'ratingAverage': 4.9,
        'ratingCount': 34,
        'chambers': [
          {
            'hospitalName': 'Bup Medical',
            'area': 'Mirpur',
            'location': 'Dhaka',
          }
        ],
      },
      {
        '_id': 'doc_fallback_2',
        'name': 'Dr. Md. Kamrul Islam',
        'designation': 'Professor & Head',
        'specialities': ['General Surgery', 'Urology'],
        'education': ['MBBS', 'FCPS', 'FRCS'],
        'bmdcRegNumber': 'A-12345',
        'isBmdcVerified': true,
        'ratingAverage': 4.8,
        'ratingCount': 120,
        'chambers': [
          {
            'hospitalName': 'Dhaka Medical College Hospital',
            'area': 'Bakshibazar',
            'location': 'Dhaka',
          }
        ],
      },
      {
        '_id': 'doc_fallback_3',
        'name': 'Dr. Farzana Rahman',
        'designation': 'Associate Professor',
        'specialities': ['General Medicine', 'Internal Medicine'],
        'education': ['MBBS', 'FCPS', 'MRCP'],
        'bmdcRegNumber': 'A-23456',
        'isBmdcVerified': true,
        'ratingAverage': 4.9,
        'ratingCount': 88,
        'chambers': [
          {
            'hospitalName': 'Square Hospital',
            'area': 'Panthapath',
            'location': 'Dhaka',
          }
        ],
      },
      {
        '_id': 'doc_fallback_4',
        'name': 'Dr. Alim Chowdhury',
        'designation': 'Senior Consultant',
        'specialities': ['Otolaryngology', 'ENT Specialist'],
        'education': ['MBBS', 'DLO', 'FCPS'],
        'bmdcRegNumber': 'A-34567',
        'isBmdcVerified': true,
        'ratingAverage': 4.7,
        'ratingCount': 52,
        'chambers': [
          {
            'hospitalName': 'Green Life Hospital',
            'area': 'Green Road',
            'location': 'Dhaka',
          }
        ],
      },
      {
        '_id': 'doc_fallback_5',
        'name': 'Dr. Selina Banu',
        'designation': 'Professor & Consultant',
        'specialities': ['Gynecology and Obstetrics'],
        'education': ['MBBS', 'FCPS', 'MS (Gynae)'],
        'bmdcRegNumber': 'A-45678',
        'isBmdcVerified': true,
        'ratingAverage': 4.9,
        'ratingCount': 95,
        'chambers': [
          {
            'hospitalName': 'Popular Diagnostic Centre',
            'area': 'Dhanmondi',
            'location': 'Dhaka',
          }
        ],
      },
      {
        '_id': 'doc_fallback_6',
        'name': 'Dr. Kamal Hossain',
        'designation': 'Associate Professor',
        'specialities': ['Dermatology'],
        'education': ['MBBS', 'DDV', 'FCPS'],
        'bmdcRegNumber': 'A-56789',
        'isBmdcVerified': true,
        'ratingAverage': 4.8,
        'ratingCount': 63,
        'chambers': [
          {
            'hospitalName': 'Labaid Specialized Hospital',
            'area': 'Dhanmondi',
            'location': 'Dhaka',
          }
        ],
      },
      {
        '_id': 'doc_fallback_7',
        'name': 'Dr. Jahangir Kabir',
        'designation': 'Chief Cardiac Surgeon',
        'specialities': ['Cardiology'],
        'education': ['MBBS', 'MS (CTS)', 'FACS'],
        'bmdcRegNumber': 'A-67890',
        'isBmdcVerified': true,
        'ratingAverage': 4.9,
        'ratingCount': 142,
        'chambers': [
          {
            'hospitalName': 'National Heart Foundation',
            'area': 'Mirpur',
            'location': 'Dhaka',
          }
        ],
      },
    ];
  }
}
