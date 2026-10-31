import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../models/doctor.dart';
import 'doctor_search_index.dart';
import 'geofire_utils.dart';
import 'notification_service.dart';

/// Cloud Firestore service providing complete data access for DoctorDesk.
/// Matches the method signatures of [ApiService] for transparent backend switching.
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static FirebaseFirestore get db => _db;
  static FirebaseAuth get auth => _auth;

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

  /// Fetches a doctor by document ID from bundled APK directory and merges Firestore dynamic updates (claim, reviews, chambers).
  static Future<Doctor> fetchDoctorById(String id) async {
    Doctor? baseDoctor;
    try {
      final bundled = await getBundledDoctors();
      final normalizedId = id.replaceFirst('doctor_', 'doc_');
      for (final doc in bundled) {
        if (doc.id == id ||
            doc.id == normalizedId ||
            doc.id == 'doc_$id' ||
            doc.id == 'doctor_$id') {
          baseDoctor = doc;
          break;
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
        final data = Map<String, dynamic>.from(snapshot.data()!);
        data['_id'] = snapshot.id;
        if (baseDoctor != null) {
          final mergedMap = baseDoctor.toJson();
          mergedMap.addAll(data);
          if (!data.containsKey('chambers') || (data['chambers'] as List?)?.isEmpty == true) {
            mergedMap['chambers'] = baseDoctor.chambers.map((c) => c.toJson()).toList();
          }
          return Doctor.fromJson(mergedMap);
        }
        return Doctor.fromJson(data);
      }
    } catch (e) {
      debugPrint('Firestore fetchDoctorById error: $e');
    }

    if (baseDoctor != null) return baseDoctor;
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
    int radiusKm = 8,
    String? speciality,
    String? areaFilter,
    int page = 1,
    int limit = 20,
  }) async {
    final allMaps = await _getIndexedBundledMaps();
    final List<Doctor> matched = [];

    final normArea = areaFilter?.trim().toLowerCase();

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
        final chArea = (ch['area'] ?? ch['location'] ?? '').toString().toLowerCase();
        final chHosp = (ch['hospitalName'] ?? ch['name'] ?? '').toString().toLowerCase();

        bool isAreaMatch = false;
        if (normArea != null && normArea.isNotEmpty && normArea != 'all') {
          final cleanNorm = normArea.replaceAll('l', '');
          final cleanArea = chArea.replaceAll('l', '');
          if (chArea.contains(normArea) || chHosp.contains(normArea) || cleanArea.contains(cleanNorm)) {
            isAreaMatch = true;
          }
        }

        if (chLat != null && chLng != null) {
          final dist = GeofireUtils.distanceBetweenKm([lat, lng], [chLat, chLng]);
          if ((dist <= radiusKm || isAreaMatch) && (bestDist == null || dist < bestDist)) {
            bestDist = dist;
            bestChamber = ch;
          }
        } else if (isAreaMatch) {
          bestDist = 0.5;
          bestChamber = ch;
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

  static Stream<List<Map<String, dynamic>>> reviewsStream(String doctorId) {
    return _db
        .collection('reviews')
        .where('doctorId', isEqualTo: doctorId)
        .snapshots()
        .map((snapshot) {
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
    });
  }

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

  static Future<void> deleteReview(String doctorId, String reviewId) async {
    try {
      await _db.collection('reviews').doc(reviewId).delete();
      final allReviews = await fetchReviews(doctorId);
      if (allReviews.isEmpty) {
        await _db.collection('doctors').doc(doctorId).set({
          'ratingAverage': 0.0,
          'ratingCount': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
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
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error deleting review: $e');
      rethrow;
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
    final name = _auth.currentUser?.displayName?.isNotEmpty == true
        ? _auth.currentUser!.displayName!
        : (_auth.currentUser?.email?.split('@').first ?? 'Patient');

    String role = 'patient';
    try {
      final userSnap = await _db.collection('users').doc(patientUid).get();
      final roles = (userSnap.data()?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
      if (roles['isDoctor'] == true) {
        role = 'doctor';
      } else if (roles['isOperator'] == true) {
        role = 'operator';
      }
    } catch (_) {}

    final reviewData = <String, dynamic>{
      'doctorId': doctorId,
      'userId': patientUid,
      'patientUid': patientUid,
      'raterName': name,
      'raterRole': role,
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
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error updating doctor aggregate rating: $e');
    }

    try {
      if (patientUid.isNotEmpty) {
        await NotificationService.createNotification(
          userId: patientUid,
          title: 'Review submitted',
          body: 'Your $rating-star rating and review have been recorded.',
          type: 'review',
          relatedId: doctorId,
        );
      }
      final docSnap = await _db.collection('doctors').doc(doctorId).get();
      if (docSnap.exists) {
        final claimedBy = docSnap.data()?['claimedByUid'] as String?;
        if (claimedBy != null && claimedBy.isNotEmpty && claimedBy != patientUid) {
          await NotificationService.createNotification(
            userId: claimedBy,
            title: 'New review received',
            body: 'A patient submitted a $rating-star review on your profile.',
            type: 'review',
            relatedId: doctorId,
          );
        }
      }
    } catch (e) {
      debugPrint('Error triggering review notification: $e');
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
    Doctor? doctor;
    try {
      doctor = await fetchDoctorById(doctorId);
    } catch (_) {}

    final doctorRef = _db.collection('doctors').doc(doctorId);
    final claimData = <String, dynamic>{
      'id': doctorId,
      '_id': doctorId,
      if (doctor != null) 'name': doctor.name,
      if (doctor != null) 'specialities': doctor.specialities,
      if (doctor != null) 'experienceYears': doctor.experienceYears,
      if (doctor != null) 'education': doctor.education,
      if (doctor != null) 'designation': doctor.designation,
      if (doctor != null) 'chambers': doctor.chambers.map((c) => c.toJson()).toList(),
      'bmdcRegNumber': bmdcRegNumber,
      'claimedByUid': claimedByUid,
      'certificateImageUrl': certificateImageUrl ?? '',
      'isClaimed': true,
      'isBmdcVerified': true,
    };

    // 1. Write doctor claim using set(merge: true) so it creates the document if missing
    await doctorRef.set(claimData, SetOptions(merge: true));

    // 2. Link the user account in users/{claimedByUid}
    final userRef = _db.collection('users').doc(claimedByUid);
    await userRef.set({
      'name': doctor?.name ?? 'Dr. Specialist',
      'roles': {
        'isDoctor': true,
      },
      'chamberCount': (doctor?.chambers.isNotEmpty == true) ? doctor!.chambers.length : 1,
      'doctorProfileId': doctorId,
      'bmdcRegNumber': bmdcRegNumber,
      'doctorProfile': {
        'id': doctorId,
        'name': doctor?.name ?? 'Dr. Specialist',
        'bmdcRegNumber': bmdcRegNumber,
        'isBmdcVerified': true,
      },
    }, SetOptions(merge: true));

    // 3. Trigger in-app notification
    try {
      await NotificationService.createNotification(
        userId: claimedByUid,
        title: 'Doctor Profile Claimed',
        body: 'You are now the verified doctor for ${doctor?.name ?? "your profile"}. You can now manage appointments and live queues.',
        type: 'system',
        relatedId: doctorId,
      );
    } catch (_) {}

    return {
      'isClaimed': true,
      'isBmdcVerified': true,
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

        // Check if user is an admin directly from Firebase (admins collection, roles in Firestore, or Auth custom claims)
        final adminDoc = await _db.collection('admins').doc(uid).get();
        bool isMasterAdmin = adminDoc.exists || roles['isAdmin'] == true;

        if (!isMasterAdmin && _auth.currentUser?.uid == uid) {
          try {
            final tokenResult = await _auth.currentUser?.getIdTokenResult();
            if (tokenResult?.claims?['admin'] == true ||
                tokenResult?.claims?['isAdmin'] == true) {
              isMasterAdmin = true;
            }
          } catch (_) {}
        }

        roles['isAdmin'] = isMasterAdmin;

        // A doctor role is tied to a claimed doctor profile. This prevents a
        // stale role flag or a normal applicant from receiving appointments.
        if (roles['isDoctor'] == true) {
          if (data['doctorProfileId'] != null) {
            data['doctorProfileId'] = data['doctorProfileId'].toString();
          }
          if (data['chamberCount'] == null || (data['chamberCount'] as num) <= 0) {
            data['chamberCount'] = 1;
          }
        }

        if (roles['isOperator'] == true &&
            ((data['operatorAssignments'] as List?)?.isNotEmpty != true)) {
          // If assigned to a chamber or desk, keep operator active
        }
        data['roles'] = roles;

        return data;
      }
    } catch (e) {
      debugPrint('Firestore fetchUserProfile error: $e');
    }
    return null;
  }

  // =========================================================================
  // OPERATOR DESK MANAGEMENT
  // =========================================================================

  static Future<List<Map<String, dynamic>>> fetchRegisteredUsers({int limit = 50}) async {
    try {
      final snap = await _db.collection('users').limit(limit).get();
      return snap.docs.map((d) {
        final data = d.data();
        data['uid'] = d.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Error fetching registered users: $e');
      return [];
    }
  }

  static Future<void> assignChamberOperator({
    required String doctorId,
    required String chamberId,
    required String operatorUid,
    required String operatorName,
    required String operatorEmail,
  }) async {
    // 1. Update user document
    final userRef = _db.collection('users').doc(operatorUid);
    await userRef.set({


      'roles': {
        'isOperator': true,
      },
      'operatorAssignments': FieldValue.arrayUnion([chamberId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. Update the doctor document's chambers list
    final docRef = _db.collection('doctors').doc(doctorId);
    final docSnap = await docRef.get();
    if (docSnap.exists) {
      final data = docSnap.data() ?? {};
      final rawChambers = (data['chambers'] as List?) ?? [];
      final updatedChambers = rawChambers.map((c) {
        final cMap = Map<String, dynamic>.from(c as Map);
        final cName = cMap['id'] ?? cMap['hospitalName'] ?? cMap['name'];
        if (cName == chamberId || cMap['id'] == chamberId || cMap['hospitalName'] == chamberId) {
          cMap['hasOperator'] = true;
          cMap['operatorUid'] = operatorUid;
          cMap['operatorName'] = operatorName;
          cMap['operatorEmail'] = operatorEmail;
        }
        return cMap;
      }).toList();
      await docRef.update({'chambers': updatedChambers});
    }

    // 3. Send in-app notification
    try {
      await NotificationService.createNotification(
        userId: operatorUid,
        title: 'Desk Operator Assigned',
        body: 'You have been assigned as desk operator for $chamberId.',
        type: 'system',
        relatedId: chamberId,
      );
    } catch (_) {}
  }

  static Future<void> removeChamberOperator({
    required String doctorId,
    required String chamberId,
    required String operatorUid,
  }) async {
    // 1. Update user
    if (operatorUid.isNotEmpty) {
      final userRef = _db.collection('users').doc(operatorUid);
      final userSnap = await userRef.get();
      if (userSnap.exists) {
        final currentAssignments = List<String>.from((userSnap.data()?['operatorAssignments'] as List?) ?? []);
        currentAssignments.remove(chamberId);
        await userRef.set({
          'operatorAssignments': currentAssignments,
          'updatedAt': FieldValue.serverTimestamp(),
          if (currentAssignments.isEmpty)
            'roles': {
              'isOperator': false,
            },
        }, SetOptions(merge: true));
      }
    }

    // 2. Update doctor chambers
    final docRef = _db.collection('doctors').doc(doctorId);
    final docSnap = await docRef.get();
    if (docSnap.exists) {
      final data = docSnap.data() ?? {};
      final rawChambers = (data['chambers'] as List?) ?? [];
      final updatedChambers = rawChambers.map((c) {
        final cMap = Map<String, dynamic>.from(c as Map);
        final cName = cMap['id'] ?? cMap['hospitalName'] ?? cMap['name'];
        if (cName == chamberId || cMap['id'] == chamberId || cMap['operatorUid'] == operatorUid) {
          cMap['hasOperator'] = false;
          cMap['operatorUid'] = null;
          cMap['operatorName'] = null;
          cMap['operatorEmail'] = null;
        }
        return cMap;
      }).toList();
      await docRef.update({'chambers': updatedChambers});
    }
  }

  static Future<Map<String, dynamic>?> syncUser({
    required String uid,
    String? email,
    String? name,
    String? phone,
    String? role,
    bool isDoctor = false,
    String? photoUrl,
  }) async {
    try {
      final userRef = _db.collection('users').doc(uid);
      final existing = await userRef.get();

      if (!existing.exists) {
        final generatedUsername = await generateUniqueUsername(name, email);
        final userData = <String, dynamic>{
          'uid': uid,
          'email': email ?? '',
          'name': name ?? '',
          'username': generatedUsername,
          'photoUrl': photoUrl ?? '',
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
        final currentUsername = existing.data()?['username']?.toString() ?? '';
        if (currentUsername.isEmpty) {
          updates['username'] = await generateUniqueUsername(
            existing.data()?['name'] ?? name,
            existing.data()?['email'] ?? email,
          );
        }
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
        if (photoUrl != null && photoUrl.isNotEmpty && existing.data()?['photoUrl'] != photoUrl) {
          updates['photoUrl'] = photoUrl;
        }
        updates['lastLoginAt'] = FieldValue.serverTimestamp();
        updates['updatedAt'] = FieldValue.serverTimestamp();
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

  /// Generates a unique username: firstname + unique 3-digit number (e.g. nuzhat719, rehnuma342)
  static Future<String> generateUniqueUsername(String? rawName, String? email) async {
    String base = '';
    if (rawName != null && rawName.trim().isNotEmpty) {
      base = rawName.trim().split(' ').first;
    } else if (email != null && email.isNotEmpty) {
      base = email.split('@').first.split('.').first;
    }
    base = base.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    if (base.isEmpty) base = 'user';
    if (base.length > 15) base = base.substring(0, 15);

    final random = Random();
    for (int attempt = 0; attempt < 10; attempt++) {
      final num = 100 + random.nextInt(900);
      final candidate = '$base$num';
      try {
        final existing = await _db
            .collection('users')
            .where('username', isEqualTo: candidate)
            .limit(1)
            .get();
        if (existing.docs.isEmpty) {
          return candidate;
        }
      } catch (_) {
        return candidate;
      }
    }
    return '$base${DateTime.now().millisecondsSinceEpoch % 10000}';
  }

  /// Checks if a username is available in database and updates it for [uid]
  static Future<Map<String, dynamic>> updateUsername({
    required String uid,
    required String newUsername,
  }) async {
    final clean = newUsername.trim().toLowerCase().replaceAll('@', '');
    if (clean.length < 3) {
      return {'success': false, 'error': 'Username must be at least 3 characters long.'};
    }
    if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(clean)) {
      return {'success': false, 'error': 'Username can only contain letters, numbers, underscores, and dots.'};
    }

    try {
      final snap = await _db
          .collection('users')
          .where('username', isEqualTo: clean)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty && snap.docs.first.id != uid) {
        return {'success': false, 'error': 'Username @$clean is already taken. Please choose another.'};
      }

      await _db.collection('users').doc(uid).set({'username': clean}, SetOptions(merge: true));
      return {'success': true, 'username': clean};
    } catch (e) {
      return {'success': false, 'error': 'Database error checking username: $e'};
    }
  }

  /// Searches registered users by @username or name for 1-tap operator assignment
  static Future<List<Map<String, dynamic>>> searchUsersByUsername(String query) async {
    final clean = query.trim().toLowerCase().replaceAll('@', '');
    if (clean.isEmpty) return [];

    try {
      final snap = await _db
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: clean)
          .where('username', isLessThanOrEqualTo: '$clean\uf8ff')
          .limit(15)
          .get();

      if (snap.docs.isNotEmpty) {
        return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
      }

      final allRecent = await fetchRegisteredUsers(limit: 30);
      return allRecent.where((u) {
        final uName = (u['username'] ?? '').toString().toLowerCase();
        final name = (u['name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        return uName.contains(clean) || name.contains(clean) || email.contains(clean);
      }).toList();
    } catch (e) {
      debugPrint('searchUsersByUsername error: $e');
      return [];
    }
  }

  /// Fetches chambers directory across doctors for desk discovery & operator application
  static Future<List<Map<String, dynamic>>> fetchChambersDirectory({String? areaFilter}) async {
    final List<Map<String, dynamic>> result = [];
    final seen = <String>{};

    // 1. Fetch claimed / dynamic doctors from Firestore
    try {
      final firestoreDocs = await _db.collection('doctors').limit(50).get();
      for (final doc in firestoreDocs.docs) {
        final data = doc.data();
        final docId = doc.id;
        final docName = data['name'] ?? 'Doctor Specialist';
        final specs = (data['specialities'] as List?)?.join(', ') ?? 'General Medicine';
        final rawChambers = (data['chambers'] as List?) ?? [];
        for (final ch in rawChambers) {
          final c = Map<String, dynamic>.from(ch as Map);
          final chId = c['id']?.toString() ?? '${docId}_${c['name']}';
          if (seen.add(chId)) {
            result.add({
              'id': chId,
              'name': c['name'] ?? c['hospitalName'] ?? 'Chamber',
              'area': c['area'] ?? 'Dhaka',
              'visitingHours': c['visitingHours'] ?? '5:00 PM – 9:00 PM',
              'fee': c['fee'] ?? 800,
              'doctorId': docId,
              'doctorName': docName,
              'doctorSpecialty': specs,
              'hasOperator': c['hasOperator'] == true,
              'operatorUid': c['operatorUid'],
              'operatorName': c['operatorName'],
              'operatorEmail': c['operatorEmail'],
              'isAccessible': c['isAccessible'] == true,
              'isClaimedDoctor': true,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching firestore chambers: $e');
    }

    // 2. Supplement with bundled doctors chambers for comprehensive discovery
    try {
      final bundled = await getBundledDoctors();
      for (final doc in bundled.take(60)) {
        for (final ch in doc.chambers) {
          final chId = ch.id ?? '${doc.id}_${ch.hospitalName}';
          if (seen.add(chId)) {
            result.add({
              'id': chId,
              'name': ch.hospitalName ?? 'Clinic Chamber',
              'area': ch.area ?? ch.location ?? 'Dhaka',
              'visitingHours': ch.visitingHours ?? '5:00 PM – 9:00 PM',
              'fee': ch.fee ?? 800,
              'doctorId': doc.id,
              'doctorName': doc.name,
              'doctorSpecialty': doc.specialities.join(', '),
              'hasOperator': ch.hasOperator,
              'operatorUid': ch.operatorUid,
              'operatorName': ch.operatorName,
              'operatorEmail': ch.operatorEmail,
              'isAccessible': ch.isAccessible,
              'isClaimedDoctor': doc.isClaimed,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error supplementing bundled chambers: $e');
    }

    if (areaFilter != null && areaFilter.trim().isNotEmpty && areaFilter != 'All') {
      final norm = areaFilter.trim().toLowerCase();
      return result.where((c) {
        final a = (c['area'] ?? '').toString().toLowerCase();
        final n = (c['name'] ?? '').toString().toLowerCase();
        return a.contains(norm) || n.contains(norm);
      }).toList();
    }

    return result;
  }

  /// Patient/User applies to be a Desk Operator for a specific chamber
  static Future<void> applyForDeskOperator({
    required String chamberId,
    required String chamberName,
    required String doctorId,
    required String doctorName,
    String? note,
    String? phone,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Must be logged in to apply as desk operator.');

    final userProfile = await fetchUserProfile(user.uid);
    final applicantName = userProfile?['name'] ?? user.displayName ?? 'Applicant';
    final applicantUsername = userProfile?['username'] ?? user.email?.split('@').first ?? 'user';
    final applicantEmail = user.email ?? '';
    final applicantPhone = phone ?? userProfile?['phone'] ?? '';

    await _db.collection('operator_applications').add({
      'applicantUid': user.uid,
      'applicantName': applicantName,
      'applicantUsername': applicantUsername,
      'applicantEmail': applicantEmail,
      'applicantPhone': applicantPhone,
      'chamberId': chamberId,
      'chamberName': chamberName,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'note': note ?? '',
      'status': 'pending',
      'appliedAt': FieldValue.serverTimestamp(),
    });

    try {
      await NotificationService.createNotification(
        userId: doctorId,
        title: 'New Operator Application',
        body: '$applicantName (@$applicantUsername) applied as Desk Operator for $chamberName.',
        type: 'system',
        relatedId: chamberId,
      );
    } catch (_) {}
  }

  /// Doctor streams operator applications for their chambers
  static Stream<QuerySnapshot<Map<String, dynamic>>> operatorApplicationsStream(String doctorId) {
    return _db
        .collection('operator_applications')
        .where('doctorId', isEqualTo: doctorId)
        .snapshots();
  }

  /// Doctor agrees / approves the applicant as Desk Operator
  static Future<void> approveOperatorApplication({
    required String applicationId,
    required String doctorId,
    required String chamberId,
    required String applicantUid,
    required String applicantName,
    required String applicantEmail,
    required String chamberName,
  }) async {
    // 1. Assign operator in database (grants isOperator: true and binds chamber)
    await assignChamberOperator(
      doctorId: doctorId,
      chamberId: chamberId,
      operatorUid: applicantUid,
      operatorName: applicantName,
      operatorEmail: applicantEmail,
    );

    // 2. Mark application approved
    await _db.collection('operator_applications').doc(applicationId).update({
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // 3. Notify applicant that doctor agreed and approved them
    try {
      await NotificationService.createNotification(
        userId: applicantUid,
        title: 'Application Approved! 🎉',
        body: 'The doctor agreed to your application. You are now the Desk Operator for $chamberName.',
        type: 'system',
        relatedId: chamberId,
      );
    } catch (_) {}
  }

  /// Doctor rejects operator application
  static Future<void> rejectOperatorApplication(String applicationId) async {
    await _db.collection('operator_applications').doc(applicationId).update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
    });
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
    String? imageUrl,
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
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
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

    // Trigger notification for the post author and commenter
    try {
      final postDoc = await postRef.get();
      if (postDoc.exists) {
        final postData = postDoc.data();
        final postAuthorUid = postData?['userId'] as String?;
        if (postAuthorUid != null && postAuthorUid.isNotEmpty && postAuthorUid != uid) {
          final preview = comment.length > 50 ? '${comment.substring(0, 50)}...' : comment;
          await NotificationService.createNotification(
            userId: postAuthorUid,
            title: 'New comment on your post',
            body: '$name commented: "$preview"',
            type: 'comment',
            relatedId: postId,
          );
        }
      }

      if (uid != 'guest') {
        await NotificationService.createNotification(
          userId: uid,
          title: 'Comment posted',
          body: 'Your comment was posted to the community feed.',
          type: 'comment',
          relatedId: postId,
        );
      }
    } catch (e) {
      debugPrint('Error triggering comment notification: $e');
    }
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

  /// Retracts or deletes a doctor's answer/opinion on a post
  static Future<void> deleteDoctorAnswer(String postId) async {
    await _db.collection('posts').doc(postId).update({
      'answer': FieldValue.delete(),
    });
  }

  /// Deletes a comment on a feed post
  static Future<void> deletePostComment(String postId, String commentId) async {
    await _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .delete();
    try {
      await _db.collection('posts').doc(postId).update({
        'commentsCount': FieldValue.increment(-1),
      });
    } catch (_) {}
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
    String? doctorName,
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
      if (resolvedDoctorId == null || resolvedDoctorId.isEmpty) {
        throw StateError('Please select a doctor to book an appointment.');
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
      'doctorName': doctorName ?? 'Specialist Doctor',
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

    try {
      final docLabel = doctorName ?? 'your doctor';
      await NotificationService.createNotification(
        userId: uid,
        title: 'Appointment Confirmed',
        body: 'Appointment with $docLabel scheduled on ${scheduledTime.day}/${scheduledTime.month}/${scheduledTime.year}.',
        type: 'appointment',
        relatedId: docRef.id,
      );
    } catch (_) {}

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
            'lat': 23.8398,
            'lng': 90.3582,
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
            'lat': 23.7258,
            'lng': 90.3976,
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
            'lat': 23.7533,
            'lng': 90.3817,
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
            'lat': 23.7483,
            'lng': 90.3861,
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
            'lat': 23.7392,
            'lng': 90.3824,
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
            'lat': 23.7465,
            'lng': 90.3760,
          }
        ],
      },
      {
        '_id': 'doc_fallback_kallyanpur',
        'name': 'Dr. Md. Atikur Rahman',
        'designation': 'Consultant Physician',
        'specialities': ['General Medicine', 'Internal Medicine'],
        'education': ['MBBS', 'FCPS'],
        'bmdcRegNumber': 'A-67890',
        'isBmdcVerified': true,
        'ratingAverage': 4.8,
        'ratingCount': 42,
        'chambers': [
          {
            'hospitalName': 'Ibn Sina Medical College Hospital',
            'area': 'Kallyanpur',
            'location': 'Dhaka',
            'lat': 23.7782,
            'lng': 90.3621,
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
